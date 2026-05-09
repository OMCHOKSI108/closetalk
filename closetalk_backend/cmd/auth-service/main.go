package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/joho/godotenv"

	"github.com/OMCHOKSI108/closetalk/internal/auth"
	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/OMCHOKSI108/closetalk/internal/middleware"
	"github.com/OMCHOKSI108/closetalk/internal/model"
)

func main() {
	// Load .env if present
	_ = godotenv.Load()

	// Initialize auth
	auth.InitJWT()

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

	// Generate tokens
	accessToken, _ := auth.GenerateAccessToken(model.ParseUUID(userID), false)
	refreshToken, _ := auth.GenerateRefreshToken()

	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	writeJSON(w, http.StatusCreated, model.AuthResponse{
		AccessToken:   accessToken,
		RefreshToken:  refreshToken,
		ExpiresIn:     900,
		User:          model.UserResponse{ID: model.ParseUUID(userID), Email: &req.Email, DisplayName: req.DisplayName},
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

	// TODO: Verify OAuth code with provider (Google/Apple/GitHub)
	// For MVP, return a stub response indicating OAuth is not yet implemented
	writeJSON(w, http.StatusOK, map[string]string{
		"message":  "OAuth flow not fully implemented yet",
		"provider": req.Provider,
	})
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

	accessToken, _ := auth.GenerateAccessToken(model.ParseUUID(userID), false)
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

	// Check rate limit
	attempts, err := database.CheckRecoveryRateLimit(ctx, codeHash)
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

	// Mark code as used
	database.Pool.Exec(ctx,
		`UPDATE recovery_codes SET is_used = true, used_at = now() WHERE code_hash = $1`, codeHash)

	database.ResetRecoveryRateLimit(ctx, codeHash)

	accessToken, _ := auth.GenerateAccessToken(model.ParseUUID(userID), false)
	refreshToken, _ := auth.GenerateRefreshToken()
	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
		User:         model.UserResponse{ID: model.ParseUUID(userID)},
	})
}

func handleRecoverEmail(w http.ResponseWriter, r *http.Request) {
	// TODO: Send recovery email via AWS SES
	writeJSON(w, http.StatusOK, map[string]string{
		"message": "recovery email sent (if account exists)",
	})
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
