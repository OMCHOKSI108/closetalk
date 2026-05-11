package model

import (
	"time"

	"github.com/google/uuid"
)

type Group struct {
	ID               uuid.UUID `json:"id"`
	ConversationID   uuid.UUID `json:"conversation_id"`
	Name             string    `json:"name"`
	Description      string    `json:"description"`
	AvatarURL        string    `json:"avatar_url,omitempty"`
	CreatedBy        uuid.UUID `json:"created_by"`
	IsPublic         bool      `json:"is_public"`
	MemberLimit      int       `json:"member_limit"`
	MessageRetention string    `json:"message_retention"`
	DisappearingMsg  string    `json:"disappearing_msg"`
	InviteCode       *string   `json:"invite_code,omitempty"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
	MemberCount      int       `json:"member_count,omitempty"`
}

type GroupMember struct {
	GroupID    uuid.UUID  `json:"group_id"`
	UserID     uuid.UUID  `json:"user_id"`
	Role       string     `json:"role"`
	JoinedAt   time.Time  `json:"joined_at"`
	InvitedBy  *uuid.UUID `json:"invited_by,omitempty"`
	MutedUntil *time.Time `json:"muted_until,omitempty"`
}

type GroupInvite struct {
	ID        uuid.UUID `json:"id"`
	GroupID   uuid.UUID `json:"group_id"`
	Code      string    `json:"code"`
	CreatedBy uuid.UUID `json:"created_by"`
	ExpiresAt time.Time `json:"expires_at"`
	MaxUses   *int      `json:"max_uses,omitempty"`
	UseCount  int       `json:"use_count"`
	CreatedAt time.Time `json:"created_at"`
}

type PinnedMessage struct {
	ID         uuid.UUID  `json:"id"`
	GroupID    uuid.UUID  `json:"group_id"`
	MessageID  string     `json:"message_id"`
	PinnedBy   uuid.UUID  `json:"pinned_by"`
	PinnedAt   time.Time  `json:"pinned_at"`
	UnpinnedAt *time.Time `json:"unpinned_at,omitempty"`
}

type CreateGroupRequest struct {
	Name        string   `json:"name"`
	Description string   `json:"description,omitempty"`
	AvatarURL   string   `json:"avatar_url,omitempty"`
	MemberIDs   []string `json:"member_ids"`
	IsPublic    bool     `json:"is_public"`
}

type UpdateGroupSettingsRequest struct {
	Name             *string `json:"name,omitempty"`
	Description      *string `json:"description,omitempty"`
	AvatarURL        *string `json:"avatar_url,omitempty"`
	IsPublic         *bool   `json:"is_public,omitempty"`
	MemberLimit      *int    `json:"member_limit,omitempty"`
	MessageRetention *string `json:"message_retention,omitempty"`
	DisappearingMsg  *string `json:"disappearing_msg,omitempty"`
}

type AddMemberRequest struct {
	UserIDs []string `json:"user_ids"`
}

type UpdateRoleRequest struct {
	Role string `json:"role"`
}

type JoinGroupRequest struct {
	Code    string `json:"code,omitempty"`
	GroupID string `json:"group_id,omitempty"`
}

type InviteResponse struct {
	Code      string    `json:"code"`
	ExpiresAt time.Time `json:"expires_at"`
	URL       string    `json:"url"`
}

type PinMessageRequest struct {
	MessageID string `json:"message_id"`
}

type GroupResponse struct {
	ID               uuid.UUID               `json:"id"`
	Name             string                  `json:"name"`
	Description      string                  `json:"description"`
	AvatarURL        string                  `json:"avatar_url,omitempty"`
	CreatedBy        uuid.UUID               `json:"created_by"`
	IsPublic         bool                    `json:"is_public"`
	MemberLimit      int                     `json:"member_limit"`
	MessageRetention string                  `json:"message_retention"`
	DisappearingMsg  string                  `json:"disappearing_msg"`
	InviteCode       *string                 `json:"invite_code,omitempty"`
	MemberCount      int                     `json:"member_count"`
	Members          []GroupMemberResponse   `json:"members,omitempty"`
	PinnedMessages   []PinnedMessageResponse `json:"pinned_messages,omitempty"`
	CreatedAt        time.Time               `json:"created_at"`
	UpdatedAt        time.Time               `json:"updated_at"`
}

type GroupMemberResponse struct {
	UserID      uuid.UUID `json:"user_id"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url,omitempty"`
	Role        string    `json:"role"`
	JoinedAt    time.Time `json:"joined_at"`
}

type PinnedMessageResponse struct {
	MessageID string    `json:"message_id"`
	PinnedBy  uuid.UUID `json:"pinned_by"`
	PinnedAt  time.Time `json:"pinned_at"`
}
