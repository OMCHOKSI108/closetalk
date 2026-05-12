package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
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
	"github.com/OMCHOKSI108/closetalk/internal/media"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/OMCHOKSI108/closetalk/internal/notifications"
	"github.com/OMCHOKSI108/closetalk/internal/webhooks"
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

	notifications.Init()
	media.Init()

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

	// Serve uploaded voice files (public — UUID-based URLs are effectively private)
	workDir, _ := os.Getwd()
	voiceDir := filepath.Join(workDir, "uploads", "voice")
	os.MkdirAll(voiceDir, 0755)
	r.Get("/voice/*", func(w http.ResponseWriter, r *http.Request) {
		http.StripPrefix("/voice/", http.FileServer(http.Dir(voiceDir))).ServeHTTP(w, r)
	})

	// Message REST API (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)

		r.Post("/messages", handleSendMessage)
		r.Post("/messages/voice", handleUploadVoice)
		r.Post("/messages/forward", handleForwardMessage)
		r.Get("/messages/{chatId}", handleGetMessages)
		r.Get("/messages/search", handleSearchMessagesGlobal)
		r.Get("/messages/{chatId}/search", handleSearchMessages)
		r.Put("/messages/{messageId}", handleEditMessage)
		r.Delete("/messages/{messageId}", handleDeleteMessage)
		r.Post("/messages/{messageId}/react", handleReactToMessage)
		r.Post("/messages/{messageId}/read", handleMarkRead)
		r.Post("/messages/{messageId}/delivered", handleMarkDelivered)
		r.Post("/bookmarks", handleAddBookmark)
		r.Get("/bookmarks", handleListBookmarks)
		r.Delete("/bookmarks/{messageId}", handleRemoveBookmark)

		// Media upload (presigned URL)
		r.Post("/media/upload", handleRequestMediaUpload)
		r.Post("/media/upload-avatar", handleRequestAvatarUpload)

		r.Get("/moderation/queue", handleModerationQueue)
		r.Post("/moderation/{messageId}/review", handleModerationReview)
	})

	// Sync & device routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)

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

	// Periodic cleanup of expired disappearing messages
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			if database.GlobalStore != nil {
				deleted, err := database.GlobalStore.DeleteExpiredMessages(context.Background())
				if err != nil {
					log.Printf("[cleanup] delete expired messages error: %v", err)
				} else if deleted > 0 {
					log.Printf("[cleanup] deleted %d expired messages", deleted)
				}
			}
		}
	}()

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

	// Register Valkey session for presence tracking
	if database.Valkey != nil {
		database.StoreUserSession(context.Background(), claims.UserID, deviceID, 5*time.Minute)
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
		case "call.offer", "call.answer", "call.ice", "call.end", "call.reject":
			payload, ok := wsMsg.Payload.(map[string]interface{})
			if !ok {
				continue
			}
			var targetUserID string
			if tid, ok := payload["target_user_id"]; ok {
				targetUserID, _ = tid.(string)
			}
			if targetUserID == "" {
				if cid, ok := payload["chat_id"]; ok {
					targetUserID, _ = cid.(string)
				}
			}
			if targetUserID == "" {
				targetUserID = c.userID
			}
			data, _ := json.Marshal(wsMsg)
			hub.broadcastToUserDevices(targetUserID, data, "")
		}
	}
}

// ─── Username helpers ────────────────────────────────────────────────────────

func getUsernames(ctx context.Context, userIDs []string) map[string]string {
	result := map[string]string{}
	if database.Pool == nil || len(userIDs) == 0 {
		return result
	}
	seen := map[string]bool{}
	for _, id := range userIDs {
		if seen[id] {
			continue
		}
		seen[id] = true
		var username string
		err := database.Pool.QueryRow(ctx, "SELECT username FROM users WHERE id = $1::uuid", id).Scan(&username)
		if err == nil {
			result[id] = username
		}
	}
	return result
}

func sendPushNotifications(ctx context.Context, recipientIDs []string, senderName, content, chatID, messageID, senderID string) {
	if database.Pool == nil || len(recipientIDs) == 0 {
		return
	}

	preview := content
	if len(preview) > 100 {
		preview = preview[:100]
	}

	data := map[string]string{
		"chat_id":     chatID,
		"message_id":  messageID,
		"sender_id":   senderID,
		"sender_name": senderName,
	}

	for _, uid := range recipientIDs {
		rows, err := database.Pool.Query(ctx,
			`SELECT token FROM notification_tokens WHERE user_id = $1::uuid`,
			uid,
		)
		if err != nil {
			continue
		}
		for rows.Next() {
			var token string
			rows.Scan(&token)
			go notifications.SendWithRetry(ctx, token, senderName, preview, data, 3)
		}
		rows.Close()
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
	if req.MediaURL != "" {
		msg.MediaURL = req.MediaURL
	}
	if req.MediaID != "" {
		msg.MediaID = req.MediaID
	}
	if req.ForwardedFrom != "" {
		msg.ForwardedFrom = req.ForwardedFrom
	}
	if len(req.RecipientIDs) > 0 {
		msg.RecipientIDs = req.RecipientIDs
	}
	if req.DisappearAfter != "" && req.DisappearAfter != "off" {
		if d, err := parseDisappearDuration(req.DisappearAfter); err == nil {
			t := now.Add(d)
			msg.DisappearedAt = &t
		}
	}

	if err := database.GlobalStore.InsertMessage(context.Background(), msg); err != nil {
		log.Printf("[messages] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, "INTERNAL", "Failed to send message")
		return
	}

	// Index in Neon for full-text search
	go func() {
		if err := database.IndexMessage(context.Background(),
			msg.ID.String(), msg.ChatID, msg.SenderID,
			msg.Content, msg.ContentType, msg.CreatedAt,
		); err != nil {
			log.Printf("[search] index error: %v", err)
		}
	}()

	// Look up sender username
	usernames := getUsernames(context.Background(), []string{userID})

	// Broadcast via WebSocket to all devices in chat
	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.new",
		Payload: model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			SenderUsername: usernames[userID],
			Content:        msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			ForwardedFrom: msg.ForwardedFrom,
			Status:        msg.Status, CreatedAt: msg.CreatedAt,
		},
	})
	hub.broadcastToChat(req.ChatID, wsPayload, userID)
	// Multi-device fan-out: push to all recipient devices
	for _, recipientID := range req.RecipientIDs {
		hub.broadcastToUserDevices(recipientID, wsPayload, "")
	}

	// Send push notifications to recipients not currently connected
	go sendPushNotifications(context.Background(), req.RecipientIDs, usernames[userID], req.Content, msg.ChatID, msg.ID.String(), msg.SenderID)

	// Dispatch webhooks for all recipients
	go func() {
		ctx := context.Background()
		for _, recipientID := range req.RecipientIDs {
			hooks, err := webhooks.LoadActiveWebhooks(ctx, recipientID)
			if err != nil || len(hooks) == 0 {
				continue
			}
			hookData := map[string]any{
				"message_id":   msg.ID.String(),
				"chat_id":      msg.ChatID,
				"sender_id":    msg.SenderID,
				"sender_name":  usernames[userID],
				"content":      msg.Content,
				"content_type": msg.ContentType,
				"media_url":    msg.MediaURL,
				"created_at":   msg.CreatedAt,
			}
			for _, h := range hooks {
				go webhooks.DeliverWithRetry(ctx, h.ID, h.URL, h.Secret, webhooks.EventMessageNew, hookData, 3)
			}
		}
	}()

	writeJSON(w, http.StatusCreated, model.MessageResponse{
		ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
		SenderUsername: usernames[userID],
		Content:        msg.Content, ContentType: msg.ContentType,
		MediaURL: msg.MediaURL, MediaID: msg.MediaID,
		ForwardedFrom: msg.ForwardedFrom,
		Status:        msg.Status, CreatedAt: msg.CreatedAt,
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

	// Batch-lookup sender usernames
	senderIDs := make([]string, 0, len(messages))
	for _, msg := range messages {
		senderIDs = append(senderIDs, msg.SenderID)
	}
	usernames := getUsernames(context.Background(), senderIDs)

	for _, msg := range messages {
		reactions, _ := database.GlobalStore.GetReactions(context.Background(), msg.ID)
		resp.Messages = append(resp.Messages, model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			SenderUsername: usernames[msg.SenderID],
			Content:        msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			ReplyToID: msg.ReplyToID, ForwardedFrom: msg.ForwardedFrom,
			Status:           msg.Status,
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

	// Also update the message status to 'read' in the store
	readMsg, readErr := database.GlobalStore.GetMessage(context.Background(), messageID)
	if readErr == nil && readMsg.Status != "read" {
		readMsg.Status = "read"
		database.GlobalStore.UpdateMessage(context.Background(), readMsg)
	}

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.status",
		Payload: map[string]string{
			"message_id": messageIDStr,
			"user_id":    userID,
			"status":     "read",
		},
	})

	chatMsg, chatErr := database.GlobalStore.GetMessage(context.Background(), messageID)
	if chatErr == nil {
		hub.broadcastToChat(chatMsg.ChatID, wsPayload, userID)
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "read"})
}

func handleMarkDelivered(w http.ResponseWriter, r *http.Request) {
	messageIDStr := chi.URLParam(r, "messageId")
	messageID, err := uuid.Parse(messageIDStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	err = database.GlobalStore.MarkDelivered(context.Background(), messageID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to mark delivered")
		return
	}

	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.status",
		Payload: map[string]string{
			"message_id": messageIDStr,
			"status":     "delivered",
		},
	})

	msg, err := database.GlobalStore.GetMessage(context.Background(), messageID)
	if err == nil {
		hub.broadcastToChat(msg.ChatID, wsPayload, "")
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "delivered"})
}

func searchMessagesNeon(ctx context.Context, chatID, query string, cursor time.Time, limit int) ([]model.SearchResult, bool, error) {
	neonResults, hasMore, err := database.SearchMessagesNeon(ctx, chatID, query, cursor, limit)
	if err != nil || len(neonResults) > 0 {
		if err != nil {
			return nil, false, err
		}
		senderIDs := make([]string, 0, len(neonResults))
		for _, r := range neonResults {
			senderIDs = append(senderIDs, r.SenderID)
		}
		usernames := getUsernames(ctx, senderIDs)
		results := make([]model.SearchResult, 0, len(neonResults))
		for _, r := range neonResults {
			snippet := r.Content
			if len(snippet) > 150 {
				snippet = snippet[:150] + "..."
			}
			results = append(results, model.SearchResult{
				MessageID:   r.MessageID,
				ChatID:      r.ChatID,
				SenderID:    r.SenderID,
				SenderName:  usernames[r.SenderID],
				Content:     r.Content,
				ContentType: r.ContentType,
				Snippet:     snippet,
				CreatedAt:   r.CreatedAt,
			})
		}
		return results, hasMore, nil
	}
	return nil, false, nil
}

func handleSearchMessages(w http.ResponseWriter, r *http.Request) {
	chatID := chi.URLParam(r, "chatId")
	if chatID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "chat_id is required")
		return
	}

	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if query == "" {
		writeJSON(w, http.StatusOK, model.SearchMessagesResponse{Results: []model.SearchResult{}, HasMore: false})
		return
	}

	cursor := time.Now()
	if c := r.URL.Query().Get("cursor"); c != "" {
		if t, err := time.Parse(time.RFC3339, c); err == nil {
			cursor = t
		}
	}

	limit := 20
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 50 {
			limit = parsed
		}
	}

	ctx := context.Background()

	// Try Neon full-text search first (ILIKE + pg_trgm)
	results, hasMore, neonErr := searchMessagesNeon(ctx, chatID, query, cursor, limit)
	if neonErr == nil && results != nil {
		var nextCursor string
		if len(results) > 0 {
			nextCursor = results[len(results)-1].CreatedAt.Format(time.RFC3339)
		}
		writeJSON(w, http.StatusOK, model.SearchMessagesResponse{
			Results:    results,
			NextCursor: nextCursor,
			HasMore:    hasMore,
		})
		return
	}

	// Fallback to store search
	messages, hasMore, err := database.GlobalStore.SearchMessages(ctx, chatID, query, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to search messages")
		return
	}

	senderIDs := make([]string, 0, len(messages))
	for _, msg := range messages {
		senderIDs = append(senderIDs, msg.SenderID)
	}
	usernames := getUsernames(ctx, senderIDs)

	results = make([]model.SearchResult, 0, len(messages))
	for _, msg := range messages {
		snippet := msg.Content
		if len(snippet) > 150 {
			snippet = snippet[:150] + "..."
		}
		results = append(results, model.SearchResult{
			MessageID:   msg.ID.String(),
			ChatID:      msg.ChatID,
			SenderID:    msg.SenderID,
			SenderName:  usernames[msg.SenderID],
			Content:     msg.Content,
			ContentType: msg.ContentType,
			Snippet:     snippet,
			CreatedAt:   msg.CreatedAt,
		})
	}

	var nextCursor string
	if len(messages) > 0 {
		nextCursor = messages[len(messages)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, model.SearchMessagesResponse{
		Results:    results,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	})
}

func handleSearchMessagesGlobal(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "AUTH", "unauthorized")
		return
	}

	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if query == "" {
		writeJSON(w, http.StatusOK, model.SearchMessagesResponse{Results: []model.SearchResult{}, HasMore: false})
		return
	}

	cursor := time.Now()
	if c := r.URL.Query().Get("cursor"); c != "" {
		if t, err := time.Parse(time.RFC3339, c); err == nil {
			cursor = t
		}
	}

	limit := 20
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 50 {
			limit = parsed
		}
	}

	ctx := context.Background()
	neonResults, hasMore, err := database.SearchMessagesNeonGlobal(ctx, userID, query, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to search messages")
		return
	}

	senderIDs := make([]string, 0, len(neonResults))
	for _, r := range neonResults {
		senderIDs = append(senderIDs, r.SenderID)
	}
	usernames := getUsernames(ctx, senderIDs)

	results := make([]model.SearchResult, 0, len(neonResults))
	for _, r := range neonResults {
		snippet := r.Content
		if len(snippet) > 150 {
			snippet = snippet[:150] + "..."
		}
		results = append(results, model.SearchResult{
			MessageID:   r.MessageID,
			ChatID:      r.ChatID,
			SenderID:    r.SenderID,
			SenderName:  usernames[r.SenderID],
			Content:     r.Content,
			ContentType: r.ContentType,
			Snippet:     snippet,
			CreatedAt:   r.CreatedAt,
		})
	}

	var nextCursor string
	if len(neonResults) > 0 {
		nextCursor = neonResults[len(neonResults)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, model.SearchMessagesResponse{
		Results:    results,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	})
}

func handleForwardMessage(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req model.ForwardMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	if req.MessageID == "" || len(req.TargetChatIDs) == 0 {
		writeError(w, http.StatusBadRequest, "VALIDATION", "message_id and target_chat_ids are required")
		return
	}

	messageID, err := uuid.Parse(req.MessageID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	ctx := context.Background()
	original, err := database.GlobalStore.GetMessage(ctx, messageID)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "Message not found")
		return
	}

	// Resolve original sender's username
	usernames := getUsernames(ctx, []string{original.SenderID, userID})
	forwardedFrom := usernames[original.SenderID]
	if forwardedFrom == "" {
		forwardedFrom = original.SenderID
	}

	now := time.Now()
	results := make([]model.MessageResponse, 0, len(req.TargetChatIDs))

	for _, chatID := range req.TargetChatIDs {
		if chatID == "" {
			continue
		}

		newMsg := &model.Message{
			ID:            uuid.New(),
			ChatID:        chatID,
			SenderID:      userID,
			Content:       original.Content,
			ContentType:   original.ContentType,
			MediaURL:      original.MediaURL,
			MediaID:       original.MediaID,
			ForwardedFrom: forwardedFrom,
			Status:        "sent",
			CreatedAt:     now,
		}

		if err := database.GlobalStore.InsertMessage(ctx, newMsg); err != nil {
			log.Printf("[forward] insert error for chat %s: %v", chatID, err)
			continue
		}

		resp := model.MessageResponse{
			ID: newMsg.ID, ChatID: newMsg.ChatID, SenderID: newMsg.SenderID,
			SenderUsername: usernames[userID],
			Content:        newMsg.Content, ContentType: newMsg.ContentType,
			MediaURL: newMsg.MediaURL, MediaID: newMsg.MediaID,
			ForwardedFrom: forwardedFrom,
			Status:        newMsg.Status, CreatedAt: newMsg.CreatedAt,
		}

		// Broadcast via WebSocket to target chat
		wsPayload, _ := json.Marshal(model.WebSocketMessage{
			Type:    "message.new",
			Payload: resp,
		})
		hub.broadcastToChat(chatID, wsPayload, userID)
		// Also broadcast to sender's other devices
		hub.broadcastToUserDevices(userID, wsPayload, "")

		results = append(results, resp)
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"messages": results,
	})
}

func handleUploadVoice(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "user not found")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 10<<20)
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "file too large or invalid multipart")
		return
	}

	file, header, err := r.FormFile("voice")
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "voice file is required")
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	validTypes := map[string]bool{
		"audio/webm":  true,
		"audio/mp4":   true,
		"audio/ogg":   true,
		"audio/wav":   true,
		"audio/x-wav": true,
		"audio/mpeg":  true,
	}
	if !validTypes[contentType] {
		writeError(w, http.StatusBadRequest, "VALIDATION", "unsupported audio format")
		return
	}

	duration := r.FormValue("duration")
	if duration == "" {
		duration = "0"
	}

	data, err := io.ReadAll(file)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to read file")
		return
	}

	workDir, _ := os.Getwd()
	voiceDir := filepath.Join(workDir, "uploads", "voice")
	os.MkdirAll(voiceDir, 0755)

	ext := filepath.Ext(header.Filename)
	if ext == "" {
		switch contentType {
		case "audio/webm":
			ext = ".webm"
		case "audio/mp4":
			ext = ".mp4"
		case "audio/ogg":
			ext = ".ogg"
		case "audio/wav", "audio/x-wav":
			ext = ".wav"
		case "audio/mpeg":
			ext = ".mp3"
		default:
			ext = ".webm"
		}
	}

	filename := uuid.New().String() + ext
	filePath := filepath.Join(voiceDir, filename)
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL", "failed to save file")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{
		"media_url": "/voice/" + filename,
		"duration":  duration,
	})
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

	result, hasMore, err := database.GlobalStore.ListBookmarks(context.Background(), userID, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to list bookmarks")
		return
	}
	if result == nil {
		result = []model.BookmarkResponse{}
	}

	var nextCursor string
	if len(result) > 0 {
		nextCursor = result[len(result)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"bookmarks":   result,
		"has_more":    hasMore,
		"next_cursor": nextCursor,
	})
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

	// Batch-lookup sender usernames
	senderIDs := make([]string, 0, len(allMessages))
	for _, msg := range allMessages {
		senderIDs = append(senderIDs, msg.SenderID)
	}
	usernames := getUsernames(ctx, senderIDs)

	for _, msg := range allMessages {
		reactions, _ := database.GlobalStore.GetReactions(ctx, msg.ID)
		resp.Messages = append(resp.Messages, model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			SenderUsername: usernames[msg.SenderID],
			Content:        msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			ReplyToID: msg.ReplyToID, ForwardedFrom: msg.ForwardedFrom,
			Status:           msg.Status,
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

func handleModerationQueue(w http.ResponseWriter, r *http.Request) {
	cursor := time.Now()
	if c := r.URL.Query().Get("cursor"); c != "" {
		if t, err := time.Parse(time.RFC3339, c); err == nil {
			cursor = t
		}
	}

	limit := 20
	if l := r.URL.Query().Get("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 50 {
			limit = parsed
		}
	}

	ctx := context.Background()
	messages, hasMore, err := database.GlobalStore.ListFlaggedMessages(ctx, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to list flagged messages")
		return
	}

	results := make([]model.MessageResponse, 0, len(messages))
	for _, msg := range messages {
		results = append(results, model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			Content: msg.Content, ContentType: msg.ContentType,
			MediaURL: msg.MediaURL, MediaID: msg.MediaID,
			Status: msg.Status, CreatedAt: msg.CreatedAt,
			ModerationStatus: msg.ModerationStatus,
		})
	}

	var nextCursor string
	if len(messages) > 0 {
		nextCursor = messages[len(messages)-1].CreatedAt.Format(time.RFC3339)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"messages":    results,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}

func handleModerationReview(w http.ResponseWriter, r *http.Request) {
	messageID := chi.URLParam(r, "messageId")
	if messageID == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "message_id is required")
		return
	}

	var req struct {
		Action string `json:"action"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	if req.Action != "approve" && req.Action != "reject" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "action must be 'approve' or 'reject'")
		return
	}

	id, err := uuid.Parse(messageID)
	if err != nil {
		writeError(w, http.StatusBadRequest, "VALIDATION", "invalid message_id")
		return
	}

	ctx := context.Background()
	msg, err := database.GlobalStore.GetMessage(ctx, id)
	if err != nil {
		writeError(w, http.StatusNotFound, "NOT_FOUND", "message not found")
		return
	}

	status := "approved"
	if req.Action == "reject" {
		status = "rejected"
	}

	msg.ModerationStatus = status
	if err := database.GlobalStore.UpdateMessage(ctx, msg); err != nil {
		writeError(w, http.StatusInternalServerError, "DB_ERROR", "failed to update moderation status")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": status})
}

func parseDisappearDuration(s string) (time.Duration, error) {
	switch s {
	case "5s":
		return 5 * time.Second, nil
	case "30s":
		return 30 * time.Second, nil
	case "5m":
		return 5 * time.Minute, nil
	case "1h":
		return time.Hour, nil
	case "24h":
		return 24 * time.Hour, nil
	default:
		return 0, fmt.Errorf("unknown disappear duration: %s", s)
	}
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

// ─── Media handlers ──────────────────────────────────────────────────────────

func handleRequestMediaUpload(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req struct {
		FileName    string `json:"file_name"`
		ContentType string `json:"content_type"`
		Folder      string `json:"folder,omitempty"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	if req.FileName == "" {
		writeError(w, http.StatusBadRequest, "VALIDATION", "file_name is required")
		return
	}

	ctx := context.Background()
	folder := req.Folder
	if folder == "" {
		folder = "uploads"
	}

	uploadURL, mediaURL, err := media.GenerateUploadURLWithFolder(ctx, folder, req.FileName, req.ContentType)
	if err != nil {
		log.Printf("[media] generate upload url error: %v", err)
		writeError(w, http.StatusInternalServerError, "MEDIA_ERROR", "failed to generate upload URL")
		return
	}

	if database.Pool != nil {
		database.Pool.Exec(ctx,
			`INSERT INTO media (user_id, object_key, file_name, content_type, media_url) VALUES ($1::uuid, $2, $3, $4, $5)`,
			userID, folder+"/"+req.FileName, req.FileName, req.ContentType, mediaURL,
		)
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"upload_url": uploadURL,
		"media_url":  mediaURL,
	})
}

func handleRequestAvatarUpload(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	uploadURL, mediaURL, err := media.GenerateUploadURLWithFolder(context.Background(), "avatars", "avatar.jpg", "image/jpeg")
	if err != nil {
		log.Printf("[media] avatar upload url error: %v", err)
		writeError(w, http.StatusInternalServerError, "MEDIA_ERROR", "failed to generate upload URL")
		return
	}

	if database.Pool != nil {
		database.Pool.Exec(context.Background(),
			`UPDATE users SET avatar_url = $2 WHERE id = $1::uuid`,
			userID, mediaURL,
		)
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"upload_url": uploadURL,
		"media_url":  mediaURL,
	})
}
