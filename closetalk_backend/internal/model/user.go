package model

import (
	"time"

	"github.com/google/uuid"
)

func ParseUUID(s string) (uuid.UUID, error) {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.Nil, err
	}
	return id, nil
}

func ParseUUIDOrNil(s string) uuid.UUID {
	id, err := uuid.Parse(s)
	if err != nil {
		return uuid.Nil
	}
	return id
}

type User struct {
	ID                uuid.UUID  `json:"id"`
	Email             *string    `json:"email,omitempty"`
	Phone             *string    `json:"phone,omitempty"`
	PhoneHash         *string    `json:"-"`
	Username          string     `json:"username"`
	DisplayName       string     `json:"display_name"`
	Bio               string     `json:"bio"`
	AvatarURL         string     `json:"avatar_url,omitempty"`
	PasswordHash      string     `json:"-"`
	OAuthProvider     *string    `json:"oauth_provider,omitempty"`
	OAuthID           *string    `json:"-"`
	IsActive          bool       `json:"is_active"`
	IsAdmin           bool       `json:"is_admin"`
	E2EEEnabled       bool       `json:"e2ee_enabled"`
	UsernameChanges   int        `json:"username_changes"`
	UsernameChangedAt *time.Time `json:"username_changed_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
	LastSeen          *time.Time `json:"last_seen,omitempty"`
	DeletedAt         *time.Time `json:"-"`
}

type RegisterRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
	Username    string `json:"username"`
}

type RegisterInitRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
	Username    string `json:"username"`
}

type RegisterVerifyRequest struct {
	Email string `json:"email"`
	OTP   string `json:"otp"`
}

type RegisterInitResponse struct {
	Message  string `json:"message"`
	Email    string `json:"email"`
	Cooldown int    `json:"cooldown"` // seconds until next OTP
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type OAuthRequest struct {
	Code     string `json:"code"`
	Provider string `json:"provider"` // google | apple | github
}

type AuthResponse struct {
	AccessToken   string       `json:"access_token"`
	RefreshToken  string       `json:"refresh_token"`
	ExpiresIn     int          `json:"expires_in"`
	User          UserResponse `json:"user"`
	RecoveryCodes []string     `json:"recovery_codes,omitempty"`
}

type UserResponse struct {
	ID                uuid.UUID  `json:"id"`
	Email             *string    `json:"email,omitempty"`
	Username          string     `json:"username"`
	DisplayName       string     `json:"display_name"`
	AvatarURL         string     `json:"avatar_url,omitempty"`
	Bio               string     `json:"bio"`
	IsAdmin           bool       `json:"is_admin"`
	UsernameChanges   int        `json:"username_changes"`
	UsernameChangedAt *time.Time `json:"username_changed_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
}

type UpdateProfileRequest struct {
	DisplayName *string `json:"display_name,omitempty"`
	Username    *string `json:"username,omitempty"`
	Bio         *string `json:"bio,omitempty"`
	AvatarURL   *string `json:"avatar_url,omitempty"`
}

type UpdateProfileResponse struct {
	User             UserResponse `json:"user"`
	RemainingChanges int          `json:"remaining_changes"`
	NextChangeAt     *time.Time   `json:"next_change_at,omitempty"`
}

type UserSearchRequest struct {
	Query string `json:"q"`
}

type UserSearchResponse struct {
	Users []UserResponse `json:"users"`
}

type RegisterNotificationTokenRequest struct {
	Token    string `json:"token"`
	Platform string `json:"platform"` // apns | fcm
	DeviceID string `json:"device_id"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type RefreshResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

type RecoverRequest struct {
	Code string `json:"code"`
}

type RecoverEmailRequest struct {
	Email string `json:"email"`
}

type RecoverEmailCompleteRequest struct {
	Token       string `json:"token"`
	NewPassword string `json:"new_password"`
}

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}
