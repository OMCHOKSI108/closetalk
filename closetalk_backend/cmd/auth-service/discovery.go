package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

type contactDiscoveryRequest struct {
	Hashes []string `json:"hashes"`
}

type contactDiscoveryResult struct {
	PhoneHash   string `json:"phone_hash"`
	UserID      string `json:"user_id"`
	DisplayName string `json:"display_name"`
	Username    string `json:"username"`
	AvatarURL   string `json:"avatar_url,omitempty"`
}

func handleContactDiscovery(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req contactDiscoveryRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if len(req.Hashes) == 0 {
		writeJSON(w, http.StatusOK, map[string]any{"matches": []contactDiscoveryResult{}})
		return
	}
	if len(req.Hashes) > 1000 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "max 1000 hashes per request"})
		return
	}

	ctx := context.Background()

	results := []contactDiscoveryResult{}
	for _, hash := range req.Hashes {
		var uid, displayName, username, avatarURL string
		err := database.Pool.QueryRow(ctx,
			`SELECT u.id, u.display_name, u.username, COALESCE(u.avatar_url, '')
			 FROM users u
			 JOIN contact_hashes ch ON ch.user_id = u.id
			 WHERE ch.phone_hash = $1 AND u.deleted_at IS NULL AND u.id != $2
			 LIMIT 1`,
			hash, userID,
		).Scan(&uid, &displayName, &username, &avatarURL)
		if err == nil {
			results = append(results, contactDiscoveryResult{
				PhoneHash:   hash,
				UserID:      uid,
				DisplayName: displayName,
				Username:    username,
				AvatarURL:   avatarURL,
			})
		}
	}

	if results == nil {
		results = []contactDiscoveryResult{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"matches": results})
}

type registerPhoneHashesRequest struct {
	Hashes []string `json:"hashes"`
}

func handleRegisterPhoneHashes(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req registerPhoneHashesRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if len(req.Hashes) > 100 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "max 100 hashes"})
		return
	}

	ctx := context.Background()
	for _, hash := range req.Hashes {
		_, err := database.Pool.Exec(ctx,
			`INSERT INTO contact_hashes (user_id, phone_hash) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			userID, hash,
		)
		if err != nil {
			log.Printf("[discovery] insert hash error: %v", err)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "registered"})
}
