package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

func handleViewStory(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	storyID := chi.URLParam(r, "id")

	ctx := context.Background()
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO story_views (story_id, viewer_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		storyID, userID,
	)
	if err != nil {
		log.Printf("[story] view error: %v", err)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleGetStoryViews(w http.ResponseWriter, r *http.Request) {
	storyID := chi.URLParam(r, "id")

	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT sv.viewer_id, u.display_name, u.username, u.avatar_url, sv.viewed_at
		 FROM story_views sv
		 JOIN users u ON u.id = sv.viewer_id
		 WHERE sv.story_id = $1
		 ORDER BY sv.viewed_at DESC`,
		storyID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to get views"})
		return
	}
	defer rows.Close()

	type viewEntry struct {
		ViewerID    string `json:"viewer_id"`
		DisplayName string `json:"display_name"`
		Username    string `json:"username"`
		AvatarURL   string `json:"avatar_url,omitempty"`
		ViewedAt    string `json:"viewed_at"`
	}
	views := []viewEntry{}
	for rows.Next() {
		var v viewEntry
		if err := rows.Scan(&v.ViewerID, &v.DisplayName, &v.Username, &v.AvatarURL, &v.ViewedAt); err != nil {
			continue
		}
		views = append(views, v)
	}
	if views == nil {
		views = []viewEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"views": views})
}

func handleReplyToStory(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	storyID := chi.URLParam(r, "id")

	var req struct {
		Content string `json:"content"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.Content == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "content is required"})
		return
	}

	ctx := context.Background()

	var storyOwnerID string
	err := database.Pool.QueryRow(ctx,
		`SELECT user_id FROM stories WHERE id = $1`, storyID,
	).Scan(&storyOwnerID)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "story not found"})
		return
	}

	var chatID string
	err = database.Pool.QueryRow(ctx,
		`SELECT id FROM conversations WHERE type = 'direct' AND id IN (
		   SELECT conversation_id FROM conversation_participants WHERE user_id = $1
		   INTERSECT
		   SELECT conversation_id FROM conversation_participants WHERE user_id = $2
		 ) LIMIT 1`,
		userID, storyOwnerID,
	).Scan(&chatID)
	if err != nil {
		err = database.Pool.QueryRow(ctx,
			`INSERT INTO conversations (type) VALUES ('direct') RETURNING id`,
		).Scan(&chatID)
		if err == nil {
			database.Pool.Exec(ctx,
				`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
				chatID, userID, storyOwnerID,
			)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"chat_id": chatID, "content": req.Content})
}

func handleMuteStoryUser(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	mutedUserID := chi.URLParam(r, "userId")

	ctx := context.Background()
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO story_mutes (user_id, muted_user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		userID, mutedUserID,
	)
	if err != nil {
		log.Printf("[story] mute error: %v", err)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "muted"})
}

func handleUnmuteStoryUser(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	mutedUserID := chi.URLParam(r, "userId")

	ctx := context.Background()
	database.Pool.Exec(ctx,
		`DELETE FROM story_mutes WHERE user_id = $1 AND muted_user_id = $2`,
		userID, mutedUserID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"status": "unmuted"})
}
