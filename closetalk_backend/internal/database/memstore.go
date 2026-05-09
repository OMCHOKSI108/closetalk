package database

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/google/uuid"
)

type MemStore struct {
	mu         sync.RWMutex
	messages   map[uuid.UUID]*model.Message
	reactions  map[uuid.UUID][]model.Reaction // messageID -> reactions
	reads      map[uuid.UUID]map[string]time.Time // messageID -> userID -> read_at
	bookmarks  map[string]map[uuid.UUID]*BookmarkEntry // userID -> messageID -> entry
}

type BookmarkEntry struct {
	MessageID uuid.UUID `json:"message_id"`
	ChatID    string    `json:"chat_id"`
	Preview   string    `json:"content_preview"`
	CreatedAt time.Time `json:"created_at"`
}

func NewMemStore() *MemStore {
	return &MemStore{
		messages:  make(map[uuid.UUID]*model.Message),
		reactions: make(map[uuid.UUID][]model.Reaction),
		reads:     make(map[uuid.UUID]map[string]time.Time),
		bookmarks: make(map[string]map[uuid.UUID]*BookmarkEntry),
	}
}

func (s *MemStore) InsertMessage(ctx context.Context, msg *model.Message) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.messages[msg.ID] = msg
	return nil
}

func (s *MemStore) GetMessage(ctx context.Context, messageID uuid.UUID) (*model.Message, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	msg, ok := s.messages[messageID]
	if !ok {
		return nil, fmt.Errorf("message not found")
	}
	return msg, nil
}

func (s *MemStore) GetMessages(ctx context.Context, chatID string, cursor time.Time, limit int) ([]*model.Message, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []*model.Message
	for _, msg := range s.messages {
		if msg.ChatID == chatID && msg.CreatedAt.Before(cursor) && !msg.IsDeleted {
			result = append(result, msg)
		}
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].CreatedAt.After(result[j].CreatedAt)
	})

	if len(result) > limit {
		result = result[:limit]
	}

	return result, nil
}

func (s *MemStore) UpdateMessage(ctx context.Context, msg *model.Message) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.messages[msg.ID] = msg
	return nil
}

func (s *MemStore) DeleteMessage(ctx context.Context, messageID uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if msg, ok := s.messages[messageID]; ok {
		msg.IsDeleted = true
	}
	return nil
}

func (s *MemStore) AddReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	reactions := s.reactions[messageID]
	for i, r := range reactions {
		if r.UserID == userID && r.Emoji == emoji {
			return nil
		}
		_ = i
	}
	s.reactions[messageID] = append(reactions, model.Reaction{
		UserID: userID, Emoji: emoji, CreatedAt: time.Now(),
	})
	return nil
}

func (s *MemStore) RemoveReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	reactions := s.reactions[messageID]
	filtered := make([]model.Reaction, 0, len(reactions))
	for _, r := range reactions {
		if !(r.UserID == userID && r.Emoji == emoji) {
			filtered = append(filtered, r)
		}
	}
	s.reactions[messageID] = filtered
	return nil
}

func (s *MemStore) GetReactions(ctx context.Context, messageID uuid.UUID) ([]model.Reaction, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	reactions := s.reactions[messageID]
	if reactions == nil {
		return []model.Reaction{}, nil
	}
	return reactions, nil
}

func (s *MemStore) MarkRead(ctx context.Context, messageID uuid.UUID, userID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.reads[messageID] == nil {
		s.reads[messageID] = make(map[string]time.Time)
	}
	s.reads[messageID][userID] = time.Now()
	return nil
}

func (s *MemStore) BookmarkMessage(ctx context.Context, userID string, messageID uuid.UUID, chatID string, preview string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.bookmarks[userID] == nil {
		s.bookmarks[userID] = make(map[uuid.UUID]*BookmarkEntry)
	}
	s.bookmarks[userID][messageID] = &BookmarkEntry{
		MessageID: messageID, ChatID: chatID, Preview: preview, CreatedAt: time.Now(),
	}
	return nil
}

func (s *MemStore) RemoveBookmark(ctx context.Context, userID string, messageID uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.bookmarks[userID], messageID)
	return nil
}

func (s *MemStore) ListBookmarks(ctx context.Context, userID string) ([]model.BookmarkResponse, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	entries, ok := s.bookmarks[userID]
	if !ok {
		return []model.BookmarkResponse{}, nil
	}

	result := make([]model.BookmarkResponse, 0, len(entries))
	for _, entry := range entries {
		result = append(result, model.BookmarkResponse{
			MessageID: entry.MessageID.String(),
			ChatID:    entry.ChatID,
			Preview:   entry.Preview,
			CreatedAt: entry.CreatedAt,
		})
	}
	return result, nil
}

var GlobalStore MessageStore = NewMemStore()
