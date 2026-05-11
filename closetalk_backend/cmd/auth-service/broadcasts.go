package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/go-chi/chi/v5"
)

type createBroadcastRequest struct {
	Name      string   `json:"name"`
	MemberIDs []string `json:"member_ids"`
}

func handleCreateBroadcast(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req createBroadcastRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "name is required"})
		return
	}

	ctx := context.Background()
	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create broadcast"})
		return
	}
	defer tx.Rollback(ctx)

	var broadcastID string
	err = tx.QueryRow(ctx,
		`INSERT INTO broadcasts (user_id, name) VALUES ($1, $2) RETURNING id`,
		userID, req.Name,
	).Scan(&broadcastID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create broadcast"})
		return
	}

	for _, memberID := range req.MemberIDs {
		if memberID == userID {
			continue
		}
		_, err = tx.Exec(ctx,
			`INSERT INTO broadcast_members (broadcast_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			broadcastID, memberID,
		)
		if err != nil {
			log.Printf("[broadcast] add member error: %v", err)
		}
	}

	tx.Commit(ctx)
	writeJSON(w, http.StatusCreated, map[string]string{"id": broadcastID})
}

func handleListBroadcasts(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT b.id, b.name, b.created_at,
		        COALESCE(json_agg(json_build_object('user_id', bm.user_id, 'added_at', bm.added_at)) FILTER (WHERE bm.user_id IS NOT NULL), '[]') as members
		 FROM broadcasts b
		 LEFT JOIN broadcast_members bm ON bm.broadcast_id = b.id
		 WHERE b.user_id = $1
		 GROUP BY b.id, b.name, b.created_at
		 ORDER BY b.created_at DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list broadcasts"})
		return
	}
	defer rows.Close()

	type broadcastResponse struct {
		ID        string `json:"id"`
		Name      string `json:"name"`
		Members   string `json:"members"`
		CreatedAt string `json:"created_at"`
	}
	broadcasts := []broadcastResponse{}
	for rows.Next() {
		var b broadcastResponse
		rows.Scan(&b.ID, &b.Name, &b.Members, &b.CreatedAt)
		broadcasts = append(broadcasts, b)
	}
	if broadcasts == nil {
		broadcasts = []broadcastResponse{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"broadcasts": broadcasts})
}

type sendBroadcastRequest struct {
	Content     string `json:"content"`
	ContentType string `json:"content_type"`
}

func handleSendBroadcast(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	broadcastID := chi.URLParam(r, "id")

	var req sendBroadcastRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.Content == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "content is required"})
		return
	}
	if req.ContentType == "" {
		req.ContentType = "text"
	}

	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT bm.user_id FROM broadcast_members bm
		 JOIN broadcasts b ON b.id = bm.broadcast_id
		 WHERE b.id = $1 AND b.user_id = $2`,
		broadcastID, userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to send broadcast"})
		return
	}
	defer rows.Close()

	memberIDs := []string{}
	for rows.Next() {
		var mid string
		rows.Scan(&mid)
		memberIDs = append(memberIDs, mid)
	}

	messageServiceURL := os.Getenv("MESSAGE_SERVICE_URL")
	if messageServiceURL == "" {
		messageServiceURL = "http://localhost:8082"
	}

	authHeader := r.Header.Get("Authorization")
	sentCount := 0

	for _, memberID := range memberIDs {
		var chatID string
		err = database.Pool.QueryRow(ctx,
			`SELECT id FROM conversations WHERE type = 'direct' AND id IN (
			   SELECT conversation_id FROM conversation_participants WHERE user_id = $1
			   INTERSECT
			   SELECT conversation_id FROM conversation_participants WHERE user_id = $2
			 ) LIMIT 1`,
			userID, memberID,
		).Scan(&chatID)
		if err != nil {
			err = database.Pool.QueryRow(ctx,
				`INSERT INTO conversations (type) VALUES ('direct') RETURNING id`,
			).Scan(&chatID)
			if err == nil {
				database.Pool.Exec(ctx,
					`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
					chatID, userID, memberID,
				)
			}
		}
		if chatID != "" {
			body, _ := json.Marshal(map[string]any{
				"chat_id":      chatID,
				"content":      req.Content,
				"content_type": req.ContentType,
			})
			httpReq, _ := http.NewRequest("POST", messageServiceURL+"/messages", bytes.NewReader(body))
			httpReq.Header.Set("Authorization", authHeader)
			httpReq.Header.Set("Content-Type", "application/json")
			if resp, err := http.DefaultClient.Do(httpReq); err == nil {
				resp.Body.Close()
				sentCount++
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "sent", "recipient_count": strconv.Itoa(sentCount)})
}
