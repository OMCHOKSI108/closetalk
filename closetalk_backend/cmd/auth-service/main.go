package main

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sesv2"
	"github.com/aws/aws-sdk-go-v2/service/sesv2/types"
	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/google/uuid"
	"github.com/joho/godotenv"

	"github.com/OMCHOKSI108/closetalk/internal/auth"
	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

type googleKeysResponse struct {
	Keys []googleKey `json:"keys"`
}

type googleKey struct {
	Kty string `json:"kty"`
	Alg string `json:"alg"`
	Use string `json:"use"`
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type googleTokenPayload struct {
	Iss           string `json:"iss"`
	Sub           string `json:"sub"`
	Azp           string `json:"azp"`
	Aud           string `json:"aud"`
	Iat           int64  `json:"iat"`
	Exp           int64  `json:"exp"`
	Email         string `json:"email"`
	EmailVerified string `json:"email_verified"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
}

// Cache Google's public keys (refreshed every hour)
var (
	googleKeysCache     []googleKey
	googleKeysCacheTime time.Time
	googleClientID      string
)

func main() {
	// Load .env if present
	_ = godotenv.Load()

	// Initialize auth
	auth.InitJWT()

	googleClientID = os.Getenv("GOOGLE_CLIENT_ID")

	// Connect databases
	if err := database.ConnectNeon(); err != nil {
		log.Fatalf("[fatal] database: %v", err)
	}
	defer database.CloseNeon()

	if err := database.ConnectValkey(); err != nil {
		log.Fatalf("[fatal] valkey: %v", err)
	}
	defer database.CloseValkey()

	// Run migrations
	if err := database.RunMigrations(); err != nil {
		log.Fatalf("[fatal] migrations: %v", err)
	}

	// Router
	r := chi.NewRouter()

	// Global middleware
	r.Use(chimw.RequestID)
	r.Use(chimw.RealIP)
	r.Use(middleware.Logging)
	r.Use(chimw.Recoverer)
	r.Use(chimw.Timeout(30 * time.Second))
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "Idempotency-Key"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	// Root API info
	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"service": "Closetalk",
			"version": "1.0.0",
			"endpoints": map[string]string{
				"health":           "/health",
				"auth_register":    "/auth/register",
				"auth_login":       "/auth/login",
				"auth_refresh":     "/auth/refresh",
				"auth_recover":     "/auth/recover",
				"messages":         "/messages/{chatId}",
				"bookmarks":        "/bookmarks",
				"websocket":        "/ws",
			},
			"documentation": "https://github.com/OMCHOKSI108/closetalk",
		})
	})

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "auth-service"})
	})

	// Auth routes (no auth required)
	r.Route("/auth", func(r chi.Router) {
		r.Post("/register", handleRegister)
		r.Post("/login", handleLogin)
		r.Post("/oauth", handleOAuth)
		r.Post("/refresh", handleRefresh)
		r.Post("/recover", handleRecover)
		r.Post("/recover/email", handleRecoverEmail)
		r.Post("/recover/email/complete", handleRecoverEmailComplete)
	})

	// Auth routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Put("/auth/password", handleChangePassword)
		r.Post("/auth/logout", handleLogout)
	})

	// Device routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Get("/devices", handleListDevices)
		r.Post("/devices/link", handleLinkDevice)
		r.Post("/devices/revoke", handleRevokeDevice)
	})

	// Group routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Get("/groups", handleListGroups)
		r.Post("/groups", handleCreateGroup)
		r.Get("/groups/{id}", handleGetGroup)
		r.Post("/groups/{id}/invite", handleGenerateInvite)
		r.Post("/groups/join", handleJoinGroup)
		r.Post("/groups/{id}/members", handleAddMembers)
		r.Delete("/groups/{id}/members/{userId}", handleRemoveMember)
		r.Put("/groups/{id}/members/{userId}/role", handleUpdateRole)
		r.Post("/groups/{id}/leave", handleLeaveGroup)
		r.Put("/groups/{id}/settings", handleUpdateGroupSettings)
		r.Post("/groups/{id}/pin", handlePinMessage)
		r.Delete("/groups/{id}/pin/{messageId}", handleUnpinMessage)
	})

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("[auth-service] starting on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[fatal] server: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("[auth-service] shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

// ─── Handlers ────────────────────────────────────────────────────────────────

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, err *model.AppError) {
	writeJSON(w, status, model.ErrorResponse{
		Error: err.Message,
		Code:  err.Code,
	})
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req model.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" || req.Password == "" || req.DisplayName == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email, password, and display_name are required"})
		return
	}

	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "WEAK_PASSWORD", Message: "password must be at least 8 characters"})
		return
	}

	ctx := context.Background()

	// Check existing user
	var exists bool
	database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)", req.Email).Scan(&exists)
	if exists {
		writeError(w, http.StatusConflict, model.ErrEmailTaken)
		return
	}

	// Hash password
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to process password"})
		return
	}

	// Insert user
	var userID string
	err = database.Pool.QueryRow(ctx,
		`INSERT INTO users (email, display_name, password_hash)
		 VALUES ($1, $2, $3)
		 RETURNING id`,
		req.Email, req.DisplayName, hash,
	).Scan(&userID)
	if err != nil {
		log.Printf("[register] insert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to create user"})
		return
	}

	// Insert default settings
	_, _ = database.Pool.Exec(ctx,
		`INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`, userID)

	// Generate recovery codes
	codes, err := auth.GenerateRecoveryCodes(10)
	if err != nil {
		log.Printf("[register] recovery code error: %v", err)
	} else {
		for _, code := range codes {
			hashed := auth.HashRecoveryCode(code)
			database.Pool.Exec(ctx,
				`INSERT INTO recovery_codes (user_id, code_hash) VALUES ($1, $2)`, userID, hashed)
		}
	}

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	// Generate tokens
	accessToken, _ := auth.GenerateAccessToken(parsedID, false)
	refreshToken, _ := auth.GenerateRefreshToken()

	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	writeJSON(w, http.StatusCreated, model.AuthResponse{
		AccessToken:   accessToken,
		RefreshToken:  refreshToken,
		ExpiresIn:     900,
		User:          model.UserResponse{ID: parsedID, Email: &req.Email, DisplayName: req.DisplayName},
		RecoveryCodes: codes,
	})
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	var req model.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email and password are required"})
		return
	}

	ctx := context.Background()

	var user model.User
	err := database.Pool.QueryRow(ctx,
		`SELECT id, email, display_name, avatar_url, bio, password_hash, is_admin, is_active, created_at
		 FROM users WHERE email = $1 AND deleted_at IS NULL`,
		req.Email,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.AvatarURL, &user.Bio,
		&user.PasswordHash, &user.IsAdmin, &user.IsActive, &user.CreatedAt)
	if err != nil {
		writeError(w, http.StatusUnauthorized, model.ErrInvalidCredentials)
		return
	}

	if !user.IsActive {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "ACCOUNT_DISABLED", Message: "account has been disabled"})
		return
	}

	if !auth.CheckPassword(req.Password, user.PasswordHash) {
		writeError(w, http.StatusUnauthorized, model.ErrInvalidCredentials)
		return
	}

	accessToken, _ := auth.GenerateAccessToken(user.ID, user.IsAdmin)
	refreshToken, _ := auth.GenerateRefreshToken()

	database.StoreSession(ctx, refreshToken, user.ID.String(), "", 7*24*time.Hour)

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
		User: model.UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			DisplayName: user.DisplayName,
			AvatarURL:   user.AvatarURL,
			Bio:         user.Bio,
			IsAdmin:     user.IsAdmin,
			CreatedAt:   user.CreatedAt,
		},
	})
}

func handleOAuth(w http.ResponseWriter, r *http.Request) {
	var req model.OAuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Code == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "code is required"})
		return
	}

	switch req.Provider {
	case "google":
		handleGoogleOAuth(w, r, req.Code)
	case "apple":
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "NOT_IMPLEMENTED", Message: "Apple OAuth not yet implemented"})
	case "github":
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "NOT_IMPLEMENTED", Message: "GitHub OAuth not yet implemented"})
	default:
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_PROVIDER", Message: "unsupported provider: " + req.Provider})
	}
}

func handleGoogleOAuth(w http.ResponseWriter, r *http.Request, idToken string) {
	payload, err := verifyGoogleIDToken(idToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to verify Google token: " + err.Error()})
		return
	}

	if payload.EmailVerified != "true" {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "EMAIL_NOT_VERIFIED", Message: "Google email not verified"})
		return
	}

	email := payload.Email
	displayName := payload.Name
	if displayName == "" {
		displayName = strings.Split(email, "@")[0]
	}
	avatarURL := payload.Picture

	ctx := context.Background()

	// Check if user exists
	var userID string
	err = database.Pool.QueryRow(ctx,
		`SELECT id FROM users WHERE email = $1`, email,
	).Scan(&userID)

	if err != nil {
		// Create new user
		userID = uuid.New().String()
		now := time.Now()

		parsedID, err := model.ParseUUID(userID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
			return
		}

		_, err = database.Pool.Exec(ctx,
			`INSERT INTO users (id, email, display_name, avatar_url, oauth_provider, is_admin, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, 'google', false, $5, $5)`,
			parsedID, email, displayName, avatarURL, now,
		)
		if err != nil {
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create user"})
			return
		}

		// Insert default user_settings
		database.Pool.Exec(ctx,
			`INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
			parsedID,
		)
	}

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	// Generate tokens
	accessToken, _ := auth.GenerateAccessToken(parsedID, false)
	refreshToken, _ := auth.GenerateRefreshToken()
	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	// Fetch user for response
	var user model.User
	err = database.Pool.QueryRow(ctx,
		`SELECT id, email, display_name, avatar_url, bio, is_admin, created_at FROM users WHERE id = $1`,
		parsedID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.AvatarURL, &user.Bio, &user.IsAdmin, &user.CreatedAt)

	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to fetch user"})
		return
	}

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
		User: model.UserResponse{
			ID:          user.ID,
			Email:       ptr(email),
			DisplayName: user.DisplayName,
			AvatarURL:   user.AvatarURL,
			Bio:         user.Bio,
			IsAdmin:     user.IsAdmin,
			CreatedAt:   user.CreatedAt,
		},
	})
}

func ptr(s string) *string { return &s }

func verifyGoogleIDToken(idToken string) (*googleTokenPayload, error) {
	// Fetch Google's public keys if cache is empty or older than 1 hour
	if len(googleKeysCache) == 0 || time.Since(googleKeysCacheTime) > time.Hour {
		resp, err := http.Get("https://www.googleapis.com/oauth2/v3/certs")
		if err != nil {
			return nil, fmt.Errorf("fetch google keys: %w", err)
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return nil, fmt.Errorf("read google keys: %w", err)
		}

		var keysResp googleKeysResponse
		if err := json.Unmarshal(body, &keysResp); err != nil {
			return nil, fmt.Errorf("parse google keys: %w", err)
		}

		googleKeysCache = keysResp.Keys
		googleKeysCacheTime = time.Now()
	}

	// Decode JWT parts
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid token format")
	}

	// Parse header to find key ID
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, fmt.Errorf("decode header: %w", err)
	}

	var header struct {
		Kid string `json:"kid"`
		Alg string `json:"alg"`
	}
	if err := json.Unmarshal(headerJSON, &header); err != nil {
		return nil, fmt.Errorf("parse header: %w", err)
	}

	// Find matching key
	var matchedKey *googleKey
	for i := range googleKeysCache {
		if googleKeysCache[i].Kid == header.Kid {
			matchedKey = &googleKeysCache[i]
			break
		}
	}
	if matchedKey == nil {
		return nil, fmt.Errorf("key not found for kid: %s", header.Kid)
	}

	// Verify RSA signature
	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, fmt.Errorf("decode signature: %w", err)
	}

	// Decode RSA public key
	nBytes, err := base64.RawURLEncoding.DecodeString(matchedKey.N)
	if err != nil {
		return nil, fmt.Errorf("decode n: %w", err)
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(matchedKey.E)
	if err != nil {
		return nil, fmt.Errorf("decode e: %w", err)
	}

	pubKey := &rsa.PublicKey{
		N: new(big.Int).SetBytes(nBytes),
		E: int(new(big.Int).SetBytes(eBytes).Int64()),
	}

	// Verify signature
	message := parts[0] + "." + parts[1]
	hash := sha256.Sum256([]byte(message))
	if err := rsa.VerifyPKCS1v15(pubKey, crypto.SHA256, hash[:], signature); err != nil {
		return nil, fmt.Errorf("invalid signature: %w", err)
	}

	// Decode payload
	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decode payload: %w", err)
	}

	var payload googleTokenPayload
	if err := json.Unmarshal(payloadJSON, &payload); err != nil {
		return nil, fmt.Errorf("parse payload: %w", err)
	}

	// Verify issuer
	if payload.Iss != "https://accounts.google.com" && payload.Iss != "accounts.google.com" {
		return nil, fmt.Errorf("invalid issuer: %s", payload.Iss)
	}

	// Verify audience against configured client ID
	if googleClientID != "" && payload.Aud != googleClientID {
		return nil, fmt.Errorf("invalid audience: %s (expected %s)", payload.Aud, googleClientID)
	}

	// Verify token is not expired
	if payload.Exp > 0 && time.Now().Unix() > payload.Exp {
		return nil, fmt.Errorf("token expired at %d", payload.Exp)
	}

	return &payload, nil
}



func handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req model.RefreshRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.RefreshToken == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "refresh_token is required"})
		return
	}

	ctx := context.Background()

	sessionData, err := database.GetSession(ctx, req.RefreshToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, model.ErrInvalidToken)
		return
	}

	// sessionData is "userID:deviceID"
	userID := sessionData
	deviceID := ""

	// Delete old session
	database.DeleteSession(ctx, req.RefreshToken)

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	accessToken, _ := auth.GenerateAccessToken(parsedID, false)
	newRefreshToken, _ := auth.GenerateRefreshToken()

	database.StoreSession(ctx, newRefreshToken, userID, deviceID, 7*24*time.Hour)

	writeJSON(w, http.StatusOK, model.RefreshResponse{
		AccessToken:  accessToken,
		RefreshToken: newRefreshToken,
		ExpiresIn:    900,
	})
}

func handleRecover(w http.ResponseWriter, r *http.Request) {
	var req model.RecoverRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	// Normalize: remove dash if present
	code := req.Code
	if len(code) == 11 && code[5] == '-' {
		code = code[:5] + code[6:]
	}

	codeHash := auth.HashRecoveryCode(code)

	ctx := context.Background()

	// Rate limit by IP address to prevent brute force across all 10 codes
	clientIP, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		clientIP = r.RemoteAddr
	}
	attempts, err := database.CheckRecoveryRateLimit(ctx, clientIP)
	if err == nil && attempts > 5 {
		writeError(w, http.StatusTooManyRequests, model.ErrRecoveryLimit)
		return
	}

	var userID string
	var isUsed bool
	err = database.Pool.QueryRow(ctx,
		`SELECT user_id, is_used FROM recovery_codes WHERE code_hash = $1 FOR UPDATE`,
		codeHash,
	).Scan(&userID, &isUsed)

	if err != nil {
		writeError(w, http.StatusUnauthorized, model.ErrInvalidCredentials)
		return
	}

	if isUsed {
		writeError(w, http.StatusGone, model.ErrRecoveryCodeUsed)
		return
	}

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	// Mark code as used
	database.Pool.Exec(ctx,
		`UPDATE recovery_codes SET is_used = true, used_at = now() WHERE code_hash = $1`, codeHash)

	database.ResetRecoveryRateLimit(ctx, clientIP)

	accessToken, _ := auth.GenerateAccessToken(parsedID, false)
	refreshToken, _ := auth.GenerateRefreshToken()
	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
		User:         model.UserResponse{ID: parsedID},
	})
}

func handleRecoverEmail(w http.ResponseWriter, r *http.Request) {
	var req model.RecoverEmailRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email is required"})
		return
	}

	ctx := context.Background()

	// Always return success regardless of whether email exists (security)
	var userID string
	var displayName string
	err := database.Pool.QueryRow(ctx,
		`SELECT id, display_name FROM users WHERE email = $1`, req.Email,
	).Scan(&userID, &displayName)

	if err == nil {
		// Generate a recovery token
		recoveryToken, _ := auth.GenerateRefreshToken()
		database.StoreSession(ctx, "recover:"+recoveryToken, userID, "", 15*time.Minute)

		recoveryLink := fmt.Sprintf("https://d34etjxuah5cvp.cloudfront.net/auth/recover?token=%s", recoveryToken)

		// Try to send email via SES
		sesErr := sendSESEmail(ctx, req.Email, "CloseTalk Password Recovery",
			fmt.Sprintf("Hi %s,\n\nClick the link below to reset your password:\n%s\n\nThis link expires in 15 minutes.\n\nIf you didn't request this, ignore this email.", displayName, recoveryLink),
		)
		if sesErr != nil {
			log.Printf("[ses] failed to send recovery email to %s: %v", req.Email, sesErr)
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"message": "recovery email sent (if account exists)",
	})
}

func handleRecoverEmailComplete(w http.ResponseWriter, r *http.Request) {
	var req model.RecoverEmailCompleteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Token == "" || req.NewPassword == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "token and new_password are required"})
		return
	}

	if len(req.NewPassword) < 8 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "WEAK_PASSWORD", Message: "password must be at least 8 characters"})
		return
	}

	ctx := context.Background()

	// Look up recovery token
	sessionData, err := database.GetSession(ctx, "recover:"+req.Token)
	if err != nil {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "INVALID_TOKEN", Message: "invalid or expired recovery token"})
		return
	}

	// sessionData is "userID:deviceID"
	userID, _, _ := strings.Cut(sessionData, ":")
	if userID == "" {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "INVALID_TOKEN", Message: "invalid recovery token"})
		return
	}

	// Hash new password
	newHash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to process password"})
		return
	}

	// Update password
	_, err = database.Pool.Exec(ctx,
		`UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2`, newHash, userID,
	)
	if err != nil {
		log.Printf("[recover] password update error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to update password"})
		return
	}

	// Invalidate all sessions for this user
	database.Valkey.Del(ctx, "user_sessions:"+userID)

	// Delete the recovery token
	database.DeleteSession(ctx, "recover:"+req.Token)

	writeJSON(w, http.StatusOK, map[string]string{"message": "password updated successfully"})
}

var sesClient *sesv2.Client

func getSESClient() *sesv2.Client {
	if sesClient == nil {
		cfg, err := config.LoadDefaultConfig(context.Background())
		if err != nil {
			log.Printf("[ses] failed to load config: %v", err)
			return nil
		}
		sesClient = sesv2.NewFromConfig(cfg)
	}
	return sesClient
}

func sendSESEmail(ctx context.Context, to, subject, body string) error {
	from := os.Getenv("SES_FROM_EMAIL")
	if from == "" {
		from = "noreply@closetalk.app"
	}

	client := getSESClient()
	if client == nil {
		return fmt.Errorf("SES client not initialized")
	}

	_, err := client.SendEmail(ctx, &sesv2.SendEmailInput{
		FromEmailAddress: aws.String(from),
		Destination: &types.Destination{
			ToAddresses: []string{to},
		},
		Content: &types.EmailContent{
			Simple: &types.Message{
				Subject: &types.Content{
					Data: aws.String(subject),
				},
				Body: &types.Body{
					Text: &types.Content{
						Data: aws.String(body),
					},
				},
			},
		},
	})
	return err
}

func handleChangePassword(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.ChangePasswordRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()

	var currentHash string
	err := database.Pool.QueryRow(ctx,
		`SELECT password_hash FROM users WHERE id = $1`, userID,
	).Scan(&currentHash)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to verify password"})
		return
	}

	if !auth.CheckPassword(req.OldPassword, currentHash) {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "WRONG_PASSWORD", Message: "current password is incorrect"})
		return
	}

	newHash, _ := auth.HashPassword(req.NewPassword)
	database.Pool.Exec(ctx, `UPDATE users SET password_hash = $1, updated_at = now() WHERE id = $2`, newHash, userID)

	writeJSON(w, http.StatusOK, map[string]string{"message": "password updated"})
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	// Invalidate all sessions for this user
	database.Valkey.Del(context.Background(), "user_sessions:"+userID)
	writeJSON(w, http.StatusOK, map[string]string{"message": "logged out"})
}

func handleListDevices(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT id, device_name, device_type, platform, is_active, linked_at, last_active
		 FROM user_devices WHERE user_id = $1 ORDER BY last_active DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to list devices"})
		return
	}
	defer rows.Close()

	devices := []model.DeviceResponse{}
	for rows.Next() {
		var d model.DeviceResponse
		rows.Scan(&d.ID, &d.DeviceName, &d.DeviceType, &d.Platform, &d.IsActive, &d.LinkedAt, &d.LastActive)
		devices = append(devices, d)
	}

	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func handleLinkDevice(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.LinkDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	// Check device limit (max 5)
	ctx := context.Background()
	var deviceCount int
	database.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM user_devices WHERE user_id = $1 AND is_active = true`, userID,
	).Scan(&deviceCount)

	if deviceCount >= 5 {
		writeError(w, http.StatusConflict, &model.AppError{Code: "DEVICE_LIMIT", Message: "max 5 devices per user"})
		return
	}

	var deviceID string
	err := database.Pool.QueryRow(ctx,
		`INSERT INTO user_devices (user_id, device_name, device_type, platform, public_key)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id`,
		userID, req.DeviceName, req.DeviceType, req.Platform, req.DevicePubKey,
	).Scan(&deviceID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to link device"})
		return
	}

	deviceToken, _ := auth.GenerateRefreshToken()

	writeJSON(w, http.StatusCreated, model.LinkDeviceResponse{
		DeviceToken: deviceToken,
		DeviceID:    deviceID,
	})
}

func handleRevokeDevice(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.RevokeDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()
	result, err := database.Pool.Exec(ctx,
		`UPDATE user_devices SET is_active = false WHERE id = $1 AND user_id = $2`,
		req.DeviceID, userID,
	)
	if err != nil || result.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "DEVICE_NOT_FOUND", Message: "device not found"})
		return
	}

	// Remove from Valkey sessions
	database.RemoveUserSession(ctx, userID, req.DeviceID)

	writeJSON(w, http.StatusOK, map[string]string{"message": "device revoked"})
}
