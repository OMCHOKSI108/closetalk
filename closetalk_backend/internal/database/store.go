package database

import (
	"context"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/google/uuid"
)

type MessageStore interface {
	InsertMessage(ctx context.Context, msg *model.Message) error
	GetMessage(ctx context.Context, messageID uuid.UUID) (*model.Message, error)
	GetMessages(ctx context.Context, chatID string, cursor time.Time, limit int) ([]*model.Message, bool, error)
	UpdateMessage(ctx context.Context, msg *model.Message) error
	DeleteMessage(ctx context.Context, messageID uuid.UUID) error
	AddReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error
	RemoveReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error
	GetReactions(ctx context.Context, messageID uuid.UUID) ([]model.Reaction, error)
	MarkRead(ctx context.Context, messageID uuid.UUID, userID string) error
	BookmarkMessage(ctx context.Context, userID string, messageID uuid.UUID, chatID string, preview string) error
	RemoveBookmark(ctx context.Context, userID string, messageID uuid.UUID) error
	ListBookmarks(ctx context.Context, userID string) ([]model.BookmarkResponse, error)
}
