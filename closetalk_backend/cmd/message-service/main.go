package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
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

type wsClient struct {
	conn   *websocket.Conn
	userID string
	chatID string
	send   chan []byte
}

type wsHub struct {
	mu      sync.RWMutex
	clients map[string]map[*wsClient]bool // chatID -> clients
}

var hub = &wsHub{clients: make(map[string]map[*wsClient]bool)}

func main() {
	_ = godotenv.Load()
	auth.InitJWT()

	// Try ScyllaDB, fall back to in-memory
	if err := database.ConnectScylla(); err != nil {
		log.Printf("[warn] scylla not available, using in-memory store: %v", err)
	} else {
		database.InitScyllaSchema()
		database.GlobalStore = database.NewScyllaStore()
		defer database.CloseScylla()
	}

	// Connect Valkey for presence
	if err := database.ConnectValkey(); err != nil {
		log.Printf("[warn] valkey not available: %v", err)
	} else {
		defer database.CloseValkey()
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

// ─── WebSocket Hub ───────────────────────────────────────────────────────────

func (h *wsHub) run() {
	ticker := time.NewTicker(30 * time.Second)
	for range ticker.C {
		h.mu.RLock()
		for chatID, clients := range h.clients {
			for client := range clients {
				select {
				case client.send <- []byte(`{"type":"ping"}`):
				default:
					close(client.send)
					delete(clients, client)
				}
			}
			if len(clients) == 0 {
				delete(h.clients, chatID)
			}
		}
		h.mu.RUnlock()
	}
}

func (h *wsHub) register(chatID string, client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[chatID] == nil {
		h.clients[chatID] = make(map[*wsClient]bool)
	}
	h.clients[chatID][client] = true
}

func (h *wsHub) unregister(chatID string, client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if clients, ok := h.clients[chatID]; ok {
		delete(clients, client)
		close(client.send)
	}
}

func (h *wsHub) broadcast(chatID string, message []byte, excludeUserID string) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if clients, ok := h.clients[chatID]; ok {
		for client := range clients {
			if client.userID == excludeUserID {
				continue
			}
			select {
			case client.send <- message:
			default:
				close(client.send)
				delete(clients, client)
			}
		}
	}
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
		conn:   conn,
		userID: claims.UserID,
		chatID: chatID,
		send:   make(chan []byte, 256),
	}

	hub.register(chatID, client)

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
		hub.unregister(c.chatID, c)
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
			hub.broadcast(c.chatID, data, c.userID)
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

	if err := database.GlobalStore.InsertMessage(context.Background(), msg); err != nil {
		log.Printf("[messages] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, "INTERNAL", "Failed to send message")
		return
	}

	// Broadcast via WebSocket
	wsPayload, _ := json.Marshal(model.WebSocketMessage{
		Type: "message.new",
		Payload: model.MessageResponse{
			ID: msg.ID, ChatID: msg.ChatID, SenderID: msg.SenderID,
			Content: msg.Content, ContentType: msg.ContentType,
			Status: msg.Status, CreatedAt: msg.CreatedAt,
		},
	})
	hub.broadcast(req.ChatID, wsPayload, userID)

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
		if parsed, err := uuid.Parse(l); err == nil {
			_ = parsed
		}
	}

	messages, err := database.GlobalStore.GetMessages(context.Background(), chatID, cursor, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "INTERNAL", "Failed to fetch messages")
		return
	}

	resp := model.PaginatedMessages{
		Messages: make([]model.MessageResponse, 0, len(messages)),
		HasMore:  len(messages) >= limit,
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
	hub.broadcast(msg.ChatID, wsPayload, userID)

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
	hub.broadcast(msg.ChatID, wsPayload, userID)

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

	// Broadcast to all including sender for consistency
	hub.mu.RLock()
	if clients, ok := hub.clients[""]; ok {
		_ = clients
	}
	for chatID := range hub.clients {
		hub.broadcast(chatID, wsPayload, "")
	}
	hub.mu.RUnlock()

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
		hub.broadcast(msg.ChatID, wsPayload, userID)
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
	writeJSON(w, http.StatusOK, map[string]any{"bookmarks": []any{}})
}
