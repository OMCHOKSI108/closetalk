package main

import (
	"context"
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"

	"github.com/OMCHOKSI108/closetalk/internal/database"
)

type wsClient struct {
	conn     *websocket.Conn
	userID   string
	deviceID string
	chatIDs  map[string]bool
	send     chan []byte
}

type wsHub struct {
	mu     sync.RWMutex
	byChat map[string]map[*wsClient]bool   // chatID -> clients
	byUser map[string]map[string]*wsClient // userID -> deviceID -> client
}

func newHub() *wsHub {
	return &wsHub{
		byChat: make(map[string]map[*wsClient]bool),
		byUser: make(map[string]map[string]*wsClient),
	}
}

func (h *wsHub) run() {
	ticker := time.NewTicker(30 * time.Second)
	for range ticker.C {
		h.mu.RLock()
		var stale []*wsClient
		for chatID, clients := range h.byChat {
			for client := range clients {
				select {
				case client.send <- []byte(`{"type":"ping"}`):
				default:
					stale = append(stale, client)
				}
			}
			if len(clients) == 0 {
				delete(h.byChat, chatID)
			}
		}
		h.mu.RUnlock()

		for _, client := range stale {
			h.removeClient(client)
		}
	}
}

func (h *wsHub) register(client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for chatID := range client.chatIDs {
		if h.byChat[chatID] == nil {
			h.byChat[chatID] = make(map[*wsClient]bool)
		}
		h.byChat[chatID][client] = true
	}

	if h.byUser[client.userID] == nil {
		h.byUser[client.userID] = make(map[string]*wsClient)
	}
	h.byUser[client.userID][client.deviceID] = client
}

func (h *wsHub) removeClient(client *wsClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	for chatID := range h.byChat {
		delete(h.byChat[chatID], client)
		if len(h.byChat[chatID]) == 0 {
			delete(h.byChat, chatID)
		}
	}

	if devices, ok := h.byUser[client.userID]; ok {
		delete(devices, client.deviceID)
		if len(devices) == 0 {
			delete(h.byUser, client.userID)
		}
	}

	// Cleanup Valkey session and update last_seen
	if database.Valkey != nil {
		database.RemoveUserSession(context.Background(), client.userID, client.deviceID)
		count, err := database.Valkey.SCard(context.Background(), "user_sessions:"+client.userID).Result()
		if err == nil && count == 0 {
			if database.Pool != nil {
				_, err := database.Pool.Exec(context.Background(),
					`UPDATE users SET last_seen = now() WHERE id = $1::uuid`, client.userID)
				if err != nil {
					log.Printf("[hub] failed to update last_seen for %s: %v", client.userID, err)
				}
			}
		}
	}

	close(client.send)
}

func (h *wsHub) broadcastToChat(chatID string, message []byte, excludeUserID string) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if clients, ok := h.byChat[chatID]; ok {
		for client := range clients {
			if client.userID == excludeUserID {
				continue
			}
			select {
			case client.send <- message:
			default:
				go h.removeClient(client)
			}
		}
	}
}

func (h *wsHub) broadcastToUserDevices(userID string, message []byte, excludeDeviceID string) {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if devices, ok := h.byUser[userID]; ok {
		for deviceID, client := range devices {
			if deviceID == excludeDeviceID {
				continue
			}
			select {
			case client.send <- message:
			default:
				go h.removeClient(client)
			}
		}
	}
}

func (h *wsHub) disconnectDevice(userID string, deviceID string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if devices, ok := h.byUser[userID]; ok {
		if client, ok := devices[deviceID]; ok {
			for chatID := range h.byChat {
				delete(h.byChat[chatID], client)
				if len(h.byChat[chatID]) == 0 {
					delete(h.byChat, chatID)
				}
			}
			delete(devices, deviceID)
			if len(devices) == 0 {
				delete(h.byUser, userID)
			}

			revokeMsg, _ := json.Marshal(map[string]string{
				"type":   "device.revoked",
				"reason": "Device was revoked remotely",
			})
			select {
			case client.send <- revokeMsg:
			default:
			}
		}
	}
}

func (h *wsHub) getOnlineDevices(userID string) []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	var devices []string
	if d, ok := h.byUser[userID]; ok {
		for deviceID := range d {
			devices = append(devices, deviceID)
		}
	}
	return devices
}

func (h *wsHub) subscribeToChat(client *wsClient, chatID string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	client.chatIDs[chatID] = true

	if h.byChat[chatID] == nil {
		h.byChat[chatID] = make(map[*wsClient]bool)
	}
	h.byChat[chatID][client] = true
}

func (h *wsHub) unsubscribeFromChat(client *wsClient, chatID string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	delete(client.chatIDs, chatID)

	if clients, ok := h.byChat[chatID]; ok {
		delete(clients, client)
		if len(clients) == 0 {
			delete(h.byChat, chatID)
		}
	}
}
