package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

type scheduleMessageRequest struct {
	ChatID      string `json:"chat_id"`
	Content     string `json:"content"`
	ContentType string `json:"content_type"`
	MediaURL    string `json:"media_url,omitempty"`
	SendAt      string `json:"send_at"`
	ReplyToID   string `json:"reply_to_id,omitempty"`
}

func handleScheduleMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req scheduleMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ChatID == "" || req.Content == "" || req.SendAt == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "chat_id, content, and send_at are required"})
		return
	}

	sendAt, err := time.Parse(time.RFC3339, req.SendAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "invalid send_at format, use RFC3339"})
		return
	}
	if sendAt.Before(time.Now()) {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "send_at must be in the future"})
		return
	}
	if sendAt.After(time.Now().Add(30 * 24 * time.Hour)) {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "send_at must be within 30 days"})
		return
	}

	if req.ContentType == "" {
		req.ContentType = "text"
	}

	ctx := context.Background()
	var id string
	err = database.Pool.QueryRow(ctx,
		`INSERT INTO scheduled_messages (chat_id, sender_id, content, content_type, media_url, reply_to_id, send_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
		req.ChatID, userID, req.Content, req.ContentType, req.MediaURL, req.ReplyToID, sendAt,
	).Scan(&id)
	if err != nil {
		log.Printf("[scheduled] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to schedule message"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"id": id, "send_at": req.SendAt})
}

func handleListScheduledMessages(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT id, chat_id, content, content_type, send_at, status, created_at
		 FROM scheduled_messages
		 WHERE sender_id = $1 AND status = 'pending'
		 ORDER BY send_at ASC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list scheduled messages"})
		return
	}
	defer rows.Close()

	type entry struct {
		ID          string `json:"id"`
		ChatID      string `json:"chat_id"`
		Content     string `json:"content"`
		ContentType string `json:"content_type"`
		SendAt      string `json:"send_at"`
		Status      string `json:"status"`
		CreatedAt   string `json:"created_at"`
	}
	msgs := []entry{}
	for rows.Next() {
		var m entry
		rows.Scan(&m.ID, &m.ChatID, &m.Content, &m.ContentType, &m.SendAt, &m.Status, &m.CreatedAt)
		msgs = append(msgs, m)
	}
	if msgs == nil {
		msgs = []entry{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"scheduled": msgs})
}

func handleCancelScheduledMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	msgID := chi.URLParam(r, "id")

	ctx := context.Background()
	tag, err := database.Pool.Exec(ctx,
		`UPDATE scheduled_messages SET status = 'cancelled' WHERE id = $1 AND sender_id = $2 AND status = 'pending'`,
		msgID, userID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "scheduled message not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "cancelled"})
}
