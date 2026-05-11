package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

type createWebhookRequest struct {
	URL    string   `json:"url"`
	Events []string `json:"events"`
}

func handleCreateWebhook(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req createWebhookRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.URL == "" || len(req.Events) == 0 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "url and events are required"})
		return
	}

	secret := generateWebhookSecret()

	ctx := context.Background()
	var id string
	err := database.Pool.QueryRow(ctx,
		`INSERT INTO webhooks (user_id, url, events, secret) VALUES ($1, $2, $3, $4) RETURNING id`,
		userID, req.URL, req.Events, secret,
	).Scan(&id)
	if err != nil {
		log.Printf("[webhooks] create error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create webhook"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"id": id, "secret": secret})
}

func handleListWebhooks(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT id, url, events, is_active, created_at FROM webhooks WHERE user_id = $1 ORDER BY created_at DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list webhooks"})
		return
	}
	defer rows.Close()

	type webhookEntry struct {
		ID       string   `json:"id"`
		URL      string   `json:"url"`
		Events   []string `json:"events"`
		IsActive bool     `json:"is_active"`
		CreateAt string   `json:"created_at"`
	}
	hooks := []webhookEntry{}
	for rows.Next() {
		var h webhookEntry
		rows.Scan(&h.ID, &h.URL, &h.Events, &h.IsActive, &h.CreateAt)
		hooks = append(hooks, h)
	}
	if hooks == nil {
		hooks = []webhookEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"webhooks": hooks})
}

func handleDeleteWebhook(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	webhookID := chi.URLParam(r, "id")

	ctx := context.Background()
	tag, err := database.Pool.Exec(ctx,
		`DELETE FROM webhooks WHERE id = $1 AND user_id = $2`, webhookID, userID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "webhook not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func generateWebhookSecret() string {
	b := make([]byte, 32)
	rand.Read(b)
	return hex.EncodeToString(b)
}
