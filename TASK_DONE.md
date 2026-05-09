# CloseTalk — Task Completion Log

> Every completed task logged here with date, files changed, and verification status.

---

## 2026-05-09 — Go Backend Scaffold + Auth Service

**Files created:**
- `closetalk_backend/go.mod` — Go module initialized with Go 1.26, deps: chi, pgx, go-redis, jwt, bcrypt
- `closetalk_backend/cmd/auth-service/main.go` — Auth service entry point with all handlers
- `closetalk_backend/internal/model/user.go` — User, RegisterRequest, LoginRequest, AuthResponse, etc.
- `closetalk_backend/internal/model/device.go` — Device, LinkDeviceRequest, DeviceResponse
- `closetalk_backend/internal/model/session.go` — Session, RecoveryCode
- `closetalk_backend/internal/model/errors.go` — Standard API error types and codes
- `closetalk_backend/internal/database/neon.go` — PostgreSQL connection pool + auto-migration (8 tables)
- `closetalk_backend/internal/database/valkey.go` — Valkey client + session/rate-limit helpers
- `closetalk_backend/internal/auth/jwt.go` — JWT generation & validation (HS256, 15min access / 7d refresh)
- `closetalk_backend/internal/auth/password.go` — bcrypt (cost 12), SHA-256 phone hashing, recovery code generation
- `closetalk_backend/internal/middleware/auth.go` — JWT auth middleware + admin guard
- `closetalk_backend/internal/middleware/ratelimit.go` — Per-user, per-IP, per-chat rate limiting
- `closetalk_backend/internal/middleware/logging.go` — Structured request logging
- `closetalk_backend/infrastructure/migrations/` — SQL migration files (up/down for v001, v002)
- `closetalk_backend/docker-compose.yml` — Local dev: Go service + PostgreSQL 17 + Valkey 8.1
- `closetalk_backend/Dockerfile` — Multi-stage build (golang:1.26-alpine → distroless)
- `closetalk_backend/.env.example` — Environment variable template
- `closetalk_backend/.gitignore` — Go build artifacts

**Auth service endpoints:**
| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/register` | Register with email + password, returns JWT + 10 recovery codes |
| POST | `/auth/login` | Login, returns JWT + user profile |
| POST | `/auth/oauth` | OAuth stub (Google/Apple) |
| POST | `/auth/refresh` | Rotate refresh token |
| POST | `/auth/recover` | Verify recovery code (one-time) |
| POST | `/auth/recover/email` | Request email recovery (stub) |
| PUT | `/auth/password` | Change password (JWT required) |
| POST | `/auth/logout` | Invalidate sessions (JWT required) |
| GET | `/devices` | List linked devices (JWT required) |
| POST | `/devices/link` | Link new device (JWT required, max 5) |
| POST | `/devices/revoke` | Revoke device (JWT required) |
| GET | `/health` | Health check |

**Database tables created (auto-migration):**
- `users` — email, phone, password_hash, oauth, is_admin, soft delete
- `recovery_codes` — 10 one-time codes per user, SHA-256 hashed
- `user_devices` — multi-device support (max 5 per user)
- `user_settings` — privacy controls (last_seen, profile photo, read receipts, etc.)

**Verification:**
- [x] `go mod tidy` — all 15 dependencies resolved
- [x] `go build ./cmd/auth-service/` — 17MB binary built successfully
- [x] `go vet ./...` — zero issues
- [x] All database migrations defined and tested locally
- [x] Valkey connection + session management helpers implemented
- [x] Recovery codes: 10 generated at signup, SHA-256 hashed, one-time use
- [x] Rate limiting: per-user (100/min), per-IP (1000/min)
- [x] JWT: RS256→HS256 with 15min access + 7d refresh tokens

---

## 2026-05-09 — Message Service (REST + WebSocket Real-Time)

**Files created:**
- `closetalk_backend/cmd/message-service/main.go` — Message service with REST API + WebSocket hub + 9 endpoints
- `closetalk_backend/internal/model/message.go` — Message, Reaction, PaginatedMessages, WebSocketMessage models
- `closetalk_backend/internal/database/store.go` — MessageStore interface (10 methods)
- `closetalk_backend/internal/database/memstore.go` — Thread-safe in-memory message store (ScyllaDB fallback)
- `closetalk_backend/internal/database/scylla.go` — ScyllaDB connection + schema init (messages, message_reads, message_reactions, bookmarks)
- `closetalk_backend/internal/database/scylla_store.go` — ScyllaDB-backed MessageStore with full CQL queries
- `closetalk_app/lib/models/message.dart` — Message, Reaction, PaginatedMessages Dart models
- `closetalk_app/lib/services/message_service.dart` — REST API client for message CRUD
- `closetalk_app/lib/services/webtransport_service.dart` — WebSocket client with auto-reconnect, typing indicators

**Message service endpoints:**
| Method | Endpoint | Description |
|---|---|---|
| POST | `/messages` | Send message (JWT) |
| GET | `/messages/{chatId}` | Paginated history (cursor-based) |
| PUT | `/messages/{messageId}` | Edit message (15min window) |
| DELETE | `/messages/{messageId}` | Delete message (15min window) |
| POST | `/messages/{messageId}/react` | Toggle emoji reaction |
| POST | `/messages/{messageId}/read` | Mark as read |
| POST | `/bookmarks` | Bookmark message |
| DELETE | `/bookmarks/{messageId}` | Remove bookmark |
| GET | `/bookmarks` | List bookmarks |
| WS | `/ws?token=&chat_id=` | WebSocket real-time messaging |

**Infrastructure:**
- Updated `docker-compose.yml` — Added message-service + ScyllaDB 6.2 (5 services total)
- Updated `go.mod` — Added gocql, gorilla/websocket, google/uuid, godotenv

**Verification:**
- [x] `go vet ./...` — zero issues
- [x] `go build ./cmd/message-service/` — builds clean
- [x] `go build ./cmd/auth-service/` — still builds clean (17MB)
- [x] All deps resolved via `go mod tidy`
- [x] MemStore fallback when ScyllaDB unavailable
- [x] WebSocket hub with per-chat broadcasting + 30s ping
- [x] Cursor-based pagination (50 per page)
- [x] Optimistic UI ready: message status ticks (sent→delivered→read) through WebSocket

---

## 2026-05-09 — Initial Git Commit (Backend + Flutter Stubs)

**Files committed:**
- Full `closetalk_backend/` — Auth service + Message service + all packages
- Flutter stubs — `message.dart`, `message_service.dart`, `webtransport_service.dart`
- `docs/planning.md` — Decision field filled in
- `TASK_DONE.md` — Task completion log

**Files created:**
- `closetalk_backend/go.mod` — Go module initialized with Go 1.26, deps: chi, pgx, go-redis, jwt, bcrypt
- `closetalk_backend/cmd/auth-service/main.go` — Auth service entry point with all handlers
- `closetalk_backend/internal/model/user.go` — User, RegisterRequest, LoginRequest, AuthResponse, etc.
- `closetalk_backend/internal/model/device.go` — Device, LinkDeviceRequest, DeviceResponse
- `closetalk_backend/internal/model/session.go` — Session, RecoveryCode
- `closetalk_backend/internal/model/errors.go` — Standard API error types and codes
- `closetalk_backend/internal/database/neon.go` — PostgreSQL connection pool + auto-migration (8 tables)
- `closetalk_backend/internal/database/valkey.go` — Valkey client + session/rate-limit helpers
- `closetalk_backend/internal/auth/jwt.go` — JWT generation & validation (HS256, 15min access / 7d refresh)
- `closetalk_backend/internal/auth/password.go` — bcrypt (cost 12), SHA-256 phone hashing, recovery code generation
- `closetalk_backend/internal/middleware/auth.go` — JWT auth middleware + admin guard
- `closetalk_backend/internal/middleware/ratelimit.go` — Per-user, per-IP, per-chat rate limiting
- `closetalk_backend/internal/middleware/logging.go` — Structured request logging
- `closetalk_backend/infrastructure/migrations/` — SQL migration files (up/down for v001, v002)
- `closetalk_backend/docker-compose.yml` — Local dev: Go service + PostgreSQL 17 + Valkey 8.1
- `closetalk_backend/Dockerfile` — Multi-stage build (golang:1.26-alpine → distroless)
- `closetalk_backend/.env.example` — Environment variable template
- `closetalk_backend/.gitignore` — Go build artifacts

**Auth service endpoints:**
| Method | Endpoint | Description |
|---|---|---|
| POST | `/auth/register` | Register with email + password, returns JWT + 10 recovery codes |
| POST | `/auth/login` | Login, returns JWT + user profile |
| POST | `/auth/oauth` | OAuth stub (Google/Apple) |
| POST | `/auth/refresh` | Rotate refresh token |
| POST | `/auth/recover` | Verify recovery code (one-time) |
| POST | `/auth/recover/email` | Request email recovery (stub) |
| PUT | `/auth/password` | Change password (JWT required) |
| POST | `/auth/logout` | Invalidate sessions (JWT required) |
| GET | `/devices` | List linked devices (JWT required) |
| POST | `/devices/link` | Link new device (JWT required, max 5) |
| POST | `/devices/revoke` | Revoke device (JWT required) |
| GET | `/health` | Health check |

**Database tables created (auto-migration):**
- `users` — email, phone, password_hash, oauth, is_admin, soft delete
- `recovery_codes` — 10 one-time codes per user, SHA-256 hashed
- `user_devices` — multi-device support (max 5 per user)
- `user_settings` — privacy controls (last_seen, profile photo, read receipts, etc.)

**Verification:**
- [x] `go mod tidy` — all 15 dependencies resolved
- [x] `go build ./cmd/auth-service/` — 17MB binary built successfully
- [x] `go vet ./...` — zero issues
- [x] All database migrations defined and tested locally
- [x] Valkey connection + session management helpers implemented
- [x] Recovery codes: 10 generated at signup, SHA-256 hashed, one-time use
- [x] Rate limiting: per-user (100/min), per-IP (1000/min)
- [x] JWT: RS256→HS256 with 15min access + 7d refresh tokens
