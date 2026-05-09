package main

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"log"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

func generateInviteCode() (string, error) {
	const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	code := make([]byte, 12)
	for i := range code {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		code[i] = charset[n.Int64()]
	}
	return string(code), nil
}

func handleCreateGroup(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	parsedUserID := model.ParseUUID(userID)

	var req model.CreateGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Name == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "group name is required"})
		return
	}
	if len(req.Name) > 100 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "group name too long (max 100)"})
		return
	}

	ctx := context.Background()
	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to create group"})
		return
	}
	defer tx.Rollback(ctx)

	// Create conversation
	var convID uuid.UUID
	err = tx.QueryRow(ctx,
		`INSERT INTO conversations (type) VALUES ('group') RETURNING id`,
	).Scan(&convID)
	if err != nil {
		log.Printf("[groups] conversation insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to create group"})
		return
	}

	// Create group
	memberLimit := 1000
	var groupID uuid.UUID
	err = tx.QueryRow(ctx,
		`INSERT INTO groups (conversation_id, name, description, avatar_url, created_by, is_public, member_limit)
		 VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
		convID, req.Name, req.Description, req.AvatarURL, parsedUserID, req.IsPublic, memberLimit,
	).Scan(&groupID)
	if err != nil {
		log.Printf("[groups] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to create group"})
		return
	}

	// Add creator as admin
	_, err = tx.Exec(ctx,
		`INSERT INTO group_members (group_id, user_id, role, invited_by) VALUES ($1, $2, 'admin', $2)`,
		groupID, parsedUserID,
	)
	if err != nil {
		log.Printf("[groups] member insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to add creator"})
		return
	}

	// Add creator as conversation participant
	_, err = tx.Exec(ctx,
		`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2)`,
		convID, parsedUserID,
	)
	if err != nil {
		log.Printf("[groups] participant insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to add participant"})
		return
	}

	// Add members
	for _, memberIDStr := range req.MemberIDs {
		memberID := model.ParseUUID(memberIDStr)
		if memberID == parsedUserID {
			continue
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO group_members (group_id, user_id, role, invited_by) VALUES ($1, $2, 'member', $3)
			 ON CONFLICT DO NOTHING`,
			groupID, memberID, parsedUserID,
		)
		if err != nil {
			log.Printf("[groups] member insert error for %s: %v", memberIDStr, err)
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2)
			 ON CONFLICT DO NOTHING`,
			convID, memberID,
		)
		if err != nil {
			log.Printf("[groups] participant insert error for %s: %v", memberIDStr, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		log.Printf("[groups] commit error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to create group"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"group_id": groupID,
		"name":     req.Name,
		"status":   "created",
	})
}

func handleGetGroup(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)

	ctx := context.Background()

	// Check membership
	var isMember bool
	database.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2)`,
		groupID, model.ParseUUID(userID),
	).Scan(&isMember)
	if !isMember {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "NOT_MEMBER", Message: "you are not a member of this group"})
		return
	}

	var g model.Group
	err := database.Pool.QueryRow(ctx,
		`SELECT g.id, g.conversation_id, g.name, COALESCE(g.description, ''), COALESCE(g.avatar_url, ''),
		        g.created_by, g.is_public, g.member_limit, g.created_at, g.updated_at,
		        COALESCE(g.invite_code, ''), COALESCE(gs.message_retention, 'off'), COALESCE(gs.disappearing_msg, 'off'),
		        (SELECT COUNT(*) FROM group_members WHERE group_id = g.id)
		 FROM groups g
		 LEFT JOIN group_settings gs ON gs.group_id = g.id
		 WHERE g.id = $1`,
		groupID,
	).Scan(&g.ID, &g.ConversationID, &g.Name, &g.Description, &g.AvatarURL,
		&g.CreatedBy, &g.IsPublic, &g.MemberLimit, &g.CreatedAt, &g.UpdatedAt,
		&g.InviteCode, &g.MessageRetention, &g.DisappearingMsg, &g.MemberCount)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "GROUP_NOT_FOUND", Message: "group not found"})
		return
	}

	if g.InviteCode != nil && *g.InviteCode == "" {
		g.InviteCode = nil
	}

	// Get members
	rows, err := database.Pool.Query(ctx,
		`SELECT gm.user_id, u.display_name, COALESCE(u.avatar_url, ''), gm.role, gm.joined_at
		 FROM group_members gm JOIN users u ON u.id = gm.user_id
		 WHERE gm.group_id = $1 ORDER BY gm.joined_at ASC`,
		groupID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to fetch members"})
		return
	}
	defer rows.Close()

	members := []model.GroupMemberResponse{}
	for rows.Next() {
		var m model.GroupMemberResponse
		rows.Scan(&m.UserID, &m.DisplayName, &m.AvatarURL, &m.Role, &m.JoinedAt)
		members = append(members, m)
	}

	// Get pinned messages
	pinRows, err := database.Pool.Query(ctx,
		`SELECT message_id, pinned_by, pinned_at FROM pinned_messages
		 WHERE group_id = $1 AND unpinned_at IS NULL
		 ORDER BY pinned_at DESC LIMIT 5`,
		groupID,
	)
	if err == nil {
		defer pinRows.Close()
		pinned := []model.PinnedMessageResponse{}
		for pinRows.Next() {
			var p model.PinnedMessageResponse
			pinRows.Scan(&p.MessageID, &p.PinnedBy, &p.PinnedAt)
			pinned = append(pinned, p)
		}
		writeJSON(w, http.StatusOK, model.GroupResponse{
			ID:               g.ID,
			Name:             g.Name,
			Description:      g.Description,
			AvatarURL:        g.AvatarURL,
			CreatedBy:        g.CreatedBy,
			IsPublic:         g.IsPublic,
			MemberLimit:      g.MemberLimit,
			MessageRetention: g.MessageRetention,
			DisappearingMsg:  g.DisappearingMsg,
			InviteCode:       g.InviteCode,
			MemberCount:      g.MemberCount,
			CreatedAt:        g.CreatedAt,
			UpdatedAt:        g.UpdatedAt,
			Members:          members,
			PinnedMessages:   pinned,
		})
		return
	}

	writeJSON(w, http.StatusOK, model.GroupResponse{
		ID:               g.ID,
		Name:             g.Name,
		Description:      g.Description,
		AvatarURL:        g.AvatarURL,
		CreatedBy:        g.CreatedBy,
		IsPublic:         g.IsPublic,
		MemberLimit:      g.MemberLimit,
		MessageRetention: g.MessageRetention,
		DisappearingMsg:  g.DisappearingMsg,
		InviteCode:       g.InviteCode,
		MemberCount:      g.MemberCount,
		CreatedAt:        g.CreatedAt,
		UpdatedAt:        g.UpdatedAt,
		Members:          members,
	})
}

func handleListGroups(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT g.id, g.name, g.description, g.avatar_url, g.is_public, g.member_limit,
		        g.created_at, g.updated_at,
		        (SELECT COUNT(*) FROM group_members WHERE group_id = g.id),
		        gm.role
		 FROM groups g
		 JOIN group_members gm ON gm.group_id = g.id
		 WHERE gm.user_id = $1 AND gm.left_at IS NULL
		 ORDER BY g.updated_at DESC`,
		model.ParseUUID(userID),
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to list groups"})
		return
	}
	defer rows.Close()

	type groupListItem struct {
		ID          uuid.UUID `json:"id"`
		Name        string    `json:"name"`
		Description string    `json:"description"`
		AvatarURL   string    `json:"avatar_url,omitempty"`
		IsPublic    bool      `json:"is_public"`
		MemberLimit int       `json:"member_limit"`
		MemberCount int       `json:"member_count"`
		Role        string    `json:"role"`
		CreatedAt   time.Time `json:"created_at"`
		UpdatedAt   time.Time `json:"updated_at"`
	}

	groups := []groupListItem{}
	for rows.Next() {
		var g groupListItem
		rows.Scan(&g.ID, &g.Name, &g.Description, &g.AvatarURL, &g.IsPublic, &g.MemberLimit,
			&g.CreatedAt, &g.UpdatedAt, &g.MemberCount, &g.Role)
		groups = append(groups, g)
	}

	writeJSON(w, http.StatusOK, map[string]any{"groups": groups})
}

func handleGenerateInvite(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)

	ctx := context.Background()

	// Verify admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can generate invites"})
		return
	}

	code, err := generateInviteCode()
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to generate invite"})
		return
	}

	expiresAt := time.Now().Add(7 * 24 * time.Hour)

	_, err = database.Pool.Exec(ctx,
		`UPDATE groups SET invite_code = $1 WHERE id = $2`,
		code, groupID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to save invite"})
		return
	}

	writeJSON(w, http.StatusCreated, model.InviteResponse{
		Code:      code,
		ExpiresAt: expiresAt,
		URL:       "https://closetalk.app/join/" + code,
	})
}

func handleJoinGroup(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	parsedUserID := model.ParseUUID(userID)

	var req model.JoinGroupRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	// Find group by invite code
	var groupID, convID uuid.UUID
	var memberCount, memberLimit int
	err := database.Pool.QueryRow(ctx,
		`SELECT g.id, g.conversation_id,
		        (SELECT COUNT(*) FROM group_members WHERE group_id = g.id),
		        g.member_limit
		 FROM groups g WHERE g.invite_code = $1`,
		req.Code,
	).Scan(&groupID, &convID, &memberCount, &memberLimit)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "INVALID_INVITE", Message: "invalid invite code"})
		return
	}

	if memberCount >= memberLimit {
		writeError(w, http.StatusConflict, &model.AppError{Code: "GROUP_FULL", Message: "group has reached member limit"})
		return
	}

	// Check if already a member
	var existing bool
	database.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id = $1 AND user_id = $2 AND left_at IS NULL)`,
		groupID, parsedUserID,
	).Scan(&existing)
	if existing {
		writeError(w, http.StatusConflict, &model.AppError{Code: "ALREADY_MEMBER", Message: "you are already a member"})
		return
	}

	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to join group"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx,
		`INSERT INTO group_members (group_id, user_id, role) VALUES ($1, $2, 'member')`,
		groupID, parsedUserID,
	)
	if err != nil {
		log.Printf("[groups] join member insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to join group"})
		return
	}

	_, err = tx.Exec(ctx,
		`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2)
		 ON CONFLICT DO NOTHING`,
		convID, parsedUserID,
	)
	if err != nil {
		log.Printf("[groups] join participant insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to join group"})
		return
	}

	if err := tx.Commit(ctx); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to join group"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"group_id": groupID,
		"status":   "joined",
	})
}

func handleAddMembers(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)

	var req model.AddMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	// Verify admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can add members"})
		return
	}

	// Get conversation ID
	var convID uuid.UUID
	database.Pool.QueryRow(ctx,
		`SELECT conversation_id FROM groups WHERE id = $1`, groupID,
	).Scan(&convID)

	// Check member limit
	var memberCount, memberLimit int
	database.Pool.QueryRow(ctx,
		`SELECT COUNT(*), g.member_limit FROM group_members gm
		 JOIN groups g ON g.id = gm.group_id
		 WHERE gm.group_id = $1 AND gm.left_at IS NULL
		 GROUP BY g.member_limit`,
		groupID,
	).Scan(&memberCount, &memberLimit)

	added := []string{}
	skipped := []string{}
	for _, memberIDStr := range req.UserIDs {
		memberID := model.ParseUUID(memberIDStr)

		if memberCount >= memberLimit {
			skipped = append(skipped, memberIDStr)
			continue
		}

		_, err := database.Pool.Exec(ctx,
			`INSERT INTO group_members (group_id, user_id, role, invited_by) VALUES ($1, $2, 'member', $3)
			 ON CONFLICT DO NOTHING`,
			groupID, memberID, model.ParseUUID(userID),
		)
		if err != nil {
			skipped = append(skipped, memberIDStr)
			continue
		}

		database.Pool.Exec(ctx,
			`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2)
			 ON CONFLICT DO NOTHING`,
			convID, memberID,
		)
		memberCount++
		added = append(added, memberIDStr)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"added":   added,
		"skipped": skipped,
	})
}

func handleRemoveMember(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	targetIDStr := chi.URLParam(r, "userId")
	groupID := model.ParseUUID(groupIDStr)
	targetID := model.ParseUUID(targetIDStr)

	ctx := context.Background()

	// Verify admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can remove members"})
		return
	}

	// Cannot remove other admins
	var targetRole string
	database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, targetID,
	).Scan(&targetRole)
	if targetRole == "admin" && role == "admin" && model.ParseUUID(userID) != targetID {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_CANT_REMOVE_ADMIN", Message: "admins cannot remove other admins"})
		return
	}

	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to remove member"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx,
		`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, targetID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to remove member"})
		return
	}

	// Remove from conversation participants
	var convID uuid.UUID
	tx.QueryRow(ctx, `SELECT conversation_id FROM groups WHERE id = $1`, groupID).Scan(&convID)
	tx.Exec(ctx,
		`DELETE FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2`,
		convID, targetID,
	)

	if err := tx.Commit(ctx); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to remove member"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

func handleUpdateRole(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	targetIDStr := chi.URLParam(r, "userId")
	groupID := model.ParseUUID(groupIDStr)
	targetID := model.ParseUUID(targetIDStr)

	var req model.UpdateRoleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Role != "admin" && req.Role != "member" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "role must be 'admin' or 'member'"})
		return
	}

	ctx := context.Background()

	// Verify requester is admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can change roles"})
		return
	}

	_, err = database.Pool.Exec(ctx,
		`UPDATE group_members SET role = $1 WHERE group_id = $2 AND user_id = $3`,
		req.Role, groupID, targetID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to update role"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func handleLeaveGroup(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)
	parsedUserID := model.ParseUUID(userID)

	ctx := context.Background()

	var role string
	database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, parsedUserID,
	).Scan(&role)

	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to leave group"})
		return
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx,
		`DELETE FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, parsedUserID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to leave group"})
		return
	}

	var convID uuid.UUID
	tx.QueryRow(ctx, `SELECT conversation_id FROM groups WHERE id = $1`, groupID).Scan(&convID)
	tx.Exec(ctx,
		`DELETE FROM conversation_participants WHERE conversation_id = $1 AND user_id = $2`,
		convID, parsedUserID,
	)

	// If last admin left, promote the oldest member
	if role == "admin" {
		var newAdminID uuid.UUID
		err := tx.QueryRow(ctx,
			`SELECT user_id FROM group_members WHERE group_id = $1 ORDER BY joined_at ASC LIMIT 1`,
			groupID,
		).Scan(&newAdminID)
		if err == nil {
			tx.Exec(ctx,
				`UPDATE group_members SET role = 'admin' WHERE group_id = $1 AND user_id = $2`,
				groupID, newAdminID,
			)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to leave group"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "left"})
}

func handleUpdateGroupSettings(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)

	var req model.UpdateGroupSettingsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	// Verify admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can update settings"})
		return
	}

	// Build dynamic update
	sets := []string{}
	args := []any{}
	argIdx := 1

	if req.Name != nil {
		sets = append(sets, "name = $"+strconv.Itoa(argIdx))
		args = append(args, *req.Name)
		argIdx++
	}
	if req.Description != nil {
		sets = append(sets, "description = $"+strconv.Itoa(argIdx))
		args = append(args, *req.Description)
		argIdx++
	}
	if req.AvatarURL != nil {
		sets = append(sets, "avatar_url = $"+strconv.Itoa(argIdx))
		args = append(args, *req.AvatarURL)
		argIdx++
	}
	if req.IsPublic != nil {
		sets = append(sets, "is_public = $"+strconv.Itoa(argIdx))
		args = append(args, *req.IsPublic)
		argIdx++
	}
	if req.MemberLimit != nil {
		sets = append(sets, "member_limit = $"+strconv.Itoa(argIdx))
		args = append(args, *req.MemberLimit)
		argIdx++
	}
	if req.MessageRetention != nil {
		sets = append(sets, "message_retention = $"+strconv.Itoa(argIdx))
		args = append(args, *req.MessageRetention)
		argIdx++
	}
	if req.DisappearingMsg != nil {
		sets = append(sets, "disappearing_msg = $"+strconv.Itoa(argIdx))
		args = append(args, *req.DisappearingMsg)
		argIdx++
	}
	sets = append(sets, "updated_at = now()")

	if len(sets) == 1 {
		writeJSON(w, http.StatusOK, map[string]string{"status": "no changes"})
		return
	}

	// Use group_settings table
	query := `INSERT INTO group_settings (group_id`
	valPlaceholders := `$1`
	valArgs := []any{groupID}
	valIdx := 2

	colMap := map[string]*string{
		"message_retention": req.MessageRetention,
		"disappearing_msg": req.DisappearingMsg,
	}

	for k, v := range colMap {
		if v != nil {
			query += ", " + k
			valPlaceholders += ", $" + strconv.Itoa(valIdx)
			valArgs = append(valArgs, *v)
			valIdx++
		}
	}

	query += `) VALUES (` + valPlaceholders + `)
		ON CONFLICT (group_id) DO UPDATE SET `
	updates := []string{}
	for k, v := range colMap {
		if v != nil {
			updates = append(updates, k+" = EXCLUDED."+k)
		}
	}
	query += ", " + strings.Join(updates, ", ")

	_, err = database.Pool.Exec(ctx, query, valArgs...)
	if err != nil {
		log.Printf("[groups] settings update error: %v", err)
	}

	// Update groups table for non-settings fields
	args = append(args, groupID)
	updateQuery := `UPDATE groups SET ` + strings.Join(sets, ", ") + ` WHERE id = $` + strconv.Itoa(argIdx)
	_, err = database.Pool.Exec(ctx, updateQuery, args...)
	if err != nil {
		log.Printf("[groups] update error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to update settings"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func handlePinMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	groupID := model.ParseUUID(groupIDStr)

	var req model.PinMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	// Verify admin
	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can pin messages"})
		return
	}

	_, err = database.Pool.Exec(ctx,
		`INSERT INTO pinned_messages (group_id, message_id, pinned_by) VALUES ($1, $2, $3)`,
		groupID, req.MessageID, model.ParseUUID(userID),
	)
	if err != nil {
		log.Printf("[groups] pin error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to pin message"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "pinned"})
}

func handleUnpinMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	groupIDStr := chi.URLParam(r, "id")
	messageIDStr := chi.URLParam(r, "messageId")
	groupID := model.ParseUUID(groupIDStr)

	ctx := context.Background()

	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM group_members WHERE group_id = $1 AND user_id = $2`,
		groupID, model.ParseUUID(userID),
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ADMIN_ONLY", Message: "only admins can unpin messages"})
		return
	}

	_, err = database.Pool.Exec(ctx,
		`UPDATE pinned_messages SET unpinned_at = now() WHERE group_id = $1 AND message_id = $2 AND unpinned_at IS NULL`,
		groupID, messageIDStr,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to unpin message"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unpinned"})
}


