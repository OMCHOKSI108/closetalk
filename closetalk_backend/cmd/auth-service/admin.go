package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

// ── User Management ─────────────────────────────────────────────

func handleAdminListUsers(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	ctx := context.Background()

	type adminUser struct {
		ID          string `json:"id"`
		Email       string `json:"email"`
		DisplayName string `json:"display_name"`
		Username    string `json:"username"`
		IsActive    bool   `json:"is_active"`
		IsAdmin     bool   `json:"is_admin"`
		CreatedAt   string `json:"created_at"`
	}

	var users []adminUser

	querySQL := `SELECT id, COALESCE(email,''), display_name, COALESCE(username,''), is_active, is_admin, COALESCE(created_at::text,'')
				 FROM users WHERE deleted_at IS NULL`
	args := []any{}

	if query != "" {
		querySQL += ` AND (username ILIKE $1 OR display_name ILIKE $1 OR COALESCE(email,'') ILIKE $1)`
		args = append(args, "%"+query+"%")
	}
	querySQL += ` ORDER BY created_at DESC LIMIT 50`

	rows, qErr := database.Pool.Query(ctx, querySQL, args...)
	if qErr != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "query failed"})
		return
	}
	defer rows.Close()

	for rows.Next() {
		var u adminUser
		if err := rows.Scan(&u.ID, &u.Email, &u.DisplayName, &u.Username, &u.IsActive, &u.IsAdmin, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		users = []adminUser{}
	}
	if users == nil {
		users = []adminUser{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"users": users})
}

func handleAdminGetUser(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()

	var deviceCount, groupCount, convCount int
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM user_devices WHERE user_id = $1`, targetUserID).Scan(&deviceCount)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM group_members WHERE user_id = $1 AND left_at IS NULL`, targetUserID).Scan(&groupCount)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM conversation_participants WHERE user_id = $1`, targetUserID).Scan(&convCount)

	type userDetail struct {
		ID                string `json:"id"`
		Email             string `json:"email"`
		DisplayName       string `json:"display_name"`
		Username          string `json:"username"`
		IsActive          bool   `json:"is_active"`
		IsAdmin           bool   `json:"is_admin"`
		CreatedAt         string `json:"created_at"`
		LastSeen          string `json:"last_seen"`
		DeviceCount       int    `json:"device_count"`
		GroupCount        int    `json:"group_count"`
		ConversationCount int    `json:"conversation_count"`
	}

	var u userDetail
	err := database.Pool.QueryRow(ctx,
		`SELECT id, COALESCE(email,''), display_name, COALESCE(username,''),
		        is_active, is_admin, COALESCE(created_at::text,''), COALESCE(last_seen::text,'')
		 FROM users WHERE id = $1 AND deleted_at IS NULL`, targetUserID,
	).Scan(&u.ID, &u.Email, &u.DisplayName, &u.Username, &u.IsActive, &u.IsAdmin, &u.CreatedAt, &u.LastSeen)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "user not found"})
		return
	}
	u.DeviceCount = deviceCount
	u.GroupCount = groupCount
	u.ConversationCount = convCount

	writeJSON(w, http.StatusOK, u)
}

func handleAdminDisableUser(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()
	var isActive bool
	err := database.Pool.QueryRow(ctx,
		`SELECT is_active FROM users WHERE id = $1 AND deleted_at IS NULL`, targetUserID,
	).Scan(&isActive)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "user not found"})
		return
	}
	newStatus := !isActive
	_, err = database.Pool.Exec(ctx,
		`UPDATE users SET is_active = $1, updated_at = now() WHERE id = $2`,
		newStatus, targetUserID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to update user"})
		return
	}
	if !newStatus {
		database.Valkey.Del(ctx, "user_sessions:"+targetUserID)
	}
	writeJSON(w, http.StatusOK, map[string]any{"is_active": newStatus})
}

func handleAdminDeleteUser(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()
	_, err := database.Pool.Exec(ctx, `UPDATE users SET deleted_at = now(), is_active = false WHERE id = $1 AND deleted_at IS NULL`, targetUserID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to delete user"})
		return
	}
	database.Valkey.Del(ctx, "user_sessions:"+targetUserID)
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func handleAdminBatchDeleteUsers(w http.ResponseWriter, r *http.Request) {
	var req struct {
		UserIDs []string `json:"user_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.UserIDs) == 0 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "user_ids array required"})
		return
	}
	ctx := context.Background()
	for _, uid := range req.UserIDs {
		database.Pool.Exec(ctx, `UPDATE users SET deleted_at = now(), is_active = false WHERE id = $1 AND deleted_at IS NULL`, uid)
		database.Valkey.Del(ctx, "user_sessions:"+uid)
	}
	writeJSON(w, http.StatusOK, map[string]any{"deleted": len(req.UserIDs)})
}

func handleAdminUserDevices(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()

	type deviceEntry struct {
		ID         string `json:"id"`
		DeviceName string `json:"device_name"`
		DeviceType string `json:"device_type"`
		Platform   string `json:"platform"`
		AppVersion string `json:"app_version"`
		IsActive   bool   `json:"is_active"`
		LastActive string `json:"last_active"`
		LinkedAt   string `json:"linked_at"`
	}

	rows, err := database.Pool.Query(ctx,
		`SELECT id, COALESCE(device_name,''), COALESCE(device_type,''), COALESCE(platform,''),
		        COALESCE(app_version,''), is_active, COALESCE(last_active::text,''), COALESCE(linked_at::text,'')
		 FROM user_devices WHERE user_id = $1 ORDER BY last_active DESC`, targetUserID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "query failed"})
		return
	}
	defer rows.Close()

	devices := []deviceEntry{}
	for rows.Next() {
		var d deviceEntry
		rows.Scan(&d.ID, &d.DeviceName, &d.DeviceType, &d.Platform, &d.AppVersion, &d.IsActive, &d.LastActive, &d.LinkedAt)
		devices = append(devices, d)
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func handleAdminForceLogout(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()

	iter := database.Valkey.Scan(ctx, 0, "session:*"+targetUserID+"*", 1000).Iterator()
	for iter.Next(ctx) {
		database.Valkey.Del(ctx, iter.Val())
	}
	database.Valkey.Del(ctx, "user_sessions:"+targetUserID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func handleAdminResetPassword(w http.ResponseWriter, r *http.Request) {
	targetUserID := chi.URLParam(r, "userId")
	ctx := context.Background()

	var exists bool
	database.Pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL)`, targetUserID).Scan(&exists)
	if !exists {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "user not found"})
		return
	}

	b := make([]byte, 12)
	rand.Read(b)
	tempPass := hex.EncodeToString(b)

	hash, err := auth.HashPassword(tempPass)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to generate password"})
		return
	}
	database.Pool.Exec(ctx, `UPDATE users SET password_hash = $1 WHERE id = $2`, hash, targetUserID)
	database.Valkey.Del(ctx, "user_sessions:"+targetUserID)

	writeJSON(w, http.StatusOK, map[string]string{"temporary_password": tempPass})
}

// ── Group Management ────────────────────────────────────────────

func handleAdminListGroups(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	type groupEntry struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Description string `json:"description"`
		IsPublic    bool   `json:"is_public"`
		MemberCount int    `json:"member_count"`
		CreatedBy   string `json:"created_by"`
		CreatedAt   string `json:"created_at"`
	}

	rows, err := database.Pool.Query(ctx,
		`SELECT g.id, g.name, COALESCE(g.description,''), g.is_public,
		        (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = g.id AND gm.left_at IS NULL) as member_count,
		        COALESCE(g.created_by::text,''), COALESCE(g.created_at::text,'')
		 FROM groups g ORDER BY g.created_at DESC LIMIT 50`,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "query failed"})
		return
	}
	defer rows.Close()

	groups := []groupEntry{}
	for rows.Next() {
		var g groupEntry
		rows.Scan(&g.ID, &g.Name, &g.Description, &g.IsPublic, &g.MemberCount, &g.CreatedBy, &g.CreatedAt)
		groups = append(groups, g)
	}
	if groups == nil {
		groups = []groupEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": groups})
}

func handleAdminGetGroup(w http.ResponseWriter, r *http.Request) {
	groupID := chi.URLParam(r, "groupId")
	ctx := context.Background()

	type groupDetail struct {
		ID               string `json:"id"`
		Name             string `json:"name"`
		Description      string `json:"description"`
		IsPublic         bool   `json:"is_public"`
		MemberLimit      int    `json:"member_limit"`
		InviteCode       string `json:"invite_code"`
		MessageRetention string `json:"message_retention"`
		DisappearingMsg  string `json:"disappearing_msg"`
		MemberCount      int    `json:"member_count"`
		CreatedBy        string `json:"created_by"`
		CreatedAt        string `json:"created_at"`
	}

	var g groupDetail
	err := database.Pool.QueryRow(ctx,
		`SELECT g.id, g.name, COALESCE(g.description,''), g.is_public, g.member_limit,
		        COALESCE(g.invite_code,''), COALESCE(g.message_retention,'off'), COALESCE(g.disappearing_msg,'off'),
		        (SELECT COUNT(*) FROM group_members gm WHERE gm.group_id = g.id AND gm.left_at IS NULL),
		        COALESCE(g.created_by::text,''), COALESCE(g.created_at::text,'')
		 FROM groups g WHERE g.id = $1`, groupID,
	).Scan(&g.ID, &g.Name, &g.Description, &g.IsPublic, &g.MemberLimit, &g.InviteCode, &g.MessageRetention, &g.DisappearingMsg, &g.MemberCount, &g.CreatedBy, &g.CreatedAt)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "group not found"})
		return
	}
	writeJSON(w, http.StatusOK, g)
}

func handleAdminDeleteGroup(w http.ResponseWriter, r *http.Request) {
	groupID := chi.URLParam(r, "groupId")
	ctx := context.Background()

	_, err := database.Pool.Exec(ctx, `UPDATE groups SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL`, groupID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to delete group"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// ── Push Broadcast ──────────────────────────────────────────────

func handleAdminBroadcast(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Title   string `json:"title"`
		Message string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Message == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "title and message required"})
		return
	}
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx, `SELECT DISTINCT token FROM notification_tokens WHERE token IS NOT NULL`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "query failed"})
		return
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var t string
		rows.Scan(&t)
		tokens = append(tokens, t)
	}

	go func() {
		for _, token := range tokens {
			err := sendFCMNotification(token, req.Title, req.Message)
			if err != nil {
				log.Printf("[broadcast] fcm error: %v", err)
			}
		}
	}()

	writeJSON(w, http.StatusOK, map[string]any{"sent": len(tokens)})
}

// ── Security (Blocked IPs) ──────────────────────────────────────

func handleAdminListBlockedIPs(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	keys, err := database.Valkey.Keys(ctx, "blocked_ip:*").Result()
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "query failed"})
		return
	}

	type ipEntry struct {
		IP        string `json:"ip"`
		BlockedAt string `json:"blocked_at"`
		Reason    string `json:"reason"`
	}

	entries := []ipEntry{}
	for _, k := range keys {
		val, _ := database.Valkey.Get(ctx, k).Result()
		ip := strings.TrimPrefix(k, "blocked_ip:")
		entries = append(entries, ipEntry{IP: ip, BlockedAt: val, Reason: "manual block"})
	}
	if entries == nil {
		entries = []ipEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"blocked_ips": entries})
}

func handleAdminBlockIP(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IP     string `json:"ip"`
		Reason string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.IP == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "ip required"})
		return
	}
	ctx := context.Background()
	if req.Reason == "" {
		req.Reason = "manual block"
	}
	database.Valkey.Set(ctx, "blocked_ip:"+req.IP, time.Now().Format(time.RFC3339), 0)
	writeJSON(w, http.StatusOK, map[string]string{"status": "blocked"})
}

func handleAdminUnblockIP(w http.ResponseWriter, r *http.Request) {
	ip := chi.URLParam(r, "ip")
	ctx := context.Background()
	database.Valkey.Del(ctx, "blocked_ip:"+ip)
	writeJSON(w, http.StatusOK, map[string]string{"status": "unblocked"})
}

// ── Enhanced Analytics ──────────────────────────────────────────

func handleAdminEnhancedAnalytics(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	var totalUsers, activeToday, signupsToday int
	var dau7d, totalMessages, totalReports int

	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`).Scan(&totalUsers)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE last_seen > now() - interval '24 hours' AND deleted_at IS NULL`).Scan(&activeToday)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE created_at > now() - interval '24 hours' AND deleted_at IS NULL`).Scan(&signupsToday)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE last_seen > now() - interval '7 days' AND deleted_at IS NULL`).Scan(&dau7d)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM conversations WHERE created_at > now() - interval '24 hours'`).Scan(&totalMessages)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM reports`).Scan(&totalReports)

	// Daily signups for last 7 days
	type dailyPoint struct {
		Date  string `json:"date"`
		Count int    `json:"count"`
	}
	daily := []dailyPoint{}
	dRows, _ := database.Pool.Query(ctx,
		`SELECT to_char(d::date,'YYYY-MM-DD'), COALESCE(COUNT(u.id),0)
		 FROM generate_series(now() - interval '6 days', now(), interval '1 day') d
		 LEFT JOIN users u ON date_trunc('day', u.created_at) = date_trunc('day', d)
		 GROUP BY d ORDER BY d`,
	)
	if dRows != nil {
		defer dRows.Close()
		for dRows.Next() {
			var p dailyPoint
			dRows.Scan(&p.Date, &p.Count)
			daily = append(daily, p)
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"total_users":    totalUsers,
		"active_today":   activeToday,
		"signups_today":  signupsToday,
		"dau_7d":         dau7d,
		"total_messages": totalMessages,
		"total_reports":  totalReports,
		"daily_signups":  daily,
	})
}

// ── Feature Flags ───────────────────────────────────────────────

func handleAdminListFlags(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT id, name, COALESCE(description,''), enabled, rollout_percent, created_at, updated_at
		 FROM feature_flags ORDER BY name`,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list flags"})
		return
	}
	defer rows.Close()

	type flagEntry struct {
		ID             string `json:"id"`
		Name           string `json:"name"`
		Description    string `json:"description"`
		Enabled        bool   `json:"enabled"`
		RolloutPercent int    `json:"rollout_percent"`
		CreatedAt      string `json:"created_at"`
		UpdatedAt      string `json:"updated_at"`
	}
	flags := []flagEntry{}
	for rows.Next() {
		var f flagEntry
		rows.Scan(&f.ID, &f.Name, &f.Description, &f.Enabled, &f.RolloutPercent, &f.CreatedAt, &f.UpdatedAt)
		flags = append(flags, f)
	}
	if flags == nil {
		flags = []flagEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"flags": flags})
}

type updateFlagRequest struct {
	Enabled        *bool `json:"enabled,omitempty"`
	RolloutPercent *int  `json:"rollout_percent,omitempty"`
}

func handleAdminUpdateFlag(w http.ResponseWriter, r *http.Request) {
	flagID := chi.URLParam(r, "id")
	var req updateFlagRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	ctx := context.Background()
	if req.Enabled != nil {
		database.Pool.Exec(ctx,
			`UPDATE feature_flags SET enabled = $1, updated_at = now() WHERE id = $2`,
			*req.Enabled, flagID,
		)
		var key string
		database.Pool.QueryRow(ctx, `SELECT name FROM feature_flags WHERE id = $1`, flagID).Scan(&key)
		if key != "" {
			val := "0"
			if *req.Enabled {
				val = "1"
			}
			database.Valkey.Set(ctx, "feature_flag:"+key, val, 5*time.Second)
		}
	}
	if req.RolloutPercent != nil {
		database.Pool.Exec(ctx,
			`UPDATE feature_flags SET rollout_percent = $1, updated_at = now() WHERE id = $2`,
			*req.RolloutPercent, flagID,
		)
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// ── Audit Log ───────────────────────────────────────────────────

func handleAdminAuditLog(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT id, admin_id, action, target_type, COALESCE(target_id,''), COALESCE(details::text,'{}'), created_at
		 FROM audit_log ORDER BY created_at DESC LIMIT 100`,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to get audit log"})
		return
	}
	defer rows.Close()

	type logEntry struct {
		ID         string `json:"id"`
		AdminID    string `json:"admin_id"`
		Action     string `json:"action"`
		TargetType string `json:"target_type"`
		TargetID   string `json:"target_id"`
		Details    string `json:"details"`
		CreatedAt  string `json:"created_at"`
	}
	entries := []logEntry{}
	for rows.Next() {
		var e logEntry
		rows.Scan(&e.ID, &e.AdminID, &e.Action, &e.TargetType, &e.TargetID, &e.Details, &e.CreatedAt)
		entries = append(entries, e)
	}
	if entries == nil {
		entries = []logEntry{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
}

// ── Helper ──────────────────────────────────────────────────────

func sendFCMNotification(token, title, message string) error {
	return fmt.Errorf("FCM not implemented: %s %s %s", token, title, message)
}
