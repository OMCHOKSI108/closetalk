package model

import (
	"time"

	"github.com/google/uuid"
)

func ParseUUID(s string) uuid.UUID {
	id, _ := uuid.Parse(s)
	return id
}

type User struct {
	ID           uuid.UUID  `json:"id"`
	Email        *string    `json:"email,omitempty"`
	Phone        *string    `json:"phone,omitempty"`
	PhoneHash    *string    `json:"-"`
	DisplayName  string     `json:"display_name"`
	Bio          string     `json:"bio"`
	AvatarURL    string     `json:"avatar_url,omitempty"`
	PasswordHash string     `json:"-"`
	OAuthProvider *string   `json:"oauth_provider,omitempty"`
	OAuthID      *string    `json:"-"`
	IsActive     bool       `json:"is_active"`
	IsAdmin      bool       `json:"is_admin"`
	E2EEEnabled  bool       `json:"e2ee_enabled"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	LastSeen     *time.Time `json:"last_seen,omitempty"`
	DeletedAt    *time.Time `json:"-"`
}

type RegisterRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
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
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	ExpiresIn    int          `json:"expires_in"`
	User         UserResponse `json:"user"`
	RecoveryCodes []string    `json:"recovery_codes,omitempty"`
}

type UserResponse struct {
	ID          uuid.UUID `json:"id"`
	Email       *string   `json:"email,omitempty"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url,omitempty"`
	Bio         string    `json:"bio"`
	IsAdmin     bool      `json:"is_admin"`
	CreatedAt   time.Time `json:"created_at"`
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

type ChangePasswordRequest struct {
	OldPassword string `json:"old_password"`
	NewPassword string `json:"new_password"`
}
