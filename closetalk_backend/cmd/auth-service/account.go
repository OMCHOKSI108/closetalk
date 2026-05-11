package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

func handleDeleteAccount(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	_, err := database.Pool.Exec(ctx,
		`UPDATE users SET deleted_at = $1, is_active = false, email = 'deleted_' || id || '@deleted', username = 'deleted_' || id, updated_at = $1 WHERE id = $2 AND deleted_at IS NULL`,
		time.Now(), userID,
	)
	if err != nil {
		log.Printf("[account] delete error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to delete account"})
		return
	}

	database.Valkey.Del(ctx, "user_sessions:"+userID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
