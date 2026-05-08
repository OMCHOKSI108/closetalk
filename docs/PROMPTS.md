# CloseTalk — 20 VibeCoding Prompts

> Copy-paste these prompts in order to your AI coding agent (Cursor, Claude, Copilot, etc.) to build the entire project. Each prompt builds on the last and includes recovery instructions if something goes wrong.

---

## Prompt 1 — Gather Full Project Context

```
You are building CloseTalk — a production-grade chat app for 100,000 users that fixes every major WhatsApp problem. Before writing any code, read and understand these project files:

1. Read `/PROJECT.md` — understand the full project guide, structure, and workflow
2. Read `/docs/whatsapp-gap-analysis.md` — understand what we're fixing vs WhatsApp
3. Read `/docs/product-vision.md` — understand the end-user experience
4. Read `/docs/architecture.md` — understand the system architecture and services
5. Read `/docs/requirements.md` — understand all functional and non-functional requirements

After reading all files:
- Summarize the project in 5 bullet points
- List the tech stack
- List the top 3 architectural decisions that make this different from WhatsApp
- Confirm you understand the project scope

Do NOT write any code yet. This is a context-gathering step only.
```

**Verify:** Agent outputs a clear summary confirming it understands all 5 docs.

---

## Prompt 2 — Initialize Flutter App with Proper Structure

```
Now set up the Flutter project structure based on the docs you just read.

Using `/PROJECT.md` → Project Structure section as reference:

1. Read the existing `closetalk_app/` directory
2. Replace the default counter app scaffold with a proper structure:
   - `lib/config/` — app config, constants, theme
   - `lib/models/` — User, Message, Chat, Group models (immutable, with fromJson/toJson)
   - `lib/services/` — api_client.dart, auth_service.dart, webtransport_service.dart (stubs)
   - `lib/providers/` — auth_provider.dart, chat_provider.dart (stubs using Riverpod)
   - `lib/screens/` — auth/, chat/, group/, status/, settings/, search/, channel/
   - `lib/widgets/` — common widgets (avatar, message_bubble, chat_tile)
   - `lib/l10n/` — localization setup (English + Hindi at minimum)
3. Add required packages to pubspec.yaml:
   - `flutter_riverpod` or `bloc` (state management)
   - `flutter_secure_storage` (token storage)
   - `go_router` (navigation)
   - `freezed_annotation` + `json_annotation` (models)
   - `flutter_localizations` (i18n)
   - `intl`
4. Create `lib/main.dart` with MaterialApp.router setup (NOT the counter app)
5. Create `lib/app.dart` with theme (light + dark mode)
6. Update `analysis_options.yaml` to remove unnecessary lint ignores

CRITICAL:
- Every file must be a proper, non-empty stub with imports, class declarations, and TODOs
- Models must have fromJson/toJson factory methods
- Providers must extend the correct Riverpod/BLoC class
- After creating all files, run `flutter pub get` and `flutter analyze` — fix ALL errors before reporting done

Show me: the final directory tree, pubspec.yaml dependencies, and flutter analyze output (must be clean).
```

**Verify:** `flutter pub get` succeeds, `flutter analyze` is clean, directory matches PROJECT.md.

---

## Prompt 3 — Build Complete Authentication System

```
Now build the complete auth system based on these doc references:
- `/docs/requirements.md` → F1.1–F1.9 (User Management)
- `/docs/architecture-flow.md` → Diagram 2 (User Authentication Flow)
- `/docs/security.md` → Authentication section
- `/docs/multi-device-sync.md` → Device Linking section

Implement:

BACKEND (choose one language and stick with it):

Node.js or Go — create `closetalk_backend/services/auth-service/`:
1. POST /auth/register — email/password with bcrypt (cost 12+), return JWT
2. POST /auth/login — validate credentials, return access_token (15min) + refresh_token (7d)
3. POST /auth/oauth — handle Google/Apple OAuth callback
4. POST /auth/refresh — rotate refresh token
5. POST /auth/recover — validate recovery code (1 of 10), return session token
6. POST /devices/link — link a new device with QR code flow
7. POST /devices/revoke — revoke a device by ID, force-close its connections
8. GET /devices — list all active devices for the current user

In-memory storage for now. Use JWT signing with RS256.

FLUTTER:
1. Auth screens: login_screen.dart, register_screen.dart, recovery_screen.dart
2. auth_service.dart — API client calling the backend
3. auth_provider.dart — Riverpod state management for auth
4. Secure token storage using flutter_secure_storage
5. Auto-login on app start (check stored token, refresh if expired)
6. Account recovery flow (recovery codes from F1.6)

VERIFICATION:
- `flutter analyze` must be clean
- Backend server starts and responds to POST /auth/register with valid JWT
- Show me: curl example of register + login + device link flow

CRITICAL: Recovery codes MUST be 10 one-time codes. Display them ONCE at signup.
```

**Verify:** Backend starts, curl register + login returns JWT, flutter analyze clean.

---

## Prompt 4 — Build Message Service with WebTransport Transport

```
Build the core messaging system based on:
- `/docs/requirements.md` → F3.1–F3.10 (Messaging), F6.1–F6.4 (Real-Time)
- `/docs/architecture-flow.md` → Diagram 3 (Real-Time Message Delivery)
- `/docs/architecture-flow.md` → Diagram 4 (WebTransport Connection)
- `/docs/architecture.md` → Key Decision #3 (WebTransport)

BACKEND:
Create `closetalk_backend/services/message-service/`:

1. WebTransport endpoint (primary):
   - Handle QUIC connections with JWT auth
   - Reliable stream: send/receive messages with ACK
   - Unreliable datagram: typing indicators, presence pings, cursor position
   - 0-RTT reconnection support

2. REST API (fallback):
   - POST /messages — send message { chat_id, content, content_type }
   - GET /messages/:chat_id — paginated history (cursor-based)
   - PUT /messages/:id — edit message
   - DELETE /messages/:id — delete message
   - POST /messages/:id/react — add/remove emoji reaction

3. Message model with status tracking: sending → sent → delivered → read

FLUTTER:
1. `webtransport_service.dart` — WebTransport client with:
   - Connect with JWT, auto-reconnect with 0-RTT
   - Send stream for messages, send datagram for typing/presence
   - Receive stream for incoming messages
   - Fallback to SSE, then WebSocket if WebTransport fails

2. `chat_screen.dart` — message list with scroll-to-bottom, bubbles, typing indicator, reply preview, emoji reaction picker, status ticks

3. `chat_provider.dart` — state management with:
   - Pull-to-refresh for history
   - Optimistic UI (show message immediately, update tick on ACK)
   - Offline queue (save unsent messages locally, send on reconnect)

VERIFICATION:
- Send a message from one client → appears on another client in < 50ms
- Typing indicator appears in < 20ms via datagram
- Optimistic UI works (message shows before server ACK)
- `flutter analyze` clean

CRITICAL: WebTransport over QUIC is PRIMARY. WebSocket is fallback only.
```

**Verify:** Two clients send/receive in real-time. Typing indicators appear instantly.

---

## Prompt 5 — Connect Databases (Neon PostgreSQL + ScyllaDB + Valkey)

```
Now connect the real databases based on:
- `/docs/architecture.md` → Polyglot Persistence section
- `/docs/requirements.md` → N2.1–N2.5 (Scalability)
- `/docs/architecture-flow.md` → Diagram 6 (Database Architecture)

IMPLEMENT:

1. Neon PostgreSQL (Users, Groups, Metadata):
   - Schema: users, groups, group_members, contacts, user_devices, conversations
   - Row Level Security (RLS) on all tables
   - Migration scripts in `closetalk_backend/infrastructure/migrations/`

2. ScyllaDB Cloud (Messages):
   - Keyspace + tables: messages, message_reads, message_reactions
   - Primary key: chat_id (partition), created_at (clustering)
   - Alternator API (DynamoDB-compatible)
   - Pagination: SELECT WHERE chat_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT 50

3. Valkey 8.1 (Session, Presence, Cache):
   - Refresh tokens, device sessions, rate limit counters
   - TTLs: sessions 7d, rate limits 1min, presence 30s
   - Pub/sub for presence broadcasting

4. Connection pooling: PgBouncer for PostgreSQL, pool for Valkey, pool for ScyllaDB

VERIFICATION:
- All services start and connect to their databases
- Register user → stored in PostgreSQL
- Send message → stored in ScyllaDB, retrievable via paginated query
- Session → stored in Valkey with correct TTL
- `docker-compose up` starts all services without errors

CRITICAL: Messages → ScyllaDB. Metadata → PostgreSQL. Sessions → Valkey. Do NOT mix them.
```

**Verify:** All three databases connect and store/retrieve data correctly.

---

## Prompt 6 — Build Group Chat System

```
Build group chats based on:
- `/docs/requirements.md` → F5.1–F5.8 (Group Chats)
- `/docs/architecture-flow.md` → Diagram 6 (Database ERD)

BACKEND:
1. POST /groups — create group { name, description, avatar, member_ids[] }
2. POST /groups/:id/invite — generate shareable invite link with expiry
3. POST /groups/join — join via invite link { code }
4. POST /groups/:id/members — add members (admin only)
5. DELETE /groups/:id/members/:user_id — remove member (admin only)
6. PUT /groups/:id/members/:user_id/role — promote/demote admin
7. POST /groups/:id/leave — leave group
8. PUT /groups/:id/settings — update group settings
9. POST /groups/:id/pin — pin a message
10. GET /groups/:id/messages — paginated group message history

FLUTTER:
1. `group_create_screen.dart` — create group with member picker
2. `group_info_screen.dart` — group settings, member list, admin tools
3. `invite_link_screen.dart` — share invite link with QR code
4. `group_settings_sheet.dart` — retention, disappearing messages, pinned messages

DATABASE:
- Update Neon PostgreSQL: groups + group_members tables
- RLS policies: group members can read; non-members cannot

VERIFICATION:
- Create a group → invite link works → members send/receive
- Non-members cannot access group messages (RLS enforced)
- Admin removes member → member can no longer access group
- `flutter analyze` clean

CRITICAL: Non-member must NEVER read group messages. RLS is last defense — test explicitly.
```

**Verify:** Group creation, invite, admin removal, and RLS enforcement all work.

---

## Prompt 7 — Build Multi-Device Sync

```
Build native multi-device sync based on:
- `/docs/multi-device-sync.md` — full protocol specification
- `/docs/requirements.md` → F4.1–F4.6 (Multi-Device Sync)
- `/docs/architecture-flow.md` → Device Lifecycle diagrams

IMPLEMENT:

BACKEND:
1. POST /devices/link — QR code flow with full history sync
2. GET /sync/messages?after={message_id} — incremental sync (50 per page, cursor-based)
3. Server-side fan-out: push message to ALL linked devices of recipient
4. GET /sync/status?after={timestamp} — sync status/stories too
5. DELETE /devices/:id — revoke device, close all active connections

FLUTTER:
1. `device_link_screen.dart` — QR code scanner for linking
2. `device_management_screen.dart` — list/revoke devices
3. `sync_service.dart` — sync state management with progress indicator
4. Exponential backoff for backlogs:
   - < 100 msgs → deliver all immediately
   - 100-1000 → 50-msg batches with 100ms gap
   - > 1000 → first 500, rest on demand

STATE: Track `last_synced_message_id` per chat. Deduplicate by message_id.

VERIFICATION:
- Link a new device → see complete message history
- Send message on phone → appears on desktop in < 100ms
- Revoke device → device logged out, cannot receive
- Device offline 2 days → catch-up sync works with batching
- `flutter analyze` clean

CRITICAL: Phone is NOT required as relay. Kill phone → desktop still works independently.
```

**Verify:** Kill phone process → desktop still works. Link new device → full history syncs.

---

## Prompt 8 — Build Media Pipeline

```
Build the media pipeline based on:
- `/docs/architecture-flow.md` → Diagram 11 (Media Upload & Processing)
- `/docs/architecture.md` → Key Decision #7 (Direct Media Upload)

BACKEND:
1. POST /media/upload-url — presigned S3 PUT URL { file_type, file_size, chat_id }
   - Validate: max 100MB, allowed types
   - Return: upload_url (5min), media_id, cdn_url
2. POST /media/confirm — confirm upload { media_id, etag }
3. Lambda on S3 ObjectCreated:
   - Virus scan (ClamAV) → quarantine if infected
   - Image: thumbnails (100/400/1200), WebP/AVIF
   - Video: HLS transcoding (1080p/720p/480p)
   - Voice: optimize to Opus
   - Cache thumbnail URLs in Valkey (TTL: 1hr)
4. GET /media/:media_id — serve via CloudFront (signed URL)

FLUTTER:
1. `media_picker.dart` — image picker, camera, file picker, voice recorder
2. Upload flow: request presigned URL → upload to S3 (progress bar) → confirm → send message with media_id → optimistic thumbnail → replace when processed
3. `media_viewer.dart` — full-screen image/video viewer
4. Voice message UI: hold-to-record, release-to-send, waveform

CRITICAL: Server NEVER touches raw media bytes. Client → S3 direct. Fixes WhatsApp's quality loss.

VERIFICATION:
- Upload image → presigned URL → S3 → thumbnail → message with thumbnail
- Upload video → HLS transcoding works
- Malware test file → virus scan quarantines
- `flutter analyze` clean
```

**Verify:** Full upload flow end-to-end. Original quality preserved.

---

## Prompt 9 — Build Full-Text Search

```
Build search based on:
- `/docs/architecture-flow.md` → Diagram 14 (Full-Text Search)
- `/docs/requirements.md` → F3.8 (Message search)

BACKEND:
1. Create `search-service/` with Elasticsearch:
   - Index messages on create (SQS-triggered)
   - Index mapping: message_id, chat_id, sender_id, content, created_at, content_type, chat_name, sender_name
   - Index lifecycle: hot (7d), warm (30d), cold (90d+)

2. GET /search?q={query}&chat_id=&from=&to=&sender=&page=1
   - Full-text search with relevance scoring
   - Filters: date range, sender, chat, media type
   - Highlights with <em> tags
   - Cursor-based pagination
   - Rate limited: 30 queries per user per minute

3. Backfill Lambda to batch-index existing messages

FLUTTER:
1. `search_screen.dart`:
   - Search bar with debounce (300ms)
   - Results grouped by chat, sorted by relevance
   - Highlighted snippets, chat name, sender, timestamp
   - Filter chips: date, sender, chat, media type
   - Tap result → navigate to exact message

2. Cache recent 20 searches locally

VERIFICATION:
- Send messages with keywords → search finds with relevance ranking
- Filters work: by date, sender, chat
- Search 10,000 messages in < 500ms
- `flutter analyze` clean
```

**Verify:** Correct search results with highlights. Filters work. Performance < 500ms.

---

## Prompt 10 — Build Privacy Controls & Contact Discovery

```
Build privacy controls based on:
- `/docs/requirements.md` → F2.1–F2.7 (Contact Discovery & Privacy)
- `/docs/architecture-flow.md` → Diagram 12 (Privacy-Preserving Contact Discovery)

BACKEND:
1. POST /contacts/discover — hash-based contact discovery:
   - Input: SHA-256 hashed phone numbers
   - Output: matched user_ids + display_names + avatar_urls
   - Server NEVER stores raw hashes
   - Cache in Valkey (TTL: 24hr)

2. User privacy settings (PostgreSQL user_settings):
   - last_seen_visibility: nobody | everyone | contacts | contacts_except
   - profile_photo_visibility: nobody | everyone | contacts
   - read_receipts: boolean + per_chat_overrides (JSONB)
   - group_add_permission: everyone | contacts | contacts_except
   - status_privacy: contacts | close_friends | public

3. Block/unblock:
   - POST /blocks/:user_id — block
   - DELETE /blocks/:user_id — unblock
   - Blocked: cannot send messages, see last_seen, profile photo, or status
   - Block list syncs across all devices

4. Enforce at API + database layer

FLUTTER:
1. `privacy_settings_screen.dart` — all privacy toggles
2. `block_list_screen.dart` — view/manage blocked users
3. `contact_discovery_screen.dart` — find contacts (phone permission flow)

CRITICAL: Server NEVER sees raw phone numbers. Hash-based only. Fixes WhatsApp's biggest privacy problem.

VERIFICATION:
- Two users discover each other via hashed numbers
- last_seen="nobody" → others see "Last seen recently"
- Blocked user cannot send messages
- `flutter analyze` clean
```

**Verify:** Contact discovery without raw numbers. All privacy settings enforced.

---

## Prompt 11 — Build Stories / Status

```
Build Stories/Status based on:
- `/docs/requirements.md` → F7.1–F7.6 (Stories / Status)
- `/docs/architecture-flow.md` → Diagram 15 (Stories / Status Flow)

BACKEND:
1. POST /status — create status { type, content/media_id, privacy }
2. GET /status/updates — get updates from contacts (sorted by most recent)
3. GET /status/:id/views — who viewed my status
4. POST /status/:id/view — mark as viewed { viewer_id }
5. POST /status/:id/reply — reply to status via DM
6. Lambda (hourly): delete expired statuses (created_at > 24h)

Storage: ScyllaDB — statuses PK (user_id, created_at) TTL 24h, status_views PK (status_id, viewer_id)

FLUTTER:
1. `status_list_screen.dart` — horizontal scroll of contact statuses (top of chat list)
2. `status_viewer_screen.dart` — tap-through viewer, 5s auto-advance, swipe to close
3. `status_creator_screen.dart` — camera/gallery picker, text overlay, privacy selector
4. `status_privacy_screen.dart` — close friends list management

VERIFICATION:
- Post status → appears in contacts' status list
- View status → poster sees who viewed
- After 24h → auto-deletes
- "Close Friends" privacy works
- `flutter analyze` clean
```

**Verify:** Status creation, viewing, tracking, and auto-expiry all work.

---

## Prompt 12 — Build Broadcast & Channels

```
Build Broadcast/Channels based on:
- `/docs/requirements.md` → F8.1–F8.5 (Broadcast & Channels)
- `/docs/architecture-flow.md` → Diagram 16 (Broadcast & Channels Flow)

BACKEND:
1. Broadcast lists:
   - POST /broadcasts — create { name, member_ids[] }
   - POST /broadcasts/:id/send — send to all members (each receives as DM)
   - GET /broadcasts — list my lists

2. Channels:
   - POST /channels — create { name, description, avatar, is_public }
   - POST /channels/:id/subscribe — subscribe
   - POST /channels/:id/unsubscribe — unsubscribe
   - POST /channels/:id/messages — send (admin only)
   - GET /channels/:id/messages — paginated messages
   - GET /channels/:id/subscribers — count + list (admin only)
   - GET /channels/discover — discover public channels

3. Fan-out: SNS push to all subscribers when admin sends

FLUTTER:
1. `broadcast_list_screen.dart` — create/manage broadcast lists
2. `channel_discover_screen.dart` — discover and subscribe
3. `channel_screen.dart` — channel messages (read-only for subscribers)
4. `channel_admin_screen.dart` — subscriber list, analytics

VERIFICATION:
- Broadcast → all recipients receive as DM
- Create channel → subscribe → admin sends → all subscribers receive
- `flutter analyze` clean
```

**Verify:** Broadcast sends individual DMs. Channel broadcasts to all subscribers.

---

## Prompt 13 — Build AI Integration (Moderation + Assistant + Translation)

```
Build AI features based on:
- `/docs/architecture.md` → AI Infrastructure section
- `/docs/architecture-flow.md` → Diagram 5 (Content Moderation Pipeline)
- `/docs/requirements.md` → F11.1–F11.5, F12.1–F12.4
- `/docs/security.md` → AI & Agent Security section

IMPLEMENT:

1. Content Moderation Pipeline:
   - Message → SQS FIFO → Lambda → Bedrock Guardrails (Claude 3.5 Haiku)
   - Natural-language policies: hate speech, PII, harassment, spam
   - Passed → deliver. Flagged → quarantine for review.
   - GRACEFUL DEGRADATION: Bedrock down → pass-through with deferred scanning
   - Log all to S3 for audit

2. AI Chat Assistant:
   - POST /ai/ask { question, chat_context? }
   - Bedrock AgentCore with episodic memory (per-user, never cross-tenant)
   - Rate limited: 10 calls per user per minute

3. Inline Translation:
   - POST /translate { message_id, target_language }
   - Auto-detect source language
   - Cache translations in Valkey (TTL: 24hr)

4. Group Summaries:
   - POST /groups/:id/summarize — generate AI summary
   - Scheduled Lambda: daily digest for active groups

FLUTTER:
1. Show "Under review" for flagged content (don't block UI)
2. AI Assistant: dedicated chat screen or floating button
3. Translation: tap any message → "Translate" in context menu
4. Group Summary: "View summary" button at top

CRITICAL: AI must NEVER fail core messaging. If AI down → pass-through, hide buttons, show "unavailable".

VERIFICATION:
- Send hate speech → flagged and quarantined
- Ask assistant → response with context memory
- Translate message → correct translation
- Kill Bedrock → messages still deliver (pass-through)
- `flutter analyze` clean
```

**Verify:** Moderation catches bad content. Assistant remembers context. Translation works. Graceful degradation works.

---

## Prompt 14 — Build Admin Dashboard

```
Build the admin dashboard based on:
- `/docs/requirements.md` → F13.1–F13.6 (Admin Dashboard)
- `/docs/planning.md` → Phase 5

Build `closetalk_frontend/` as a Flutter Web app (or React if preferred).

PAGES:

1. Login — admin auth separate from user auth

2. User Management — search users, view profile + devices + message count, disable/enable

3. Moderation Queue — flagged messages with content/sender/reason, actions: Approve/Remove/Ban, filter by reason/date/user, audit log

4. Analytics Dashboard — DAU/MAU chart (30d), messages/day, signups/day, retention cohort (D1/D7/D30), feature usage, active groups/channels/statuses

5. System Health — service status (up/down), latency charts (p50/p95/p99), error rate per service, DB pool usage, SQS queue depth

6. Feature Flag Console — list flags with current state, toggle on/off, rollout %, segment targeting (platform/region/user_id), kill switch

7. Audit Log Viewer — searchable admin action log, filter by admin/action/date

VERIFICATION:
- Login as admin → access all pages
- Flag → approve → message delivers
- Flag → remove → message deleted
- Ban user → user cannot log in
- Toggle feature flag → effect in app within 5s
- `flutter analyze` clean
```

**Verify:** All admin pages functional. Moderation and feature flags work correctly.

---

## Prompt 15 — Build Advanced Features (Polls, Stickers, Scheduling, Bookmarks)

```
Build advanced features from:
- `/docs/requirements.md` → F10.1–F10.8 (Advanced Messaging)

1. In-Chat Polls:
   - POST /polls — create { chat_id, question, options[], multiple_choice }
   - POST /polls/:id/vote — vote { option_index }
   - GET /polls/:id/results — live results
   - Storage: ScyllaDB
   - UI: Poll composer, inline bar chart

2. Stickers & GIFs:
   - Sticker packs: PNG/WebP with metadata
   - GIF search: Tenor/Giphy API (server-side proxy)
   - POST /stickers — upload custom sticker
   - UI: Sticker picker drawer, GIF search bar

3. Scheduled Messages:
   - POST /messages/schedule { chat_id, content, send_at }
   - GET /messages/scheduled — list
   - DELETE /messages/scheduled/:id — cancel
   - Lambda (cron): every minute, send due messages
   - UI: Calendar/time picker, "Scheduled" badge

4. Bookmarks:
   - POST /messages/:id/bookmark — bookmark
   - DELETE /messages/:id/bookmark — remove
   - GET /bookmarks — list across all chats
   - UI: Bookmark icon, bookmarks tab

VERIFICATION:
- Create poll → vote → live results update
- Search GIFs → send → appears in chat
- Schedule message → sends at correct time
- Bookmark → appears in bookmarks → syncs across devices
- `flutter analyze` clean
```

**Verify:** All four features work end-to-end. Polls live-update. Scheduled messages send on time.

---

## Prompt 16 — Build Voice & Video Calling (WebRTC)

```
Build calling based on:
- `/docs/requirements.md` → F9.1–F9.5 (Voice & Video)
- `/docs/architecture-flow.md` → call flow (transport protocol table)

BACKEND:
1. STUN/TURN: Coturn or AWS-provided
2. Signaling server (WebSocket):
   - POST /calls/offer — SDP offer { target_user_id, sdp }
   - POST /calls/answer — SDP answer { call_id, sdp }
   - POST /calls/ice-candidate — ICE { call_id, candidate }
   - POST /calls/end — end { call_id }
   - POST /calls/group — group call { participant_ids[] }
3. Store active calls in Valkey (TTL: call duration)
4. Push notification: incoming call (high priority)

FLUTTER:
1. `call_screen.dart` — full-screen call UI: local preview (PiP), remote video (full screen), mute/speaker/flip camera/end call buttons, audio-only mode
2. `incoming_call_screen.dart` — full-screen incoming call (even in background)
3. Call service: WebRTC peer connection, ICE handling, state machine, network reconnection
4. AI noise suppression: RNNoise or Bedrock on outgoing audio

VERIFICATION:
- User A calls B → B receives notification
- B answers → audio/video flows both ways
- Group call with 3+ works
- Mute, speaker, flip camera work
- Call persists on network reconnection
- `flutter analyze` clean
```

**Verify:** Two-way audio/video works. Group calls work. Incoming notification appears.

---

## Prompt 17 — Build Account Recovery & Email Integration

```
Build account recovery based on:
- `/docs/requirements.md` → F1.6–F1.7 (Recovery codes)
- `/docs/architecture-flow.md` → Diagram 13 (Account Recovery Flow)

IMPLEMENT:

1. Recovery codes at signup:
   - Generate 10 cryptographically random codes
   - Display ONCE (full-screen, force save)
   - Store SHA-256 hashes in PostgreSQL
   - Confirm: re-enter 2 random codes
   - Download as PDF + copy to clipboard

2. Recovery code verification:
   - POST /auth/recover { code }
   - Mark code used (one-time)
   - Return session token
   - Rate limit: 5 attempts/hr per user

3. Email recovery:
   - POST /auth/recover/email { email }
   - Send link via SES (expires 15 min)
   - POST /auth/recover/verify { token }
   - Rate limit: 1 email per 5 min

4. Trusted device recovery:
   - POST /auth/recover/trusted — request from trusted device
   - Push notification: "Someone is trying to recover your account"
   - User approves/rejects
   - If approved → session token

5. Recovery settings screen:
   - Show remaining code count (not actual codes)
   - Generate new codes (invalidates old)
   - Manage trusted devices
   - Update recovery email

VERIFICATION:
- Sign up → 10 codes displayed → download works
- Recover with code → marked used
- Same code again → rejected (one-time)
- Email recovery → link works within 15min, expires after
- Trusted device → push → approve → session granted
- `flutter analyze` clean
```

**Verify:** All three recovery methods work. Codes truly one-time. Email link expires.

---

## Prompt 18 — Build Infrastructure (Terraform + CI/CD + Monitoring)

```
Build infrastructure based on:
- `/docs/architecture.md` → Deployment, Scalability Path
- `/docs/architecture-flow.md` → Diagrams 7, 10
- `/docs/security.md` → Infrastructure Security, Monitoring

IMPLEMENT:

1. Terraform (`closetalk_backend/infrastructure/terraform/`):
   - VPC with public/private/data subnets across 3 AZs
   - ECS Fargate cluster with auto-scaling (CPU > 70% → scale out)
   - ALB with health checks
   - WebTransport Gateway (NLB with UDP for QUIC)
   - S3: media (lifecycle: standard → IA → glacier), backups, logs, audit
   - SQS FIFO: message-delivery, media-processing, moderation
   - SNS: push-notifications, system-alerts
   - CloudFront for media + static assets
   - AWS WAF with OWASP Top 10
   - IAM roles (least privilege)
   - Security groups (minimal ingress/egress)

2. CI/CD (`.github/workflows/`):
   - ci.yml: on PR → lint → test → build → scan
   - cd-staging.yml: on push to main → deploy to staging
   - cd-production.yml: on tag → deploy to production (manual approval)

3. Monitoring:
   - CloudWatch dashboards: health, latency, error rates, cost
   - Structured JSON logging
   - X-Ray distributed tracing
   - Alarms: latency, error rate > 2%, SQS DLQ, cost anomaly
   - Synthetic monitoring: ping every minute from 3 regions, full send/receive test every 5 min

4. Disaster Recovery:
   - Multi-AZ (failover < 1s)
   - Cross-region backup: S3 replication + Neon branching
   - Runbook for AZ failure, region failure, DB corruption, security breach

VERIFICATION:
- `terraform plan` succeeds
- `terraform apply` provisions resources
- CI/CD workflows are valid YAML
- Two browser tabs send messages through deployed infra
```

**Verify:** Terraform plan succeeds. CI/CD workflows valid. Infrastructure deploys.

---

## Prompt 19 — Security Audit + Load Testing + Hardening

```
Run security and performance validation based on:
- `/docs/security.md` — full guide
- `/docs/requirements.md` → N1.1–N1.10, N4.1–N4.10
- `/docs/architecture-flow.md` → Diagrams 17, 19

IMPLEMENT:

1. Security Hardening:
   - Flutter: `--obfuscate` + `--split-debug-info`
   - Flutter: certificate pinning
   - Flutter: `safe_device` for root/jailbreak detection
   - Backend: rate limiting headers on all responses
   - Backend: JSON Schema validation on all inputs
   - Backend: `Idempotency-Key` on POST /messages
   - Database: RLS penetration test queries
   - Database: audit logging (pgaudit + ScyllaDB audit)
   - Infra: verify Security Groups (no 0.0.0.0/0 except ALB)
   - Run `npm audit` / `go list -m all` / `flutter pub outdated` — fix vulns

2. Graceful Degradation Tests:
   - Kill moderation → messages deliver (pass-through)
   - Kill database → read-only mode
   - Kill search → basic text search still works
   - Kill WebTransport → WebSocket fallback
   - No cascading failures

3. Load Testing (k6 scripts):
   ```javascript
   export let options = {
     stages: [
       { duration: '2m', target: 100 },
       { duration: '5m', target: 100 },
       { duration: '2m', target: 500 },
       { duration: '5m', target: 500 },
       { duration: '2m', target: 0 },
     ],
     thresholds: {
       http_req_duration: ['p(95)<200', 'p(99)<500'],
       http_req_failed: ['rate<0.01'],
     },
   };
   ```
   - 500 concurrent users sending messages
   - 10,000 simultaneous WebTransport connections
   - 50,000 messages in 5 minutes
   - Record p50/p95/p99

4. Feature Flag Verification:
   - Toggle off → feature disappears within 5s
   - Rollout 50% → 50% of users see feature
   - Kill switch → instant disable
   - < 1ms per flag check

REPORT: Security findings, performance numbers, degradation scenarios, flag scenarios.
```

**Verify:** All hardening applied. Graceful degradation works. Load test passes thresholds.

---

## Prompt 20 — App Store Preparation & Production Readiness

```
Prepare for production launch based on:
- `/docs/security.md` → PlayStore & App Store Compliance
- `/docs/product-vision.md` → Success Metrics
- `/docs/planning.md` → Phase 7

CHECKLIST:

1. Google Play Store:
   - Privacy Policy (/privacy on website)
   - Data Safety section: account info, messages, contacts (hashed), device ID
   - App icon (512x512) + feature graphic (1024x500)
   - Screenshots (2-8 per device type)
   - Description (short 80 chars, full 4000 chars)
   - Category: Communication, Rating: Teen
   - Play App Signing
   - Internal → Closed → Open testing tracks
   - India: upload to MeitY portal

2. Apple App Store:
   - Privacy Nutrition Labels
   - Sign in with Apple (mandatory with other social logins)
   - Screenshots (6.5" iPhone + 5.5" iPhone + 12.9" iPad)
   - Age rating: 12+
   - Export Compliance: TLS 1.3 (ERN application)
   - TestFlight (10,000 testers)

3. Both Stores:
   - Privacy Policy URL ✅
   - Terms of Service ✅
   - Support email ✅
   - In-app account deletion ✅
   - In-app user reporting ✅

4. Production Readiness:
   - All P0 requirements complete
   - All P1 for MVP complete
   - `flutter test` — all pass
   - `flutter analyze` — zero issues
   - `flutter build --release` — all platforms succeed
   - Final security scan
   - Load test thresholds met (p95 < 200ms, p99 < 500ms)
   - DR drill: kill primary region → failover < 15 min
   - Monitoring dashboards healthy

5. Launch Plan:
   - Alpha: 100 internal testers (Week 1)
   - Closed Beta: 1,000 users (Week 2-3)
   - Open Beta: 10,000 users (Week 4-6)
   - Production launch (Week 8)
   - Post-launch: monitor crash rates, latency, support tickets daily
```

**Verify:** All checklists complete. Release builds succeed. Store metadata ready to submit.
