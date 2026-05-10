package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/joho/godotenv"

	"github.com/OMCHOKSI108/closetalk/internal/auth"
	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

var hub = newHub()

func main() {
	_ = godotenv.Load()
	auth.InitJWT()

	// Try DynamoDB, fall back to in-memory
	if err := database.ConnectDynamoDB(); err != nil {
		log.Printf("[warn] dynamodb not available, using in-memory store: %v", err)
	} else {
		database.InitDynamoDBSchema()
		database.GlobalStore = database.NewDynamoDBStore()
		defer database.CloseDynamoDB()
	}

	// Connect Valkey for presence
	if err := database.ConnectValkey(); err != nil {
		log.Printf("[warn] valkey not available: %v", err)
	} else {
		defer database.CloseValkey()
	}

	// Connect Neon for sync queries (conversation membership)
	if err := database.ConnectNeon(); err != nil {
		log.Printf("[warn] neon not available, sync will be limited: %v", err)
	} else {
		defer database.CloseNeon()
	}

	r := chi.NewRouter()

	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(middleware.Logging)
	r.Use(chimw.Recoverer)
	r.Use(chimw.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "Idempotency-Key"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "message-service"})
	})

	// WebSocket endpoint for real-time messaging
	r.Get("/ws", handleWebSocket)

	// Message REST API (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)

		r.Post("/messages", handleSendMessage)
		r.Get("/messages/{chatId}", handleGetMessages)
		r.Put("/messages/{messageId}", handleEditMessage)
		r.Delete("/messages/{messageId}", handleDeleteMessage)
		r.Post("/messages/{messageId}/react", handleReactToMessage)
		r.Post("/messages/{messageId}/read", handleMarkRead)

		r.Post("/bookmarks", handleAddBookmark)
		r.Delete("/bookmarks/{messageId}", handleRemoveBookmark)
		r.Get("/bookmarks", handleListBookmarks)
	})

	// Sync & device routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)

		r.Get("/sync/messages", handleSyncMessages)
		r.Get("/sync/status", handleSyncStatus)
		r.Post("/devices/force-revoke", handleForceRevokeDevice)
	})

	port := os.Getenv("MESSAGE_SERVICE_PORT")
	if port == "" {
		port = "8082"
	}

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	go hub.run()

	go func() {
		log.Printf("[message-service] starting on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[fatal] %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("[message-service] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}

	claims, err := auth.ValidateToken(token)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}

	deviceID := claims.DeviceID
	if deviceID == "" {
		deviceID = "unknown-" + claims.UserID
	}

	chatID := r.URL.Query().Get("chat_id")
	if chatID == "" {
		http.Error(w, "missing chat_id", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[ws] upgrade error: %v", err)
		return
	}

	client := &wsClient{
		conn:     conn,
		userID:   claims.UserID,
		deviceID: deviceID,
		chatIDs:  map[string]bool{chatID: true},
		send:     make(chan []byte, 256),
	}

	hub.register(client)

	go client.writePump()
	go client.readPump()
}

func (c *wsClient) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *wsClient) readPump() {
	defer func() {
		hub.removeClient(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(4096)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			break
		}

		var wsMsg model.WebSocketMessage
		if json.Unmarshal(message, &wsMsg) != nil {
			continue
		}

		switch wsMsg.Type {
		case "typing.start", "typing.stop":
			data, _ := json.Marshal(wsMsg)
			for chatID := range c.chatIDs {
				hub.broadcastToChat(chatID, data, c.userID)
			}
		case "subscribe":
			if chatID, ok := wsMsg.Payload.(string); ok {
				hub.subscribeToChat(c, chatID)
			}
		case "unsubscribe":
			if chatID, ok := wsMsg.Payload.(string); ok {
				hub.unsubscribeFromChat(c, chatID)
			}
		case "pong":
			c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		}
	}
}

// ─── REST Handlers ───────────────────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, model.ErrorResponse{Error: message, Code: code})
}

func handleSendMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.SendMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	if req.ChatID == "" || req.Content == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "chat_id and content are required")
		return
	}

	now := time.Now()
	msg := &model.Message{
		ID:          uuid.New(),
		ChatID:      req.ChatID,
		SenderID:    userID,
		Content:     req.Content,
		ContentType: req.ContentType,
		Status:      "sent",
		CreatedAt:   now,
	}

	if req.ContentType == "" {
		msg.ContentType = "text"
	}
	if req.ReplyToID != "" {
		if id, err := uuid.Parse(req.ReplyToID); err == nil {
			msg.ReplyToID = &id
		}
	}
	if req.MediaID != "" {
		msg.MediaID = req.MediaID
	}
	if len(req.RecipientIDs) > 0 {
		msg.RecipientIDs = req.RecipientIDs
	}

	if err := database.GlobalStore.InsertMessage(context.Background(), msg); err != nil {
		log.Printf("[messages] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, "INTERNAL", "Failed to send message")
		return
	}

	// Broadcast via WebSocket to all devices in chat
	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.new",
		Payload: model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			Content: msg.Content, ContentType: msg.ContentType,
			Status: msg.Status, CreatedAt: msg.CreatedAt,
		},
	})
	hub.broadcastToChat(req.ChatID, wsPayload, userID)
	// Multi-device fan-out: push to all recipient devices
	for _, recipientID := range req.RecipientIDs {
		hub.broadcastToUserDevices(recipientID, wsPayload, "")
	}

	writeJSON(w, http.StatusCreated, model.MessageResponse{
		ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
		Content: msg.Content, ContentType: msg.ContentType,
		Status: msg.Status, CreatedAt: msg.CreatedAt,
	})
}

func handleGetMessages(w http.ResponseWriter, r *http.Request) {
	chatID := chi.URLParam(r, "chatId")
	if chatID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "chat_id is required")
		return
	}

	cursor := time.Now()
	if c := r.URL.Query().Get("cursor"); c != "" {
		if t, err := time.Parse(time.RFC3339, c); err == nil {
			cursor = t
		}
	}

	limit := 50
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 100 {
			limit = parsed
		}
	}

	messages, hasMore, err := database.GlobalStore.GetMessages(context.Background(), chatID, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL", "Failed to fetch messages")
		return
	}

	resp := model.PaginatedMessages{
		Messages: make([]model.MessageResponse, 0, len(messages)),
		HasMore:  hasMore,
	}

	for _, msg := range messages {
		reactions, _ := database.GlobalStore.GetReactions(context.Background(), msg.ID)
		resp.Messages = append(resp.Messages, model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			Content: msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			ReplyToID: msg.ReplyToID, Status: msg.Status,
			ModerationStatus: msg.ModerationStatus,
			EditHistory:      msg.EditHistory,
			IsDeleted:        msg.IsDeleted,
			Reactions:        reactions,
			CreatedAt:        msg.CreatedAt,
			EditedAt:         msg.EditedAt,
		})
	}

	if len(messages) > 0 {
		resp.NextCursor = messages[len(messages)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, resp)
}

func handleEditMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	var req model.EditMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	ctx := context.Background()
	msg, err := database.GlobalStore.GetMessage(ctx, messageID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Message not found")
		return
	}

	if msg.SenderID != userID {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Cannot edit another user's message")
		return
	}

	if database.Pool != nil {
		var isMember bool
		database.Pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM conversation_participants WHERE conversation_id = $1::uuid AND user_id = $2)`,
			msg.ChatID, userID,
		).Scan(&isMember)
		if !isMember {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "You are no longer a member of this conversation")
			return
		}
	}

	if time.Since(msg.CreatedAt) > 15*time.Minute {
		writeError(w, http.StatusForbidden, "EXPIRED", "Can only edit within 15 minutes")
		return
	}

	now := time.Now()
	msg.EditHistory = append(msg.EditHistory, model.EditEntry{
		Content: msg.Content, EditedAt: now,
	})
	msg.Content = req.Content
	msg.EditedAt = &now

	database.GlobalStore.UpdateMessage(ctx, msg)

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.updated",
		Payload: map[string]any{
			"message_id":   msg.ID.String(),
			"content":      msg.Content,
			"edit_history": msg.EditHistory,
			"edited_at":    now,
		},
	})
	hub.broadcastToChat(msg.ChatID, wsPayload, userID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

func handleDeleteMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	ctx := context.Background()
	msg, err := database.GlobalStore.GetMessage(ctx, messageID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Message not found")
		return
	}

	if msg.SenderID != userID {
		writeError(w, http.StatusForbidden, "FORBIDDEN", "Cannot delete another user's message")
		return
	}

	if database.Pool != nil {
		var isMember bool
		database.Pool.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM conversation_participants WHERE conversation_id = $1::uuid AND user_id = $2)`,
			msg.ChatID, userID,
		).Scan(&isMember)
		if !isMember {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "You are no longer a member of this conversation")
			return
		}
	}

	if time.Since(msg.CreatedAt) > 15*time.Minute {
		writeError(w, http.StatusForbidden, "EXPIRED", "Can only delete within 15 minutes")
		return
	}

	database.GlobalStore.DeleteMessage(ctx, messageID)

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.updated",
		Payload: map[string]string{
			"message_id": messageID.String(),
			"status":     "deleted",
		},
	})
	hub.broadcastToChat(msg.ChatID, wsPayload, userID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func handleReactToMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	var req model.ReactToMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	ctx := context.Background()

	// Toggle: if reaction exists, remove it; otherwise add it
	reactions, _ := database.GlobalStore.GetReactions(ctx, messageID)
	exists := false
	for _, r := range reactions {
		if r.UserID == userID && r.Emoji == req.Emoji {
			exists = true
			break
		}
	}

	if exists {
		database.GlobalStore.RemoveReaction(ctx, messageID, userID, req.Emoji)
	} else {
		database.GlobalStore.AddReaction(ctx, messageID, userID, req.Emoji)
	}

	// Get updated reactions
	reactions, _ = database.GlobalStore.GetReactions(ctx, messageID)

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.reaction",
		Payload: map[string]any{
			"message_id": messageID.String(),
			"reactions":  reactions,
		},
	})

	// Get message to find chat_id for broadcast
	msg, _ := database.GlobalStore.GetMessage(ctx, messageID)
	chatID := ""
	if msg != nil {
		chatID = msg.ChatID
	}
	if chatID != "" {
		hub.broadcastToChat(chatID, wsPayload, "")
	}

	writeJSON(w, http.StatusOK, map[string]any{"reactions": reactions})
}

func handleMarkRead(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	database.GlobalStore.MarkRead(context.Background(), messageID, userID)

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.status",
		Payload: map[string]string{
			"message_id": messageIDStr,
			"user_id":    userID,
			"status":     "read",
		},
	})

	msg, err := database.GlobalStore.GetMessage(context.Background(), messageID)
	if err == nil {
		hub.broadcastToChat(msg.ChatID, wsPayload, userID)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "read"})
}

func handleAddBookmark(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.BookmarkRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	messageID, err := uuid.Parse(req.MessageID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	msg, err := database.GlobalStore.GetMessage(context.Background(), messageID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Message not found")
		return
	}

	preview := msg.Content
	if len(preview) > 100 {
		preview = preview[:100]
	}

	database.GlobalStore.BookmarkMessage(context.Background(), userID, messageID, req.ChatID, preview)
	writeJSON(w, http.StatusCreated, map[string]string{"status": "bookmarked"})
}

func handleRemoveBookmark(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	database.GlobalStore.RemoveBookmark(context.Background(), userID, messageID)
	writeJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

func handleListBookmarks(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	result, err := database.GlobalStore.ListBookmarks(context.Background(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to list bookmarks")
		return
	}
	if result == nil {
		result = []model.BookmarkResponse{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"bookmarks": result})
}

func handleSyncMessages(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	after := r.URL.Query().Get("after")
	limitStr := r.URL.Query().Get("limit")

	limit := 50
	if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= 100 {
		limit = l
	}

	cursor := time.Now().Add(-30 * 24 * time.Hour) // default: 30 days back
	if after != "" {
		if t, err := time.Parse(time.RFC3339, after); err == nil {
			cursor = t
		}
	}

	ctx := context.Background()

	// Get user's conversation IDs from Neon
	parsedUserID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid user_id")
		return
	}

	var convIDs []string
	if database.Pool != nil {
		rows, err := database.Pool.Query(ctx,
			`SELECT cp.conversation_id FROM conversation_participants cp
			 JOIN conversations c ON c.id = cp.conversation_id
			 WHERE cp.user_id = $1 ORDER BY c.last_message_at DESC NULLS LAST`,
			parsedUserID,
		)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var convID string
				rows.Scan(&convID)
				convIDs = append(convIDs, convID)
			}
		}
	}

	if len(convIDs) == 0 {
		writeJSON(w, http.StatusOK, model.SyncMessagesResponse{
			Messages: []model.MessageResponse{},
			HasMore:  false,
		})
		return
	}

	// Query messages from ScyllaDB for each conversation
	allMessages := []*model.Message{}
	for _, convID := range convIDs {
		messages, _, err := database.GlobalStore.GetMessages(ctx, convID, cursor, limit)
		if err != nil {
			continue
		}
		allMessages = append(allMessages, messages...)
	}

	// Sort by created_at descending (newest first)
	for i := 0; i < len(allMessages); i++ {
		for j := i + 1; j < len(allMessages); j++ {
			if allMessages[j].CreatedAt.After(allMessages[i].CreatedAt) {
				allMessages[i], allMessages[j] = allMessages[j], allMessages[i]
			}
		}
	}

	// Trim to limit
	if len(allMessages) > limit {
		allMessages = allMessages[:limit]
	}

	resp := model.SyncMessagesResponse{
		Messages: make([]model.MessageResponse, 0, len(allMessages)),
		HasMore:  len(allMessages) >= limit,
	}

	for _, msg := range allMessages {
		reactions, _ := database.GlobalStore.GetReactions(ctx, msg.ID)
		resp.Messages = append(resp.Messages, model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			Content: msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			ReplyToID: msg.ReplyToID, Status: msg.Status,
			ModerationStatus: msg.ModerationStatus,
			EditHistory:      msg.EditHistory,
			IsDeleted:        msg.IsDeleted,
			Reactions:        reactions,
			CreatedAt:        msg.CreatedAt,
			EditedAt:         msg.EditedAt,
		})
	}

	if len(allMessages) > 0 {
		resp.NextCursor = allMessages[len(allMessages)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, resp)
}

func handleSyncStatus(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	statuses := []model.StatusEntry{}

	if database.Pool != nil {
		parsedUserID, err := model.ParseUUID(userID)
		if err != nil {
			writeError(w, http.StatusBadRequest, "VALIDATION", "invalid user_id")
			return
		}
		rows, err := database.Pool.Query(ctx, `
			SELECT DISTINCT cp2.user_id
			FROM conversation_participants cp1
			JOIN conversation_participants cp2 ON cp1.conversation_id = cp2.conversation_id
			WHERE cp1.user_id = $1 AND cp2.user_id != $1
			LIMIT 50
		`, parsedUserID)
		if err == nil {
			defer rows.Close()
			for rows.Next() {
				var participantID string
				if err := rows.Scan(&participantID); err != nil {
					continue
				}
				if database.Valkey != nil {
					count, _ := database.Valkey.SCard(ctx, "user_sessions:"+participantID).Result()
					if count > 0 {
						statuses = append(statuses, model.StatusEntry{
							ID:        participantID + "-online",
							UserID:    participantID,
							Type:      "presence",
							Content:   "online",
							CreatedAt: time.Now(),
							ExpiresAt: time.Now().Add(5 * time.Minute),
						})
					}
				}
			}
		}
	}

	writeJSON(w, http.StatusOK, model.SyncStatusResponse{
		Statuses: statuses,
		HasMore:  false,
	})
}

func handleForceRevokeDevice(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req struct {
		DeviceID string `json:"device_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	if req.DeviceID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "device_id is required")
		return
	}

	hub.disconnectDevice(userID, req.DeviceID)

	writeJSON(w, http.StatusOK, map[string]string{"status": "revoked"})
}
