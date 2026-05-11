package main

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"math/big"
	"math/rand"
	"net"
	"net/http"
	"net/smtp"
	"net/url"
	"os"
	"os/signal"
	"regexp"
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
	"github.com/OMCHOKSI108/closetalk/internal/media"
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
type githubTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	Scope       string `json:"scope"`
}

type githubUser struct {
	ID        int    `json:"id"`
	Login     string `json:"login"`
	Email     string `json:"email"`
	Name      string `json:"name"`
	AvatarURL string `json:"avatar_url"`
}

type githubEmail struct {
	Email    string `json:"email"`
	Primary  bool   `json:"primary"`
	Verified bool   `json:"verified"`
}

var (
	googleKeysCache     []googleKey
	googleKeysCacheTime time.Time
	googleClientID      string
	githubClientID      string
	githubClientSecret  string
	appleClientID       string
)

func main() {
	// Load .env if present
	_ = godotenv.Load()

	// Initialize auth
	auth.InitJWT()

	googleClientID = os.Getenv("GOOGLE_CLIENT_ID")
	githubClientID = os.Getenv("GITHUB_CLIENT_ID")
	githubClientSecret = os.Getenv("GITHUB_CLIENT_SECRET")
	appleClientID = os.Getenv("APPLE_CLIENT_ID")

	// Connect databases
	if err := database.ConnectNeon(); err != nil {
		log.Fatalf("[fatal] database: %v", err)
	}
	defer database.CloseNeon()

	media.Init()

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
				"health":        "/health",
				"auth_register": "/auth/register",
				"auth_login":    "/auth/login",
				"auth_refresh":  "/auth/refresh",
				"auth_recover":  "/auth/recover",
				"messages":      "/messages/{chatId}",
				"bookmarks":     "/bookmarks",
				"websocket":     "/ws",
			},
			"documentation": "https://github.com/OMCHOKSI108/closetalk",
		})
	})

	// Health check
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"status": "ok", "service": "auth-service"})
	})

	// Auth routes (no auth required, IP rate limited)
	r.Route("/auth", func(r chi.Router) {
		r.Use(middleware.IPRateLimit)
		r.Post("/register/init", handleRegisterInit)
		r.Post("/register/verify", handleRegisterVerify)
		r.Post("/register", handleRegister)
		r.Post("/login", handleLogin)
		r.Post("/oauth", handleOAuth)
		r.Post("/refresh", handleRefresh)
		r.Post("/recover", handleRecover)
		r.Get("/recover", handleRecoverPage)
		r.Post("/recover/email", handleRecoverEmail)
		r.Post("/recover/email/complete", handleRecoverEmailComplete)
	})

	// Auth routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Put("/auth/password", handleChangePassword)
		r.Post("/auth/logout", handleLogout)
		r.Put("/auth/profile", handleUpdateProfile)
	})

	// Device routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Get("/devices", handleListDevices)
		r.Post("/devices/link", handleLinkDevice)
		r.Post("/devices/revoke", handleRevokeDevice)
		r.Post("/devices/notification", handleRegisterNotificationToken)
	})

	// Group routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Get("/groups", handleListGroups)
		r.Post("/groups", handleCreateGroup)
		r.Get("/groups/discover", handleDiscoverGroups)
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

	// User search & profile (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Get("/users/search", handleUserSearch)
		r.Get("/users/profile/{id}", handleUserProfile)
		r.Put("/users/avatar", handleUploadAvatar)
	})

	// Serve uploaded avatars
	uploadDir := os.Getenv("UPLOAD_DIR")
	if uploadDir == "" {
		uploadDir = "./uploads"
	}
	r.Get("/uploads/*", func(w http.ResponseWriter, r *http.Request) {
		fs := http.StripPrefix("/uploads/", http.FileServer(http.Dir(uploadDir)))
		fs.ServeHTTP(w, r)
	})

	// Contacts / Social (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/contacts", handleSendContactRequest)
		r.Post("/contacts/accept", handleAcceptContactRequest)
		r.Post("/contacts/reject", handleRejectContactRequest)
		r.Get("/contacts", handleListContacts)
		r.Post("/users/block", handleBlockUser)
		r.Post("/users/report", handleReportUser)
		r.Post("/conversations/direct", handleCreateDirectConversation)
	})

	// Story routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/stories", handleCreateStory)
		r.Get("/stories", handleListStories)
		r.Delete("/stories/{id}", handleDeleteStory)
	})

	// E2EE key routes (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/e2ee/keys", handleRegisterE2EEKey)
		r.Get("/e2ee/keys/{userId}", handleGetE2EEKey)
	})

	// Account management (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Delete("/auth/account", handleDeleteAccount)
	})

	// Privacy settings (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Get("/users/settings", handleGetPrivacySettings)
		r.Put("/users/settings", handleUpdatePrivacySettings)
	})

	// Contact discovery (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/contacts/discover", handleContactDiscovery)
		r.Post("/contacts/hashes", handleRegisterPhoneHashes)
	})

	// Story extensions (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/stories/{id}/view", handleViewStory)
		r.Get("/stories/{id}/views", handleGetStoryViews)
		r.Post("/stories/{id}/reply", handleReplyToStory)
		r.Post("/stories/mute/{userId}", handleMuteStoryUser)
		r.Post("/stories/unmute/{userId}", handleUnmuteStoryUser)
	})

	// Broadcasts (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/broadcasts", handleCreateBroadcast)
		r.Get("/broadcasts", handleListBroadcasts)
		r.Post("/broadcasts/{id}/send", handleSendBroadcast)
	})

	// Channels (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/channels", handleCreateChannel)
		r.Get("/channels", handleListChannels)
		r.Get("/channels/discover", handleDiscoverChannels)
		r.Post("/channels/{id}/subscribe", handleSubscribeChannel)
		r.Post("/channels/{id}/unsubscribe", handleUnsubscribeChannel)
		r.Get("/channels/{id}/subscribers", handleListChannelSubscribers)
		r.Post("/channels/{id}/messages", handleSendChannelMessage)
	})

	// Scheduled messages (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/messages/schedule", handleScheduleMessage)
		r.Get("/messages/scheduled", handleListScheduledMessages)
		r.Delete("/messages/scheduled/{id}", handleCancelScheduledMessage)
	})

	// Polls (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/polls", handleCreatePoll)
		r.Post("/polls/{id}/vote", handleVotePoll)
		r.Get("/polls/{id}/results", handleGetPollResults)
	})

	// Admin routes (JWT + admin required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(requireAdmin)
		r.Use(middleware.UserRateLimit)
		r.Get("/admin/users", handleAdminListUsers)
		r.Put("/admin/users/{userId}/disable", handleAdminDisableUser)
		r.Get("/admin/analytics", handleAdminGetAnalytics)
		r.Get("/admin/flags", handleAdminListFlags)
		r.Put("/admin/flags/{id}", handleAdminUpdateFlag)
		r.Get("/admin/audit-log", handleAdminAuditLog)
	})

	// Webhooks (JWT required)
	r.Group(func(r chi.Router) {
		r.Use(middleware.RequireAuth)
		r.Use(middleware.UserRateLimit)
		r.Post("/webhooks", handleCreateWebhook)
		r.Get("/webhooks", handleListWebhooks)
		r.Delete("/webhooks/{id}", handleDeleteWebhook)
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

// --- Middleware --------------------------------------------------------------

func requireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		isAdmin, ok := r.Context().Value(middleware.IsAdminKey).(bool)
		if !ok || !isAdmin {
			writeError(w, http.StatusForbidden, &model.AppError{Code: "FORBIDDEN", Message: "admin access required"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

// --- Handlers ----------------------------------------------------------------

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

func generateOTP() string {
	return fmt.Sprintf("%06d", rand.Intn(1000000))
}

func handleRegisterInit(w http.ResponseWriter, r *http.Request) {
	var req model.RegisterInitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" || req.Password == "" || req.DisplayName == "" || req.Username == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email, password, display_name, and username are required"})
		return
	}

	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "WEAK_PASSWORD", Message: "password must be at least 8 characters"})
		return
	}

	if err := validateUsername(req.Username); err != nil {
		writeError(w, http.StatusBadRequest, err)
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
	database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)", req.Username).Scan(&exists)
	if exists {
		writeError(w, http.StatusConflict, &model.AppError{Code: "USERNAME_TAKEN", Message: "username is already taken"})
		return
	}

	// Check cooldown (prevent OTP spam)
	cooldownKey := "otp_cooldown:" + req.Email
	if cooldown, err := database.Valkey.Get(ctx, cooldownKey).Int(); err == nil {
		remaining := 60 - int(time.Now().Unix()) + cooldown
		if remaining > 0 {
			writeJSON(w, http.StatusTooManyRequests, model.RegisterInitResponse{
				Message:  "please wait before requesting a new OTP",
				Email:    req.Email,
				Cooldown: remaining,
			})
			return
		}
	}

	// Generate OTP
	otp := generateOTP()
	otpKey := "otp_register:" + req.Email

	// Store pending registration data in Valkey (10 min TTL)
	pendingData, _ := json.Marshal(map[string]string{
		"email":        req.Email,
		"password":     req.Password,
		"display_name": req.DisplayName,
		"username":     req.Username,
		"otp":          otp,
	})
	if err := database.Valkey.Set(ctx, otpKey, pendingData, 10*time.Minute).Err(); err != nil {
		log.Printf("[register] valkey set error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to initiate registration"})
		return
	}

	// Set cooldown (60s)
	database.Valkey.Set(ctx, cooldownKey, time.Now().Unix(), 60*time.Second)

	// Send OTP email
	go func() {
		subject := "Your CloseTalk verification code"
		body := fmt.Sprintf(`Your CloseTalk verification code is: %s

This code expires in 10 minutes.

If you did not request this, please ignore this email.`, otp)
		if err := sendEmail(context.Background(), req.Email, subject, body); err != nil {
			log.Printf("[register] ses error: %v", err)
		}
	}()

	log.Printf("[register] OTP for %s: %s", req.Email, otp)

	writeJSON(w, http.StatusOK, model.RegisterInitResponse{
		Message:  "verification code sent to email",
		Email:    req.Email,
		Cooldown: 60,
	})
}

func handleRegisterVerify(w http.ResponseWriter, r *http.Request) {
	var req model.RegisterVerifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" || req.OTP == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email and otp are required"})
		return
	}

	ctx := context.Background()
	otpKey := "otp_register:" + req.Email

	// Get pending data from Valkey
	pendingJSON, err := database.Valkey.Get(ctx, otpKey).Bytes()
	if err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "OTP_EXPIRED", Message: "verification code expired or invalid"})
		return
	}

	var pending struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		Username    string `json:"username"`
		OTP         string `json:"otp"`
	}
	json.Unmarshal(pendingJSON, &pending)

	if pending.OTP != req.OTP {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_OTP", Message: "invalid verification code"})
		return
	}

	// Double-check user doesn't exist
	var exists bool
	database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)", req.Email).Scan(&exists)
	if exists {
		database.Valkey.Del(ctx, otpKey)
		writeError(w, http.StatusConflict, model.ErrEmailTaken)
		return
	}

	// Hash password & create user
	hash, err := auth.HashPassword(pending.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to process password"})
		return
	}

	var userID string
	err = database.Pool.QueryRow(ctx,
		`INSERT INTO users (email, display_name, username, password_hash)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		pending.Email, pending.DisplayName, pending.Username, hash,
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

	// Clean up OTP data
	database.Valkey.Del(ctx, otpKey)
	database.Valkey.Del(ctx, "otp_cooldown:"+req.Email)

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
		ExpiresIn:     3600,
		User:          model.UserResponse{ID: parsedID, Email: &pending.Email, Username: pending.Username, DisplayName: pending.DisplayName},
		RecoveryCodes: codes,
	})
}

func validateUsername(username string) *model.AppError {
	if len(username) < 3 || len(username) > 30 {
		return &model.AppError{Code: "INVALID_USERNAME", Message: "username must be between 3 and 30 characters"}
	}
	if !regexp.MustCompile(`^[a-zA-Z0-9_]+$`).MatchString(username) {
		return &model.AppError{Code: "INVALID_USERNAME", Message: "username can only contain letters, numbers, and underscores"}
	}
	return nil
}

func handleRegister(w http.ResponseWriter, r *http.Request) {
	var req model.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Email == "" || req.Password == "" || req.DisplayName == "" || req.Username == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "email, password, display_name, and username are required"})
		return
	}

	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "WEAK_PASSWORD", Message: "password must be at least 8 characters"})
		return
	}

	if len(req.Username) < 3 || len(req.Username) > 30 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_USERNAME", Message: "username must be between 3 and 30 characters"})
		return
	}

	if !regexp.MustCompile(`^[a-zA-Z0-9_]+$`).MatchString(req.Username) {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_USERNAME", Message: "username can only contain letters, numbers, and underscores"})
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
	database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)", req.Username).Scan(&exists)
	if exists {
		writeError(w, http.StatusConflict, &model.AppError{Code: "USERNAME_TAKEN", Message: "username is already taken"})
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
		`INSERT INTO users (email, display_name, username, password_hash)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id`,
		req.Email, req.DisplayName, req.Username, hash,
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
		ExpiresIn:     3600,
		User:          model.UserResponse{ID: parsedID, Email: &req.Email, Username: req.Username, DisplayName: req.DisplayName},
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
		`SELECT id, email, display_name, username, avatar_url, bio, password_hash, is_admin, is_active, created_at
		 FROM users WHERE email = $1 AND deleted_at IS NULL`,
		req.Email,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.Username, &user.AvatarURL, &user.Bio,
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
		ExpiresIn:    3600,
		User: model.UserResponse{
			ID:          user.ID,
			Email:       user.Email,
			Username:    user.Username,
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
		handleAppleOAuth(w, r, req.Code)
	case "github":
		handleGitHubOAuth(w, r, req.Code)
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

		username := generateUsername(displayName)
		_, err = database.Pool.Exec(ctx,
			`INSERT INTO users (id, email, display_name, username, avatar_url, oauth_provider, is_admin, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, 'google', false, $6, $6)`,
			parsedID, email, displayName, username, avatarURL, now,
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
		`SELECT id, email, display_name, username, avatar_url, bio, is_admin, created_at FROM users WHERE id = $1`,
		parsedID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.Username, &user.AvatarURL, &user.Bio, &user.IsAdmin, &user.CreatedAt)

	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to fetch user"})
		return
	}

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    3600,
		User: model.UserResponse{
			ID:          user.ID,
			Email:       ptr(email),
			Username:    user.Username,
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

func handleGitHubOAuth(w http.ResponseWriter, r *http.Request, code string) {
	if githubClientID == "" || githubClientSecret == "" {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "CONFIG_ERROR", Message: "GitHub OAuth not configured"})
		return
	}

	// Exchange authorization code for access token
	tokenResp, err := http.PostForm("https://github.com/login/oauth/access_token",
		url.Values{
			"client_id":     {githubClientID},
			"client_secret": {githubClientSecret},
			"code":          {code},
		},
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to exchange code"})
		return
	}
	defer tokenResp.Body.Close()

	body, err := io.ReadAll(tokenResp.Body)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to read token response"})
		return
	}

	// GitHub returns form-encoded by default
	values, err := url.ParseQuery(string(body))
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to parse token response"})
		return
	}

	accessToken := values.Get("access_token")
	if accessToken == "" {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to get access token"})
		return
	}

	// Fetch user info
	req, _ := http.NewRequest("GET", "https://api.github.com/user", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")

	userResp, err := http.DefaultClient.Do(req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to fetch user"})
		return
	}
	defer userResp.Body.Close()

	var ghUser githubUser
	if err := json.NewDecoder(userResp.Body).Decode(&ghUser); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to parse user"})
		return
	}

	// GitHub doesn't always return email in /user -- fetch emails if needed
	email := ghUser.Email
	if email == "" {
		emailReq, _ := http.NewRequest("GET", "https://api.github.com/user/emails", nil)
		emailReq.Header.Set("Authorization", "Bearer "+accessToken)
		emailReq.Header.Set("Accept", "application/json")

		emailResp, err := http.DefaultClient.Do(emailReq)
		if err == nil {
			defer emailResp.Body.Close()
			var emails []githubEmail
			if json.NewDecoder(emailResp.Body).Decode(&emails) == nil {
				for _, e := range emails {
					if e.Primary && e.Verified {
						email = e.Email
						break
					}
				}
			}
		}
	}

	if email == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "OAUTH_FAILED", Message: "no verified email from GitHub"})
		return
	}

	displayName := ghUser.Name
	if displayName == "" {
		displayName = ghUser.Login
	}

	ctx := context.Background()

	// Find or create user
	var userID string
	err = database.Pool.QueryRow(ctx,
		`SELECT id FROM users WHERE email = $1`, email,
	).Scan(&userID)

	if err != nil {
		username := generateUsername(displayName)
		userID = uuid.New().String()
		now := time.Now()
		_, err = database.Pool.Exec(ctx,
			`INSERT INTO users (id, email, display_name, username, avatar_url, oauth_provider, is_admin, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, $5, 'github', false, $6, $6)`,
			model.ParseUUIDOrNil(userID), email, displayName, username, ghUser.AvatarURL, now,
		)
		if err != nil {
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create user"})
			return
		}
		database.Pool.Exec(ctx,
			`INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
			model.ParseUUIDOrNil(userID),
		)
	}

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	accessTokenJWT, _ := auth.GenerateAccessToken(parsedID, false)
	refreshToken, _ := auth.GenerateRefreshToken()
	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	var user model.User
	err = database.Pool.QueryRow(ctx,
		`SELECT id, email, display_name, username, avatar_url, bio, is_admin, created_at FROM users WHERE id = $1`,
		userID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.Username, &user.AvatarURL, &user.Bio, &user.IsAdmin, &user.CreatedAt)
	if err != nil {
		user = model.User{ID: parsedID, Username: displayName, DisplayName: displayName, CreatedAt: time.Now()}
	}

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessTokenJWT,
		RefreshToken: refreshToken,
		ExpiresIn:    3600,
		User: model.UserResponse{
			ID:          user.ID,
			Email:       ptr(email),
			Username:    user.Username,
			DisplayName: user.DisplayName,
			AvatarURL:   user.AvatarURL,
			Bio:         user.Bio,
			IsAdmin:     user.IsAdmin,
			CreatedAt:   user.CreatedAt,
		},
	})
}

func handleAppleOAuth(w http.ResponseWriter, r *http.Request, idToken string) {
	if appleClientID == "" {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "CONFIG_ERROR", Message: "Apple OAuth not configured"})
		return
	}

	payload, err := verifyAppleIDToken(idToken)
	if err != nil {
		writeError(w, http.StatusUnauthorized, &model.AppError{Code: "OAUTH_FAILED", Message: "failed to verify Apple token: " + err.Error()})
		return
	}

	email := payload.Email
	if email == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "OAUTH_FAILED", Message: "no email from Apple (user may need to re-auth with email scope)"})
		return
	}

	displayName := payload.Name
	if displayName == "" {
		displayName = strings.Split(email, "@")[0]
	}

	ctx := context.Background()

	var userID string
	err = database.Pool.QueryRow(ctx,
		`SELECT id FROM users WHERE email = $1`, email,
	).Scan(&userID)

	if err != nil {
		username := generateUsername(displayName)
		userID = uuid.New().String()
		now := time.Now()
		_, err = database.Pool.Exec(ctx,
			`INSERT INTO users (id, email, display_name, username, oauth_provider, is_admin, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, 'apple', false, $5, $5)`,
			model.ParseUUIDOrNil(userID), email, displayName, username, now,
		)
		if err != nil {
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create user"})
			return
		}
		database.Pool.Exec(ctx,
			`INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
			model.ParseUUIDOrNil(userID),
		)
	}

	parsedID, err := model.ParseUUID(userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "invalid user identity"})
		return
	}

	accessTokenJWT, _ := auth.GenerateAccessToken(parsedID, false)
	refreshToken, _ := auth.GenerateRefreshToken()
	database.StoreSession(ctx, refreshToken, userID, "", 7*24*time.Hour)

	var user model.User
	err = database.Pool.QueryRow(ctx,
		`SELECT id, email, display_name, avatar_url, bio, is_admin, created_at FROM users WHERE id = $1`,
		userID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.AvatarURL, &user.Bio, &user.IsAdmin, &user.CreatedAt)
	if err != nil {
		user = model.User{ID: parsedID, DisplayName: displayName, CreatedAt: time.Now()}
	}

	writeJSON(w, http.StatusOK, model.AuthResponse{
		AccessToken:  accessTokenJWT,
		RefreshToken: refreshToken,
		ExpiresIn:    3600,
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

type appleTokenPayload struct {
	Iss           string `json:"iss"`
	Sub           string `json:"sub"`
	Aud           string `json:"aud"`
	Iat           int64  `json:"iat"`
	Exp           int64  `json:"exp"`
	Email         string `json:"email"`
	EmailVerified string `json:"email_verified"`
	Name          string `json:"name"`
}

type appleKeysResponse struct {
	Keys []appleKey `json:"keys"`
}

type appleKey struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

var (
	appleKeysCache     []appleKey
	appleKeysCacheTime time.Time
)

func verifyAppleIDToken(idToken string) (*appleTokenPayload, error) {
	if appleKeysCache == nil || time.Since(appleKeysCacheTime) > time.Hour {
		resp, err := http.Get("https://appleid.apple.com/auth/keys")
		if err != nil {
			return nil, fmt.Errorf("fetch apple keys: %w", err)
		}
		defer resp.Body.Close()

		var keysResp appleKeysResponse
		if err := json.NewDecoder(resp.Body).Decode(&keysResp); err != nil {
			return nil, fmt.Errorf("parse apple keys: %w", err)
		}
		appleKeysCache = keysResp.Keys
		appleKeysCacheTime = time.Now()
	}

	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return nil, fmt.Errorf("invalid token format")
	}

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

	var matchedKey *appleKey
	for i := range appleKeysCache {
		if appleKeysCache[i].Kid == header.Kid {
			matchedKey = &appleKeysCache[i]
			break
		}
	}

	if matchedKey == nil {
		return nil, fmt.Errorf("key not found for kid: %s", header.Kid)
	}

	signature, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, fmt.Errorf("decode signature: %w", err)
	}

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

	message := parts[0] + "." + parts[1]
	hash := sha256.Sum256([]byte(message))
	if err := rsa.VerifyPKCS1v15(pubKey, crypto.SHA256, hash[:], signature); err != nil {
		return nil, fmt.Errorf("invalid signature: %w", err)
	}

	payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, fmt.Errorf("decode payload: %w", err)
	}

	var payload appleTokenPayload
	if err := json.Unmarshal(payloadJSON, &payload); err != nil {
		return nil, fmt.Errorf("parse payload: %w", err)
	}

	if payload.Iss != "https://appleid.apple.com" {
		return nil, fmt.Errorf("invalid issuer: %s", payload.Iss)
	}

	if payload.Aud != appleClientID {
		return nil, fmt.Errorf("invalid audience: %s", payload.Aud)
	}

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
		ExpiresIn:    3600,
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
		ExpiresIn:    3600,
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
		sesErr := sendEmail(ctx, req.Email, "CloseTalk Password Recovery",
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

var recoverPageTpl = template.Must(template.New("recover").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Reset your CloseTalk password</title>
<style>
  *,*::before,*::after{box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;margin:0;padding:24px;background:#f5f3ef;color:#2a1d12;display:flex;min-height:100vh;align-items:center;justify-content:center}
  .card{background:#fff;border-radius:12px;box-shadow:0 4px 24px rgba(0,0,0,.08);padding:32px;width:100%;max-width:420px}
  h1{margin:0 0 8px;font-size:22px}
  p{margin:0 0 20px;color:#6b5a48;font-size:14px}
  label{display:block;font-size:13px;margin:12px 0 4px;color:#3a2a1c}
  input{width:100%;padding:10px 12px;border:1px solid #ddd;border-radius:8px;font-size:15px}
  button{width:100%;margin-top:20px;padding:12px;border:0;border-radius:8px;background:#5a3a24;color:#fff;font-size:15px;font-weight:600;cursor:pointer}
  button:disabled{opacity:.6;cursor:not-allowed}
  .msg{margin-top:16px;font-size:14px;padding:10px 12px;border-radius:8px;display:none}
  .msg.error{display:block;background:#fde8e8;color:#9b1c1c}
  .msg.ok{display:block;background:#e6f4ea;color:#1e6b3a}
</style>
</head>
<body>
  <form class="card" id="f">
    <h1>Reset your password</h1>
    <p>Choose a new password for your CloseTalk account.</p>
    <label for="p1">New password</label>
    <input id="p1" type="password" minlength="8" required autocomplete="new-password">
    <label for="p2">Confirm password</label>
    <input id="p2" type="password" minlength="8" required autocomplete="new-password">
    <button id="b" type="submit">Update password</button>
    <div id="m" class="msg"></div>
  </form>
<script>
(function(){
  var token = {{.Token}};
  var f = document.getElementById('f');
  var b = document.getElementById('b');
  var m = document.getElementById('m');
  function show(cls, text){ m.className = 'msg ' + cls; m.textContent = text; }
  if(!token){ show('error', 'Missing or invalid recovery link.'); b.disabled = true; return; }
  f.addEventListener('submit', function(e){
    e.preventDefault();
    var p1 = document.getElementById('p1').value;
    var p2 = document.getElementById('p2').value;
    if(p1 !== p2){ show('error', 'Passwords do not match.'); return; }
    if(p1.length < 8){ show('error', 'Password must be at least 8 characters.'); return; }
    b.disabled = true; show('', 'Updating...');
    fetch('/auth/recover/email/complete', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: token, new_password: p1})
    }).then(function(r){ return r.json().then(function(j){ return {ok: r.ok, j: j}; }); })
      .then(function(res){
        if(res.ok){
          show('ok', 'Password updated. You can close this page and sign in.');
          b.style.display = 'none';
        } else {
          var err = (res.j && (res.j.error || (res.j.message))) || 'Could not reset password.';
          show('error', err);
          b.disabled = false;
        }
      })
      .catch(function(){ show('error', 'Network error. Please try again.'); b.disabled = false; });
  });
})();
</script>
</body>
</html>`))

func handleRecoverPage(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	if err := recoverPageTpl.Execute(w, map[string]string{"Token": token}); err != nil {
		log.Printf("[recover] template error: %v", err)
	}
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

func sendEmail(ctx context.Context, to, subject, body string) error {
	// Try SMTP first (good for local dev with Gmail/SendGrid)
	if host := os.Getenv("SMTP_HOST"); host != "" {
		port := os.Getenv("SMTP_PORT")
		if port == "" {
			port = "587"
		}
		user := os.Getenv("SMTP_USER")
		pass := os.Getenv("SMTP_PASS")
		from := os.Getenv("SMTP_FROM")
		if from == "" {
			from = user
		}
		if user != "" && pass != "" {
			msg := fmt.Sprintf("From: %s\r\nTo: %s\r\nSubject: %s\r\n\r\n%s", from, to, subject, body)
			addr := fmt.Sprintf("%s:%s", host, port)
			auth := smtp.PlainAuth("", user, pass, host)
			if err := smtp.SendMail(addr, auth, from, []string{to}, []byte(msg)); err != nil {
				log.Printf("[email] SMTP error: %v", err)
				return err
			}
			return nil
		}
	}

	// Fall back to SES
	from := os.Getenv("SES_FROM_EMAIL")
	if from == "" {
		from = "noreply@closetalk.app"
	}

	client := getSESClient()
	if client == nil {
		return fmt.Errorf("no email provider configured (set SMTP_HOST+SMTP_USER+SMTP_PASS or configure SES)")
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

func generateUsername(base string) string {
	username := strings.ToLower(strings.ReplaceAll(base, " ", "_"))
	username = regexp.MustCompile(`[^a-zA-Z0-9_]`).ReplaceAllString(username, "")
	if len(username) < 3 {
		username = "user"
	}
	if len(username) > 25 {
		username = username[:25]
	}

	// Check uniqueness and append random suffix if needed
	ctx := context.Background()
	var exists bool
	database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)", username).Scan(&exists)
	if exists {
		suffix := fmt.Sprintf("_%d", time.Now().Unix()%100000)
		if len(username)+len(suffix) > 30 {
			username = username[:30-len(suffix)] + suffix
		} else {
			username = username + suffix
		}
	}
	return username
}

func handleUpdateProfile(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.UpdateProfileRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	ctx := context.Background()
	now := time.Now()

	// Fetch current user
	var currentUsername string
	var currentChanges int
	var changedAt *time.Time
	err := database.Pool.QueryRow(ctx,
		`SELECT username, username_changes, username_changed_at FROM users WHERE id = $1`,
		userID,
	).Scan(&currentUsername, &currentChanges, &changedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to fetch user"})
		return
	}

	// Build update
	updates := []string{}
	args := []any{}
	argIdx := 1

	if req.Username != nil && *req.Username != currentUsername {
		newUsername := strings.TrimSpace(*req.Username)
		if len(newUsername) < 3 || len(newUsername) > 30 {
			writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_USERNAME", Message: "username must be between 3 and 30 characters"})
			return
		}
		if !regexp.MustCompile(`^[a-zA-Z0-9_]+$`).MatchString(newUsername) {
			writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_USERNAME", Message: "username can only contain letters, numbers, and underscores"})
			return
		}

		// Check 14-day cooldown
		if changedAt != nil && time.Since(*changedAt) < 14*24*time.Hour {
			nextChange := changedAt.Add(14 * 24 * time.Hour)
			writeError(w, http.StatusTooManyRequests, &model.AppError{
				Code:    "USERNAME_COOLDOWN",
				Message: fmt.Sprintf("you can change your username again after %s", nextChange.Format(time.RFC3339)),
			})
			return
		}

		// Check 2-change limit
		if currentChanges >= 2 {
			writeError(w, http.StatusForbidden, &model.AppError{Code: "USERNAME_LIMIT", Message: "maximum 2 username changes allowed"})
			return
		}

		// Check if username is taken
		var exists bool
		database.Pool.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND id != $2)", newUsername, userID).Scan(&exists)
		if exists {
			writeError(w, http.StatusConflict, &model.AppError{Code: "USERNAME_TAKEN", Message: "username is already taken"})
			return
		}

		updates = append(updates, fmt.Sprintf("username = $%d", argIdx))
		args = append(args, newUsername)
		argIdx++
		updates = append(updates, fmt.Sprintf("username_changes = $%d", argIdx))
		args = append(args, currentChanges+1)
		argIdx++
		updates = append(updates, fmt.Sprintf("username_changed_at = $%d", argIdx))
		args = append(args, now)
		argIdx++
	}

	if req.DisplayName != nil {
		updates = append(updates, fmt.Sprintf("display_name = $%d", argIdx))
		args = append(args, *req.DisplayName)
		argIdx++
	}

	if req.Bio != nil {
		updates = append(updates, fmt.Sprintf("bio = $%d", argIdx))
		args = append(args, *req.Bio)
		argIdx++
	}

	if req.AvatarURL != nil {
		updates = append(updates, fmt.Sprintf("avatar_url = $%d", argIdx))
		args = append(args, *req.AvatarURL)
		argIdx++
	}

	if len(updates) == 0 {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "no fields to update"})
		return
	}

	updates = append(updates, fmt.Sprintf("updated_at = $%d", argIdx))
	args = append(args, now)
	argIdx++

	args = append(args, userID)
	query := fmt.Sprintf("UPDATE users SET %s WHERE id = $%d", strings.Join(updates, ", "), argIdx)

	_, err = database.Pool.Exec(ctx, query, args...)
	if err != nil {
		log.Printf("[profile] update error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to update profile"})
		return
	}

	// Fetch updated user
	var user model.User
	err = database.Pool.QueryRow(ctx,
		`SELECT id, email, display_name, username, avatar_url, bio, is_admin, username_changes, username_changed_at, created_at
		 FROM users WHERE id = $1`, userID,
	).Scan(&user.ID, &user.Email, &user.DisplayName, &user.Username, &user.AvatarURL, &user.Bio,
		&user.IsAdmin, &user.UsernameChanges, &user.UsernameChangedAt, &user.CreatedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to fetch updated user"})
		return
	}

	remainingChanges := 2 - user.UsernameChanges
	if remainingChanges < 0 {
		remainingChanges = 0
	}

	var nextChangeAt *time.Time
	if user.UsernameChangedAt != nil && remainingChanges > 0 {
		nextAllowed := user.UsernameChangedAt.Add(14 * 24 * time.Hour)
		if time.Now().Before(nextAllowed) {
			nextChangeAt = &nextAllowed
		}
	}

	writeJSON(w, http.StatusOK, model.UpdateProfileResponse{
		User: model.UserResponse{
			ID:                user.ID,
			Email:             user.Email,
			Username:          user.Username,
			DisplayName:       user.DisplayName,
			AvatarURL:         user.AvatarURL,
			Bio:               user.Bio,
			IsAdmin:           user.IsAdmin,
			UsernameChanges:   user.UsernameChanges,
			UsernameChangedAt: user.UsernameChangedAt,
			CreatedAt:         user.CreatedAt,
		},
		RemainingChanges: remainingChanges,
		NextChangeAt:     nextChangeAt,
	})
}

func handleUserSearch(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if query == "" {
		writeJSON(w, http.StatusOK, model.UserSearchResponse{Users: []model.UserResponse{}})
		return
	}

	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT id, email, display_name, username, avatar_url, bio, is_admin, created_at
		 FROM users
		 WHERE (username ILIKE $1 OR display_name ILIKE $1)
		 AND deleted_at IS NULL
		 LIMIT 20`,
		"%"+query+"%",
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "search failed"})
		return
	}
	defer rows.Close()

	users := []model.UserResponse{}
	for rows.Next() {
		var u model.UserResponse
		rows.Scan(&u.ID, &u.Email, &u.DisplayName, &u.Username, &u.AvatarURL, &u.Bio, &u.IsAdmin, &u.CreatedAt)
		users = append(users, u)
	}

	writeJSON(w, http.StatusOK, model.UserSearchResponse{Users: users})
}

func handleRegisterNotificationToken(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.RegisterNotificationTokenRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}

	if req.Token == "" || req.Platform == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "token and platform are required"})
		return
	}

	ctx := context.Background()
	if req.DeviceID != "" {
		// Update existing device's push token
		_, err := database.Pool.Exec(ctx,
			`UPDATE user_devices SET push_token = $1, last_active = now()
			 WHERE id = $2 AND user_id = $3`,
			req.Token, req.DeviceID, userID,
		)
		if err != nil {
			log.Printf("[notification] update device token error: %v", err)
		}
	} else {
		// Store as a standalone notification token
		_, err := database.Pool.Exec(ctx,
			`INSERT INTO notification_tokens (user_id, token, platform)
			 VALUES ($1, $2, $3)
			 ON CONFLICT (token) DO UPDATE SET platform = $3, updated_at = now()`,
			userID, req.Token, req.Platform,
		)
		if err != nil {
			log.Printf("[notification] insert token error: %v", err)
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to register token"})
			return
		}
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "notification token registered"})
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

// --- Contact Handlers --------------------------------------------------------

func handleSendContactRequest(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.ContactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ContactID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "contact_id is required"})
		return
	}
	if req.ContactID == userID {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "cannot add yourself"})
		return
	}

	ctx := context.Background()
	// Check not blocked
	var blocked bool
	database.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM contacts WHERE user_id = $1 AND contact_id = $2 AND status = 'blocked')`,
		req.ContactID, userID,
	).Scan(&blocked)
	if blocked {
		writeError(w, http.StatusForbidden, &model.AppError{Code: "BLOCKED", Message: "you cannot add this user"})
		return
	}

	// Upsert contact: if row exists (pending/sent/accepted), update; else insert
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO contacts (user_id, contact_id, status)
		 VALUES ($1, $2, 'sent')
		 ON CONFLICT (user_id, contact_id)
		 DO UPDATE SET status = CASE
		   WHEN contacts.status = 'accepted' THEN 'accepted'
		   WHEN contacts.status = 'blocked' THEN 'blocked'
		   ELSE 'sent'
		 END, updated_at = now()`,
		userID, req.ContactID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to send request"})
		return
	}

	// Also create reverse row for the other user
	_, err = database.Pool.Exec(ctx,
		`INSERT INTO contacts (user_id, contact_id, status)
		 VALUES ($1, $2, 'pending')
		 ON CONFLICT (user_id, contact_id)
		 DO UPDATE SET status = CASE
		   WHEN contacts.status = 'accepted' THEN 'accepted'
		   WHEN contacts.status = 'blocked' THEN 'blocked'
		   ELSE 'pending'
		 END, updated_at = now()`,
		req.ContactID, userID,
	)
	if err != nil {
		log.Printf("[contacts] reverse insert error: %v", err)
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "contact request sent"})
}

func handleAcceptContactRequest(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.ContactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ContactID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "contact_id is required"})
		return
	}

	ctx := context.Background()

	// Check there's a pending request FROM the other user
	var exists bool
	database.Pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM contacts WHERE user_id = $1 AND contact_id = $2 AND status = 'pending')`,
		userID, req.ContactID,
	).Scan(&exists)
	if !exists {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "no pending request from this user"})
		return
	}

	// Create or get direct conversation
	var chatID string
	err := database.Pool.QueryRow(ctx,
		`SELECT id FROM conversations WHERE type = 'direct' AND id IN (
		   SELECT conversation_id FROM conversation_participants WHERE user_id = $1
		   INTERSECT
		   SELECT conversation_id FROM conversation_participants WHERE user_id = $2
		 ) LIMIT 1`,
		userID, req.ContactID,
	).Scan(&chatID)
	if err != nil {
		// Create new conversation
		err = database.Pool.QueryRow(ctx,
			`INSERT INTO conversations (type) VALUES ('direct') RETURNING id`,
		).Scan(&chatID)
		if err != nil {
			log.Printf("[contacts] conversation create error: %v", err)
		} else {
			database.Pool.Exec(ctx,
				`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
				chatID, userID, req.ContactID,
			)
		}
	}

	// Update both rows to accepted
	database.Pool.Exec(ctx,
		`UPDATE contacts SET status = 'accepted', conversation_id = COALESCE($3, conversation_id), updated_at = now()
		 WHERE (user_id = $1 AND contact_id = $2)`,
		userID, req.ContactID, chatID,
	)
	database.Pool.Exec(ctx,
		`UPDATE contacts SET status = 'accepted', conversation_id = COALESCE($3, conversation_id), updated_at = now()
		 WHERE (user_id = $1 AND contact_id = $2)`,
		req.ContactID, userID, chatID,
	)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"message":         "contact request accepted",
		"conversation_id": chatID,
	})
}

func handleRejectContactRequest(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.ContactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ContactID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "contact_id is required"})
		return
	}

	ctx := context.Background()

	// Mark both rows as rejected (retain row so sender can see status and re-send).
	// Don't downgrade if already accepted or blocked.
	database.Pool.Exec(ctx,
		`UPDATE contacts SET status = 'rejected', updated_at = now()
		 WHERE ((user_id = $1 AND contact_id = $2) OR (user_id = $2 AND contact_id = $1))
		   AND status NOT IN ('accepted', 'blocked')`,
		userID, req.ContactID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"message": "contact request rejected"})
}

func handleListContacts(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT c.contact_id, c.status, c.conversation_id, c.created_at,
		        u.username, u.display_name, u.avatar_url, u.bio, u.last_seen
		 FROM contacts c
		 JOIN users u ON u.id = c.contact_id
		 WHERE c.user_id = $1 AND c.status IN ('sent', 'pending', 'accepted')
		 ORDER BY c.created_at DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to list contacts"})
		return
	}
	defer rows.Close()

	contacts := []model.ContactResponse{}
	for rows.Next() {
		var c model.ContactResponse
		var lastSeen *time.Time
		rows.Scan(&c.ContactID, &c.Status, &c.ConversationID, &c.CreatedAt,
			&c.Username, &c.DisplayName, &c.AvatarURL, &c.Bio, &lastSeen)
		if lastSeen != nil {
			c.LastSeen = lastSeen
		}
		// Check online via Valkey
		count, _ := database.Valkey.SCard(ctx, "user_sessions:"+c.ContactID).Result()
		c.IsOnline = count > 0
		contacts = append(contacts, c)
	}

	writeJSON(w, http.StatusOK, model.ContactListResponse{Contacts: contacts})
}

func handleBlockUser(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.BlockRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.BlockedUserID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "blocked_user_id is required"})
		return
	}

	ctx := context.Background()

	// Upsert both directions to blocked
	database.Pool.Exec(ctx,
		`INSERT INTO contacts (user_id, contact_id, status)
		 VALUES ($1, $2, 'blocked')
		 ON CONFLICT (user_id, contact_id)
		 DO UPDATE SET status = 'blocked', updated_at = now()`,
		userID, req.BlockedUserID,
	)
	database.Pool.Exec(ctx,
		`INSERT INTO contacts (user_id, contact_id, status)
		 VALUES ($1, $2, 'blocked')
		 ON CONFLICT (user_id, contact_id)
		 DO UPDATE SET status = 'blocked', updated_at = now()`,
		req.BlockedUserID, userID,
	)

	writeJSON(w, http.StatusOK, map[string]string{"message": "user blocked"})
}

func handleReportUser(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.ReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.ReportedUserID == "" || req.Reason == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "reported_user_id and reason are required"})
		return
	}

	ctx := context.Background()
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO reports (reporter_id, reported_user_id, reason) VALUES ($1, $2, $3)`,
		userID, req.ReportedUserID, req.Reason,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to submit report"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"message": "user reported"})
}

func handleCreateDirectConversation(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	var req model.DirectConversationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.UserID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "user_id is required"})
		return
	}
	if req.UserID == userID {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "cannot start a conversation with yourself"})
		return
	}

	ctx := context.Background()

	// Only accepted friends can start a private chat.
	var status string
	err := database.Pool.QueryRow(ctx,
		`SELECT status FROM contacts WHERE user_id = $1 AND contact_id = $2`,
		userID, req.UserID,
	).Scan(&status)
	if err != nil || status != string(model.ContactAccepted) {
		writeError(w, http.StatusForbidden, &model.AppError{
			Code:    "NOT_FRIENDS",
			Message: "you can only message accepted friends",
		})
		return
	}

	// Check if conversation already exists
	var chatID string
	err = database.Pool.QueryRow(ctx,
		`SELECT c.id FROM conversations c
		 JOIN conversation_participants p1 ON p1.conversation_id = c.id AND p1.user_id = $1
		 JOIN conversation_participants p2 ON p2.conversation_id = c.id AND p2.user_id = $2
		 WHERE c.type = 'direct'
		 LIMIT 1`,
		userID, req.UserID,
	).Scan(&chatID)

	if err != nil {
		// Create new conversation
		err = database.Pool.QueryRow(ctx,
			`INSERT INTO conversations (type) VALUES ('direct') RETURNING id`,
		).Scan(&chatID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to create conversation"})
			return
		}
		database.Pool.Exec(ctx,
			`INSERT INTO conversation_participants (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
			chatID, userID, req.UserID,
		)
	}

	writeJSON(w, http.StatusOK, model.DirectConversationResponse{ChatID: chatID})
}

// --- User Profile ------------------------------------------------------------

func handleUserProfile(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	profileID := chi.URLParam(r, "id")
	if profileID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "user id is required"})
		return
	}

	ctx := context.Background()

	var profile model.UserPublicProfile
	var lastSeen *time.Time
	err := database.Pool.QueryRow(ctx,
		`SELECT id, username, display_name, avatar_url, bio, last_seen, created_at
		 FROM users WHERE id = $1 AND deleted_at IS NULL`,
		profileID,
	).Scan(&profile.ID, &profile.Username, &profile.DisplayName,
		&profile.AvatarURL, &profile.Bio, &lastSeen, &profile.CreatedAt)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "user not found"})
		return
	}
	if lastSeen != nil {
		profile.LastSeen = lastSeen
	}

	// Check online
	count, _ := database.Valkey.SCard(ctx, "user_sessions:"+profileID).Result()
	profile.IsOnline = count > 0

	// Check contact status between current user and profile user
	if profileID != userID {
		var status string
		err = database.Pool.QueryRow(ctx,
			`SELECT status FROM contacts WHERE user_id = $1 AND contact_id = $2`,
			userID, profileID,
		).Scan(&status)
		if err == nil {
			s := model.ContactStatus(status)
			profile.ContactStatus = &s
		}
	}

	writeJSON(w, http.StatusOK, profile)
}

// --- Avatar Upload -----------------------------------------------------------

func handleUploadAvatar(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	// Max 5MB
	r.Body = http.MaxBytesReader(w, r.Body, 5<<20)
	if err := r.ParseMultipartForm(5 << 20); err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_FILE", Message: "file too large or invalid"})
		return
	}

	file, header, err := r.FormFile("avatar")
	if err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_FILE", Message: "avatar file is required"})
		return
	}
	defer file.Close()

	// Validate file type
	contentType := header.Header.Get("Content-Type")
	if contentType != "image/jpeg" && contentType != "image/png" && contentType != "image/webp" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_FILE", Message: "only jpeg, png, and webp are allowed"})
		return
	}

	// Read file bytes
	data := make([]byte, header.Size)
	if _, err := file.Read(data); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to read file"})
		return
	}

	// Save to disk
	uploadDir := os.Getenv("UPLOAD_DIR")
	if uploadDir == "" {
		uploadDir = "./uploads/avatars"
	}
	os.MkdirAll(uploadDir, 0755)

	filename := userID + "_" + fmt.Sprintf("%d", time.Now().Unix()) + ".jpg"
	filePath := uploadDir + "/" + filename
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "INTERNAL", Message: "failed to save file"})
		return
	}

	// Build URL
	baseURL := os.Getenv("PUBLIC_URL")
	if baseURL == "" {
		baseURL = "http://localhost:8081"
	}
	avatarURL := baseURL + "/uploads/avatars/" + filename

	// Update user record
	ctx := context.Background()
	_, err = database.Pool.Exec(ctx,
		`UPDATE users SET avatar_url = $1, updated_at = now() WHERE id = $2`,
		avatarURL, userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to update avatar"})
		return
	}

	writeJSON(w, http.StatusOK, model.AvatarUploadResponse{AvatarURL: avatarURL})
}

// --- Stories ---

func handleCreateStory(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req struct {
		Content   string `json:"content"`
		MediaURL  string `json:"media_url"`
		MediaType string `json:"media_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "INVALID_REQUEST", Message: "Invalid request body"})
		return
	}

	if req.MediaType == "" {
		req.MediaType = "text"
	}
	if req.MediaType != "text" && req.MediaType != "image" && req.MediaType != "video" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "Invalid media_type"})
		return
	}

	ctx := context.Background()
	var storyID string
	err := database.Pool.QueryRow(ctx,
		`INSERT INTO stories (user_id, content, media_url, media_type) VALUES ($1, $2, $3, $4) RETURNING id`,
		userID, req.Content, req.MediaURL, req.MediaType,
	).Scan(&storyID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "Failed to create story"})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"id": storyID})
}

func handleListStories(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	ctx := context.Background()

	rows, err := database.Pool.Query(ctx,
		`SELECT s.id, s.user_id, u.display_name, u.username, u.avatar_url,
		        s.content, s.media_url, s.media_type, s.created_at, s.expires_at
		 FROM stories s
		 JOIN users u ON u.id = s.user_id
		 WHERE s.expires_at > now()
		   AND (s.user_id = $1
		     OR s.user_id IN (
		       SELECT contact_id FROM contacts
		       WHERE user_id = $1 AND status = 'accepted'
		     ))
		 ORDER BY s.user_id, s.created_at DESC`,
		userID,
	)
	if err != nil {
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "Failed to list stories"})
		return
	}
	defer rows.Close()

	type StoryResponse struct {
		ID          string    `json:"id"`
		UserID      string    `json:"user_id"`
		DisplayName string    `json:"display_name"`
		Username    string    `json:"username"`
		AvatarURL   string    `json:"avatar_url"`
		Content     string    `json:"content"`
		MediaURL    string    `json:"media_url"`
		MediaType   string    `json:"media_type"`
		CreatedAt   time.Time `json:"created_at"`
		ExpiresAt   time.Time `json:"expires_at"`
	}

	var stories []StoryResponse
	for rows.Next() {
		var s StoryResponse
		if err := rows.Scan(&s.ID, &s.UserID, &s.DisplayName, &s.Username, &s.AvatarURL,
			&s.Content, &s.MediaURL, &s.MediaType, &s.CreatedAt, &s.ExpiresAt); err != nil {
			continue
		}
		stories = append(stories, s)
	}

	if stories == nil {
		stories = []StoryResponse{}
	}

	writeJSON(w, http.StatusOK, map[string]any{"stories": stories})
}

func handleDeleteStory(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)
	storyID := chi.URLParam(r, "id")
	ctx := context.Background()

	tag, err := database.Pool.Exec(ctx,
		`DELETE FROM stories WHERE id = $1 AND user_id = $2`,
		storyID, userID,
	)
	if err != nil || tag.RowsAffected() == 0 {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "Story not found"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// --- E2EE Key Handlers ---------------------------------------------------------

type e2eeKeyRequest struct {
	PublicKey string `json:"public_key"`
}

func handleRegisterE2EEKey(w http.ResponseWriter, r *http.Request) {
	userID, _ := r.Context().Value(middleware.UserIDKey).(string)

	var req e2eeKeyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, model.ErrInvalidRequest)
		return
	}
	if req.PublicKey == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "public_key is required"})
		return
	}

	ctx := context.Background()
	_, err := database.Pool.Exec(ctx,
		`INSERT INTO e2ee_keys (user_id, public_key)
		 VALUES ($1, $2)
		 ON CONFLICT (user_id)
		 DO UPDATE SET public_key = $2, updated_at = now()`,
		userID, req.PublicKey,
	)
	if err != nil {
		log.Printf("[e2ee] upsert error: %v", err)
		writeError(w, http.StatusInternalServerError, &model.AppError{Code: "DB_ERROR", Message: "failed to store key"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func handleGetE2EEKey(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "userId")
	if userID == "" {
		writeError(w, http.StatusBadRequest, &model.AppError{Code: "VALIDATION", Message: "user_id is required"})
		return
	}

	ctx := context.Background()
	var publicKey string
	err := database.Pool.QueryRow(ctx,
		`SELECT public_key FROM e2ee_keys WHERE user_id = $1`,
		userID,
	).Scan(&publicKey)
	if err != nil {
		writeError(w, http.StatusNotFound, &model.AppError{Code: "NOT_FOUND", Message: "no e2ee key found for user"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"user_id":    userID,
		"public_key": publicKey,
	})
}
