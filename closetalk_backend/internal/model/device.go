package model

import (
	"time"

	"github.com/google/uuid"
)

type Device struct {
	ID          uuid.UUID `json:"id"`
	UserID      uuid.UUID `json:"user_id"`
	DeviceName  string    `json:"device_name"`
	DeviceType  string    `json:"device_type"`  // phone | tablet | desktop | web
	Platform    string    `json:"platform"`     // android | ios | windows | macos | linux | web
	PublicKey   string    `json:"public_key,omitempty"`
	PushToken   string    `json:"push_token,omitempty"`
	AppVersion  string    `json:"app_version,omitempty"`
	IsActive    bool      `json:"is_active"`
	LinkedAt    time.Time `json:"linked_at"`
	LastActive  time.Time `json:"last_active"`
}

type LinkDeviceRequest struct {
	DevicePubKey string `json:"device_pub_key"`
	DeviceName   string `json:"device_name"`
	DeviceType   string `json:"device_type"`
	Platform     string `json:"platform"`
}

type LinkDeviceResponse struct {
	DeviceToken string `json:"device_token"`
	DeviceID    string `json:"device_id"`
}

type RevokeDeviceRequest struct {
	DeviceID string `json:"device_id"`
}

type DeviceResponse struct {
	ID          uuid.UUID `json:"id"`
	DeviceName  string    `json:"device_name"`
	DeviceType  string    `json:"device_type"`
	Platform    string    `json:"platform"`
	IsActive    bool      `json:"is_active"`
	LinkedAt    time.Time `json:"linked_at"`
	LastActive  time.Time `json:"last_active"`
}
