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
- `closetalk_backend/internal/database/neon.go` — PostgreSQL connection pool + auto-migration (12+ tables)
- `closetalk_backend/internal/database/valkey.go` — Valkey client + session/rate-limit helpers
- `closetalk_backend/internal/auth/jwt.go` — JWT generation & validation (HS256, 15min access / 7d refresh)
- `closetalk_backend/internal/auth/password.go` — bcrypt (cost 12), SHA-256 phone hashing, recovery code generation
- `closetalk_backend/internal/middleware/auth.go` — JWT auth middleware + admin guard
- `closetalk_backend/internal/middleware/ratelimit.go` — Per-user, per-IP, per-chat rate limiting
- `closetalk_backend/internal/middleware/logging.go` — Structured request logging
- `closetalk_backend/infrastructure/migrations/` — SQL migration files (up/down for v001, v002, v003)
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

## 2026-05-09 — Group Chat System

**Files created:**
- `closetalk_backend/internal/model/group.go` — Group, GroupMember, PinnedMessage, GroupInvite models + requests/responses
- `closetalk_backend/cmd/auth-service/groups.go` — 12 group handlers (create, get, list, invite, join, add/remove members, roles, leave, settings, pin/unpin)
- `closetalk_backend/infrastructure/migrations/000003_create_groups.up.sql` — Groups migration (conversations, participants, groups, members, pins, settings)
- `closetalk_backend/infrastructure/migrations/000003_create_groups.down.sql` — Groups rollback
- `closetalk_app/lib/models/group.dart` — Group, GroupMember, PinnedMessage, GroupListItem Dart models
- `closetalk_app/lib/services/group_service.dart` — REST API client for group CRUD (13 methods)
- `closetalk_app/lib/screens/chat/group_create_screen.dart` — Create group screen with name, description, privacy
- `closetalk_app/lib/screens/chat/group_info_screen.dart` — Group info, member list, invite link, settings sheet

**Database tables added (auto-migration):**
- `conversations` — type (direct/group), metadata, last_message_at
- `conversation_participants` — many-to-many user-conversation with read tracking
- `groups` — name, description, avatar, created_by, member_limit, invite_code, message_retention, disappearing_msg
- `group_members` — role (admin/member), invited_by, left_at tracking
- `pinned_messages` — message_id, pinned_by, unpinned_at
- `group_settings` — per-group retention and disappearing message overrides

**Group endpoints (added to auth-service):**
| Method | Endpoint | Description |
|---|---|---|
| GET | `/groups` | List my groups |
| POST | `/groups` | Create group (with members) |
| GET | `/groups/{id}` | Group details + members + pins |
| POST | `/groups/{id}/invite` | Generate invite code |
| POST | `/groups/join` | Join via invite code |
| POST | `/groups/{id}/members` | Add members (admin only) |
| DELETE | `/groups/{id}/members/{userId}` | Remove member (admin only) |
| PUT | `/groups/{id}/members/{userId}/role` | Promote/demote (admin only) |
| POST | `/groups/{id}/leave` | Leave group |
| PUT | `/groups/{id}/settings` | Update group settings (admin only) |
| POST | `/groups/{id}/pin` | Pin message (admin only) |
| DELETE | `/groups/{id}/pin/{messageId}` | Unpin message (admin only) |

**Key behaviors:**
- Creator automatically added as admin + conversation participant
- Group creation is transactional (conversation + group + members + participants)
- Invite codes are 12-char random alphanumeric, valid for 7 days
- Member limit checking on join
- Last admin leaving promotes oldest member to admin
- Admin cannot remove another admin
- Groups listed sorted by most recent activity

**Verification:**
- [x] `go vet ./...` — zero issues
- [x] `go build ./cmd/auth-service/` — builds clean with group routes
- [x] `go build ./cmd/message-service/` — still builds clean
