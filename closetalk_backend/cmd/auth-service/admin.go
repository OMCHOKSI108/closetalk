package main

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

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

func handleAdminGetAnalytics(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	var totalUsers, activeToday, signupsToday int
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`).Scan(&totalUsers)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE last_seen > now() - interval '24 hours' AND deleted_at IS NULL`).Scan(&activeToday)
	database.Pool.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE created_at > now() - interval '24 hours' AND deleted_at IS NULL`).Scan(&signupsToday)

	writeJSON(w, http.StatusOK, map[string]any{
		"total_users":   totalUsers,
		"active_today":  activeToday,
		"signups_today": signupsToday,
	})
}

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
