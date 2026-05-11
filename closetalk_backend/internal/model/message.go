package model

import (
	"time"

	"github.com/google/uuid"
)

type Message struct {
	ID               uuid.UUID   `json:"id"`
	ChatID           string      `json:"chat_id"`
	SenderID         string      `json:"sender_id"`
	SenderDeviceID   string      `json:"sender_device_id,omitempty"`
	RecipientIDs     []string    `json:"recipient_ids,omitempty"` // for multi-device fan-out
	Content          string      `json:"content"`
	ContentType      string      `json:"content_type"` // text | image | video | file | voice | poll
	MediaURL         string      `json:"media_url,omitempty"`
	MediaID          string      `json:"media_id,omitempty"`
	ReplyToID        *uuid.UUID  `json:"reply_to_id,omitempty"`
	ForwardedFrom    string      `json:"forwarded_from,omitempty"`
	Status           string      `json:"status"` // sending | sent | delivered | read
	ModerationStatus string      `json:"moderation_status,omitempty"`
	EditHistory      []EditEntry `json:"edit_history,omitempty"`
	IsDeleted        bool        `json:"is_deleted,omitempty"`
	CreatedAt        time.Time   `json:"created_at"`
	EditedAt         *time.Time  `json:"edited_at,omitempty"`
	DisappearedAt    *time.Time  `json:"disappeared_at,omitempty"`
}

type EditEntry struct {
	Content  string    `json:"content"`
	EditedAt time.Time `json:"edited_at"`
}

type SendMessageRequest struct {
	ChatID         string   `json:"chat_id"`
	Content        string   `json:"content"`
	ContentType    string   `json:"content_type"`
	MediaURL       string   `json:"media_url,omitempty"`
	MediaID        string   `json:"media_id,omitempty"`
	ReplyToID      string   `json:"reply_to_id,omitempty"`
	ForwardedFrom  string   `json:"forwarded_from,omitempty"`
	DisappearAfter string   `json:"disappear_after,omitempty"`
	RecipientIDs   []string `json:"recipient_ids,omitempty"` // for multi-device fan-out
}

type ForwardMessageRequest struct {
	MessageID     string   `json:"message_id"`
	TargetChatIDs []string `json:"target_chat_ids"`
}

type EditMessageRequest struct {
	Content string `json:"content"`
}

type ReactToMessageRequest struct {
	Emoji string `json:"emoji"`
}

type MessageResponse struct {
	ID               uuid.UUID   `json:"id"`
	ChatID           string      `json:"chat_id"`
	SenderID         string      `json:"sender_id"`
	SenderUsername   string      `json:"sender_username,omitempty"`
	RecipientIDs     []string    `json:"recipient_ids,omitempty"`
	Content          string      `json:"content"`
	ContentType      string      `json:"content_type"`
	MediaURL         string      `json:"media_url,omitempty"`
	MediaID          string      `json:"media_id,omitempty"`
	ReplyToID        *uuid.UUID  `json:"reply_to_id,omitempty"`
	ForwardedFrom    string      `json:"forwarded_from,omitempty"`
	Status           string      `json:"status"`
	ModerationStatus string      `json:"moderation_status,omitempty"`
	EditHistory      []EditEntry `json:"edit_history,omitempty"`
	IsDeleted        bool        `json:"is_deleted,omitempty"`
	Reactions        []Reaction  `json:"reactions,omitempty"`
	CreatedAt        time.Time   `json:"created_at"`
	EditedAt         *time.Time  `json:"edited_at,omitempty"`
	DisappearedAt    *time.Time  `json:"disappeared_at,omitempty"`
}

type Reaction struct {
	UserID    string    `json:"user_id"`
	Emoji     string    `json:"emoji"`
	CreatedAt time.Time `json:"created_at"`
}

type PaginatedMessages struct {
	Messages   []MessageResponse `json:"messages"`
	NextCursor string            `json:"next_cursor,omitempty"`
	HasMore    bool              `json:"has_more"`
}

type BookmarkRequest struct {
	MessageID string `json:"message_id"`
	ChatID    string `json:"chat_id"`
}

type BookmarkResponse struct {
	MessageID string    `json:"message_id"`
	ChatID    string    `json:"chat_id"`
	Preview   string    `json:"content_preview"`
	CreatedAt time.Time `json:"created_at"`
}

type WebSocketMessage struct {
	Type    string `json:"type"` // message.new | message.updated | message.status | typing.start | typing.stop
	Payload any    `json:"payload"`
}

type ReadReceipt struct {
	MessageID string    `json:"message_id"`
	UserID    string    `json:"user_id"`
	ReadAt    time.Time `json:"read_at"`
}

type SyncMessagesRequest struct {
	After string `json:"after,omitempty"` // cursor (created_at timestamp)
	Limit int    `json:"limit,omitempty"`
}

type SyncMessagesResponse struct {
	Messages   []MessageResponse `json:"messages"`
	NextCursor string            `json:"next_cursor,omitempty"`
	HasMore    bool              `json:"has_more"`
}

type SyncStatusRequest struct {
	After string `json:"after,omitempty"`
}

type SyncStatusResponse struct {
	Statuses   []StatusEntry `json:"statuses"`
	NextCursor string        `json:"next_cursor,omitempty"`
	HasMore    bool          `json:"has_more"`
}

type StatusEntry struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Type      string    `json:"type"` // text | image | video
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
	ExpiresAt time.Time `json:"expires_at"`
}

type SearchMessagesRequest struct {
	ChatID string `json:"chat_id"`
	Query  string `json:"query"`
	Cursor string `json:"cursor,omitempty"`
	Limit  int    `json:"limit,omitempty"`
}

type SearchResult struct {
	MessageID   string    `json:"message_id"`
	ChatID      string    `json:"chat_id"`
	SenderID    string    `json:"sender_id"`
	SenderName  string    `json:"sender_name,omitempty"`
	Content     string    `json:"content"`
	ContentType string    `json:"content_type"`
	Snippet     string    `json:"snippet"`
	CreatedAt   time.Time `json:"created_at"`
}

type SearchMessagesResponse struct {
	Results    []SearchResult `json:"results"`
	NextCursor string         `json:"next_cursor,omitempty"`
	HasMore    bool           `json:"has_more"`
}

type SearchMessagesRequestParams struct {
	Query  string `json:"q"`
	Cursor string `json:"cursor"`
	Limit  int    `json:"limit"`
}
