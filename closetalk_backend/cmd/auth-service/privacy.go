package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

type privacySettings struct {
	LastSeenVisibility     string `json:"last_seen_visibility"`
	ProfilePhotoVisibility string `json:"profile_photo_visibility"`
	ReadReceiptsGlobal     bool   `json:"read_receipts_global"`
	ReadReceiptsOverrides  string `json:"read_receipts_overrides"`
	GroupAddPermission     string `json:"group_add_permission"`
	StatusPrivacy          string `json:"status_privacy"`
	CloseFriends           string `json:"close_friends"`
}

type updatePrivacyRequest struct {
	LastSeenVisibility     *string `json:"last_seen_visibility,omitempty"`
	ProfilePhotoVisibility *string `json:"profile_photo_visibility,omitempty"`
	ReadReceiptsGlobal     *bool   `json:"read_receipts_global,omitempty"`
	GroupAddPermission     *string `json:"group_add_permission,omitempty"`
	StatusPrivacy          *string `json:"status_privacy,omitempty"`
}

func handleGetPrivacySettings(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	var s privacySettings
	err := database.Pool.QueryRow(ctx,
		`SELECT last_seen_visibility, profile_photo_visibility, read_receipts_global,
		        COALESCE(read_receipts_overrides::text, '{}'),
		        group_add_permission, status_privacy, COALESCE(close_friends::text, '[]')
		 FROM user_settings WHERE user_id = $1`,
		userID,
	).Scan(&s.LastSeenVisibility, &s.ProfilePhotoVisibility, &s.ReadReceiptsGlobal,
		&s.ReadReceiptsOverrides, &s.GroupAddPermission, &s.StatusPrivacy, &s.CloseFriends)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "settings not found"})
		return
	}

	writeJSON(w, http.StatusOK, s)
}

func handleUpdatePrivacySettings(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req updatePrivacyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()
	updates := []string{}
	args := []any{}
	idx := 1

	if req.LastSeenVisibility != nil {
		updates = append(updates, fmt.Sprintf("last_seen_visibility = $%d", idx))
		args = append(args, *req.LastSeenVisibility)
		idx++
	}
	if req.ProfilePhotoVisibility != nil {
		updates = append(updates, fmt.Sprintf("profile_photo_visibility = $%d", idx))
		args = append(args, *req.ProfilePhotoVisibility)
		idx++
	}
	if req.ReadReceiptsGlobal != nil {
		updates = append(updates, fmt.Sprintf("read_receipts_global = $%d", idx))
		args = append(args, *req.ReadReceiptsGlobal)
		idx++
	}
	if req.GroupAddPermission != nil {
		updates = append(updates, fmt.Sprintf("group_add_permission = $%d", idx))
		args = append(args, *req.GroupAddPermission)
		idx++
	}
	if req.StatusPrivacy != nil {
		updates = append(updates, fmt.Sprintf("status_privacy = $%d", idx))
		args = append(args, *req.StatusPrivacy)
		idx++
	}

	if len(updates) == 0 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "no fields to update"})
		return
	}

	updates = append(updates, fmt.Sprintf("updated_at = $%d", idx))
	args = append(args, time.Now())
	idx++

	args = append(args, userID)
	query := "UPDATE user_settings SET " + joinStrings(updates, ", ") + fmt.Sprintf(" WHERE user_id = $%d", idx)
	_, err := database.Pool.Exec(ctx, query, args...)
	if err != nil {
		log.Printf("[privacy] update error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to update settings"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func joinStrings(strs []string, sep string) string {
	if len(strs) == 0 {
		return ""
	}
	result := strs[0]
	for i := 1; i < len(strs); i++ {
		result += sep + strs[i]
	}
	return result
}
