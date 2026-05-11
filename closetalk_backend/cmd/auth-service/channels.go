package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

type createChannelRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	IsPublic    bool   `json:"is_public"`
}

func handleCreateChannel(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req createChannelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "name is required"})
		return
	}

	ctx := context.Background()
	var channelID string
	err := database.Pool.QueryRow(ctx,
		`INSERT INTO channels (name, description, is_public, created_by) VALUES ($1, $2, $3, $4) RETURNING id`,
		req.Name, req.Description, req.IsPublic, userID,
	).Scan(&channelID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create channel"})
		return
	}

	database.Pool.Exec(ctx,
		`INSERT INTO channel_subscribers (channel_id, user_id, role) VALUES ($1, $2, 'admin')`,
		channelID, userID,
	)

	writeJSON(w, http.StatusCreated, map[string]string{"id": channelID})
}

func handleListChannels(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT c.id, c.name, c.description, c.avatar_url, c.is_public, c.subscriber_count, c.created_by, c.created_at,
		        cs.role as my_role
		 FROM channels c
		 JOIN channel_subscribers cs ON cs.channel_id = c.id AND cs.user_id = $1
		 ORDER BY c.created_at DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list channels"})
		return
	}
	defer rows.Close()

	type channelResponse struct {
		ID              string `json:"id"`
		Name            string `json:"name"`
		Description     string `json:"description"`
		AvatarURL       string `json:"avatar_url"`
		IsPublic        bool   `json:"is_public"`
		SubscriberCount int64  `json:"subscriber_count"`
		CreatedBy       string `json:"created_by"`
		CreatedAt       string `json:"created_at"`
		MyRole          string `json:"my_role"`
	}
	channels := []channelResponse{}
	for rows.Next() {
		var c channelResponse
		rows.Scan(&c.ID, &c.Name, &c.Description, &c.AvatarURL, &c.IsPublic, &c.SubscriberCount, &c.CreatedBy, &c.CreatedAt, &c.MyRole)
		channels = append(channels, c)
	}
	if channels == nil {
		channels = []channelResponse{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"channels": channels})
}

func handleDiscoverChannels(w http.ResponseWriter, r *http.Request) {
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT c.id, c.name, c.description, c.avatar_url, c.subscriber_count, c.created_by, c.created_at
		 FROM channels c
		 WHERE c.is_public = true
		 ORDER BY c.subscriber_count DESC, c.created_at DESC
		 LIMIT 50`,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to discover channels"})
		return
	}
	defer rows.Close()

	type channelInfo struct {
		ID              string `json:"id"`
		Name            string `json:"name"`
		Description     string `json:"description"`
		AvatarURL       string `json:"avatar_url"`
		SubscriberCount int64  `json:"subscriber_count"`
		CreatedBy       string `json:"created_by"`
		CreatedAt       string `json:"created_at"`
	}
	channels := []channelInfo{}
	for rows.Next() {
		var c channelInfo
		rows.Scan(&c.ID, &c.Name, &c.Description, &c.AvatarURL, &c.SubscriberCount, &c.CreatedBy, &c.CreatedAt)
		channels = append(channels, c)
	}
	if channels == nil {
		channels = []channelInfo{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"channels": channels})
}

func handleSubscribeChannel(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	channelID := chi.URLParam(r, "id")

	ctx := context.Background()
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO channel_subscribers (channel_id, user_id, role) VALUES ($1, $2, 'subscriber') ON CONFLICT DO NOTHING`,
		channelID, userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to subscribe"})
		return
	}

	database.Pool.Exec(ctx,
		`UPDATE channels SET subscriber_count = (SELECT COUNT(*) FROM channel_subscribers WHERE channel_id = $1) WHERE id = $1`,
		channelID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"status": "subscribed"})
}

func handleUnsubscribeChannel(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	channelID := chi.URLParam(r, "id")

	ctx := context.Background()
	database.Pool.Exec(ctx,
		`DELETE FROM channel_subscribers WHERE channel_id = $1 AND user_id = $2 AND role = 'subscriber'`,
		channelID, userID,
	)

	database.Pool.Exec(ctx,
		`UPDATE channels SET subscriber_count = (SELECT COUNT(*) FROM channel_subscribers WHERE channel_id = $1) WHERE id = $1`,
		channelID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"status": "unsubscribed"})
}

func handleListChannelSubscribers(w http.ResponseWriter, r *http.Request) {
	channelID := chi.URLParam(r, "id")

	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT cs.user_id, cs.role, cs.subscribed_at, u.display_name, u.username, u.avatar_url
		 FROM channel_subscribers cs
		 JOIN users u ON u.id = cs.user_id
		 WHERE cs.channel_id = $1
		 ORDER BY cs.subscribed_at DESC`,
		channelID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list subscribers"})
		return
	}
	defer rows.Close()

	type subscriberEntry struct {
		UserID       string `json:"user_id"`
		Role         string `json:"role"`
		DisplayName  string `json:"display_name"`
		Username     string `json:"username"`
		AvatarURL    string `json:"avatar_url"`
		SubscribedAt string `json:"subscribed_at"`
	}
	subs := []subscriberEntry{}
	for rows.Next() {
		var s subscriberEntry
		rows.Scan(&s.UserID, &s.Role, &s.SubscribedAt, &s.DisplayName, &s.Username, &s.AvatarURL)
		subs = append(subs, s)
	}
	if subs == nil {
		subs = []subscriberEntry{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"subscribers": subs})
}

func handleSendChannelMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	channelID := chi.URLParam(r, "id")

	var req struct {
		Content     string `json:"content"`
		ContentType string `json:"content_type"`
		MediaURL    string `json:"media_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.Content == "" && req.MediaURL == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "content or media_url required"})
		return
	}
	if req.ContentType == "" {
		req.ContentType = "text"
	}

	ctx := context.Background()

	var role string
	err := database.Pool.QueryRow(ctx,
		`SELECT role FROM channel_subscribers WHERE channel_id = $1 AND user_id = $2`,
		channelID, userID,
	).Scan(&role)
	if err != nil || role != "admin" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "FORBIDDEN", Message: "only admins can send channel messages"})
		return
	}

	messageServiceURL := os.Getenv("MESSAGE_SERVICE_URL")
	if messageServiceURL == "" {
		messageServiceURL = "http://localhost:8082"
	}

	body, _ := json.Marshal(map[string]any{
		"chat_id":      channelID,
		"content":      req.Content,
		"content_type": req.ContentType,
		"media_url":    req.MediaURL,
	})
	httpReq, _ := http.NewRequest("POST", messageServiceURL+"/messages", bytes.NewReader(body))
	httpReq.Header.Set("Authorization", r.Header.Get("Authorization"))
	httpReq.Header.Set("Content-Type", "application/json")

	var msgID string
	if resp, err := http.DefaultClient.Do(httpReq); err == nil {
		defer resp.Body.Close()
		var result map[string]any
		if json.NewDecoder(resp.Body).Decode(&result) == nil {
			if id, ok := result["id"].(string); ok {
				msgID = id
			}
		}
	}
	if msgID == "" {
		msgID = "sent"
	}

	writeJSON(w, http.StatusCreated, map[string]string{"id": msgID})
}
