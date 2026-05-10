package database

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/google/uuid"
)

type ScyllaMessageStore struct{}

func NewScyllaStore() *ScyllaMessageStore {
	return &ScyllaMessageStore{}
}

func (s *ScyllaMessageStore) InsertMessage(ctx context.Context, msg *model.Message) error {
	recipientIDs := ""
	if len(msg.RecipientIDs) > 0 {
		b, _ := json.Marshal(msg.RecipientIDs)
		recipientIDs = string(b)
	}
	return Scylla.Query(
		`INSERT INTO closetalk.messages (chat_id, created_at, message_id, sender_id, sender_device_id,
		 recipient_ids, content, content_type, media_url, media_id, reply_to_id, status, moderation_status, is_deleted)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		msg.ChatID, msg.CreatedAt, msg.ID, msg.SenderID, msg.SenderDeviceID,
		recipientIDs, msg.Content, msg.ContentType, msg.MediaURL, msg.MediaID, msg.ReplyToID,
		msg.Status, msg.ModerationStatus, msg.IsDeleted,
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) GetMessage(ctx context.Context, messageID uuid.UUID) (*model.Message, error) {
	var msg model.Message
	err := Scylla.Query(
		`SELECT chat_id, created_at, message_id, sender_id, content, content_type,
		 media_url, media_id, reply_to_id, status, moderation_status, is_deleted
		 FROM closetalk.messages WHERE message_id = ? ALLOW FILTERING`,
		messageID,
	).WithContext(ctx).Scan(
		&msg.ChatID, &msg.CreatedAt, &msg.ID, &msg.SenderID,
		&msg.Content, &msg.ContentType, &msg.MediaURL, &msg.MediaID,
		&msg.ReplyToID, &msg.Status, &msg.ModerationStatus, &msg.IsDeleted,
	)
	if err != nil {
		return nil, fmt.Errorf("get message: %w", err)
	}
	return &msg, nil
}

func (s *ScyllaMessageStore) GetMessages(ctx context.Context, chatID string, cursor time.Time, limit int) ([]*model.Message, bool, error) {
	iter := Scylla.Query(
		`SELECT chat_id, created_at, message_id, sender_id, content, content_type,
		 media_url, media_id, reply_to_id, status, moderation_status, is_deleted
		 FROM closetalk.messages
		 WHERE chat_id = ? AND created_at < ?
		 ORDER BY created_at DESC
		 LIMIT ?`,
		chatID, cursor, limit,
	).WithContext(ctx).Iter()

	var messages []*model.Message
	var msg model.Message
	for iter.Scan(
		&msg.ChatID, &msg.CreatedAt, &msg.ID, &msg.SenderID,
		&msg.Content, &msg.ContentType, &msg.MediaURL, &msg.MediaID,
		&msg.ReplyToID, &msg.Status, &msg.ModerationStatus, &msg.IsDeleted,
	) {
		m := msg
		messages = append(messages, &m)
	}

	if err := iter.Close(); err != nil {
		return nil, false, fmt.Errorf("get messages: %w", err)
	}

	hasMore := len(messages) == limit
	return messages, hasMore, nil
}

func (s *ScyllaMessageStore) UpdateMessage(ctx context.Context, msg *model.Message) error {
	return Scylla.Query(
		`UPDATE closetalk.messages SET content = ?, edit_history = ?, edited_at = ?,
		 status = ?, moderation_status = ?
		 WHERE chat_id = ? AND created_at = ? AND message_id = ?`,
		msg.Content, msg.EditHistory, msg.EditedAt,
		msg.Status, msg.ModerationStatus,
		msg.ChatID, msg.CreatedAt, msg.ID,
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) DeleteMessage(ctx context.Context, messageID uuid.UUID) error {
	// Soft delete: we need chat_id and created_at for the partition key
	// This requires the full primary key. We'll use a lightweight approach.
	return Scylla.Query(
		`UPDATE closetalk.messages SET is_deleted = true WHERE message_id = ? ALLOW FILTERING`,
		messageID,
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) AddReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	return Scylla.Query(
		`INSERT INTO closetalk.message_reactions (message_id, user_id, emoji, created_at) VALUES (?, ?, ?, ?)`,
		messageID, userID, emoji, time.Now(),
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) RemoveReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	return Scylla.Query(
		`DELETE FROM closetalk.message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?`,
		messageID, userID, emoji,
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) GetReactions(ctx context.Context, messageID uuid.UUID) ([]model.Reaction, error) {
	iter := Scylla.Query(
		`SELECT user_id, emoji, created_at FROM closetalk.message_reactions WHERE message_id = ?`,
		messageID,
	).WithContext(ctx).Iter()

	var reactions []model.Reaction
	var r model.Reaction
	for iter.Scan(&r.UserID, &r.Emoji, &r.CreatedAt) {
		reactions = append(reactions, r)
	}

	if err := iter.Close(); err != nil {
		return nil, err
	}

	if reactions == nil {
		return []model.Reaction{}, nil
	}
	return reactions, nil
}

func (s *ScyllaMessageStore) MarkRead(ctx context.Context, messageID uuid.UUID, userID string) error {
	return Scylla.Query(
		`INSERT INTO closetalk.message_reads (message_id, user_id, read_at) VALUES (?, ?, ?)`,
		messageID, userID, time.Now(),
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) BookmarkMessage(ctx context.Context, userID string, messageID uuid.UUID, chatID string, preview string) error {
	return Scylla.Query(
		`INSERT INTO closetalk.bookmarks (user_id, message_id, chat_id, content_preview, created_at) VALUES (?, ?, ?, ?, ?)`,
		userID, messageID, chatID, preview, time.Now(),
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) RemoveBookmark(ctx context.Context, userID string, messageID uuid.UUID) error {
	return Scylla.Query(
		`DELETE FROM closetalk.bookmarks WHERE user_id = ? AND message_id = ?`,
		userID, messageID,
	).WithContext(ctx).Exec()
}

func (s *ScyllaMessageStore) ListBookmarks(ctx context.Context, userID string, cursor time.Time, limit int) ([]model.BookmarkResponse, bool, error) {
	iter := Scylla.Query(
		`SELECT message_id, chat_id, content_preview, created_at FROM closetalk.bookmarks
		 WHERE user_id = ? AND created_at < ?
		 ORDER BY created_at DESC
		 LIMIT ?`,
		userID, cursor, limit,
	).WithContext(ctx).Iter()

	var result []model.BookmarkResponse
	var msgID uuid.UUID
	var chatID, preview string
	var createdAt time.Time
	for iter.Scan(&msgID, &chatID, &preview, &createdAt) {
		result = append(result, model.BookmarkResponse{
			MessageID: msgID.String(),
			ChatID:    chatID,
			Preview:   preview,
			CreatedAt: createdAt,
		})
	}
	if err := iter.Close(); err != nil {
		return nil, false, err
	}

	hasMore := len(result) == limit
	return result, hasMore, nil
}

// Ensure compile-time interface compliance
var _ MessageStore = (*ScyllaMessageStore)(nil)
var _ MessageStore = (*MemStore)(nil)
