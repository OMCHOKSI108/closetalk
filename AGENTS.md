# CloseTalk — AGENTS.md (VibeCoding Prompts)

> **For developers using AI agents to build this project.** These 20 prompts are ordered, cumulative, and designed so each one checks the previous prompt's output before proceeding. Each prompt includes context, requirements from the docs, and verification steps.

---

## How to Use This File

1. **Follow the prompts in order** — each builds on the last
2. **Copy-paste the full prompt** to your AI coding agent (Cursor, Claude, Copilot, etc.)
3. **After each prompt completes**, verify the agent's output before moving to the next
4. **If the agent fails or produces bad code**, use the recovery prompt in each step before retrying

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

**Verify:** Agent should output a clear summary confirming it understands all 5 docs. If it misses anything, ask: "You missed [X]. Re-read [filename] and update your summary."

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

**Verify:** `flutter pub get` succeeds, `flutter analyze` is clean, directory structure matches PROJECT.md.  
**Recovery:** "`flutter analyze` shows [N] errors. Fix each one in order. Report before/after for each fix."

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
6. POST /devices/link — link a new device with QR code flow (from multi-device-sync.md)
7. POST /devices/revoke — revoke a device by ID, force-close its connections
8. GET /devices — list all active devices for the current user

In-memory storage for now (we'll connect databases later). Use proper JWT signing with RS256.

FLUTTER (closetalk_app/lib/):

1. Auth screens: login_screen.dart, register_screen.dart, recovery_screen.dart
2. auth_service.dart — API client calling the backend
3. auth_provider.dart — Riverpod state management for auth
4. Secure token storage using flutter_secure_storage
5. Auto-login on app start (check stored token, refresh if expired)
6. Account recovery flow (recovery codes from F1.6)

VERIFICATION:
- `flutter analyze` must be clean
- Backend server must start and respond to POST /auth/register with valid JWT
- Show me: curl example of register + login + device link flow

CRITICAL: Recovery codes MUST be 10 one-time codes. Display them ONCE at signup. This fixes WhatsApp's account recovery problem.
```

**Verify:** Backend starts, curl register + login returns JWT, flutter analyze clean.  
**Recovery:** "Backend returns 500 on POST /auth/register. Check the error logs and fix the handler."

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

3. Message model: id, chat_id, sender_id, content, content_type (text/image/file/voice),
   status (sending/sent/delivered/read), created_at, edited_at, reply_to_id

4. Message status tracking: sent → delivered → read (tick marks)

FLUTTER:
1. `webtransport_service.dart` — WebTransport client with:
   - Connect with JWT, auto-reconnect with 0-RTT
   - Send stream for messages
   - Send datagram for typing/presence
   - Receive stream for incoming messages
   - Fallback to SSE, then WebSocket if WebTransport fails

2. `chat_screen.dart` — message list with:
   - Scroll-to-bottom on new message
   - Message bubbles (sent vs received styling)
   - Typing indicator
   - Reply preview (swipe to reply)
   - Emoji reaction picker (long-press)
   - Status ticks (sending→sent→delivered→read)

3. `chat_provider.dart` — state management:
   - Message list with pull-to-refresh for history
   - Optimistic UI (show message immediately, update tick on server ACK)
   - Offline queue (save unsent messages locally, send on reconnect)

VERIFICATION:
- Send a message from one client → appears on another client in < 50ms
- Typing indicator appears in < 20ms via datagram
- Optimistic UI works (message shows immediately before server ACK)
- `flutter analyze` clean

CRITICAL: This fixes WhatsApp's TCP head-of-line blocking problem. WebTransport over QUIC is the PRIMARY transport. WebSocket is only a fallback. Test the fallback path explicitly.
```

**Verify:** Two browser tabs can send/receive messages in real-time. Typing indicators appear instantly.  
**Recovery:** "Messages are delivered but typing indicators don't appear. Check the WebTransport datagram handler — it should NOT use reliable streams for ephemeral data."

---

## Prompt 5 — Connect Databases (Neon PostgreSQL + ScyllaDB + Valkey)

```
Now connect the real databases based on:
- `/docs/architecture.md` → Polyglot Persistence section
- `/docs/requirements.md` → N2.1–N2.5 (Scalability)
- `/docs/architecture-flow.md` → Diagram 6 (Database Architecture)

IMPLEMENT:

1. **Neon PostgreSQL (Users, Groups, Metadata)**:
   - Create schema: users, groups, group_members, contacts, user_devices, conversations
   - Enable Row Level Security (RLS) on all tables
   - Create RLS policies: user can only SELECT/INSERT rows where they are a participant
   - Migration scripts in `closetalk_backend/infrastructure/migrations/`
   - Connect auth-service to PostgreSQL (replace in-memory storage)

2. **ScyllaDB Cloud (Messages)**:
   - Create keyspace and tables: messages, message_reads, message_reactions
   - Primary key design: chat_id as partition key, created_at as clustering key
   - Alternator API (DynamoDB-compatible) for the connection
   - Connect message-service to ScyllaDB (replace in-memory storage)
   - Implement pagination: SELECT WHERE chat_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT 50

3. **Valkey 8.1 (Session, Presence, Cache)**:
   - Connect auth-service to Valkey for session storage
   - Store: refresh tokens, device sessions, rate limit counters
   - TTLs: sessions 7d, rate limits 1min, presence 30s
   - Pub/sub for presence broadcasting

4. **Connection pooling**:
   - PgBouncer for PostgreSQL
   - Valkey connection pool
   - ScyllaDB driver connection pool

VERIFICATION:
- All services start and connect to their databases
- Register user → stored in PostgreSQL
- Send message → stored in ScyllaDB, retrievable via paginated query
- Session → stored in Valkey with correct TTL
- `docker-compose up` starts all services without errors

CRITICAL ERROR TO AVOID: Do NOT use the same database for everything. Messages go to ScyllaDB, metadata goes to PostgreSQL, sessions go to Valkey. If you mix them, stop and fix.
```

**Verify:** All three databases connect and store/retrieve data correctly.  
**Recovery:** "The message query is slow. Check the ScyllaDB partition key — it should be chat_id, not message_id. Fix and re-test."

---

## Prompt 6 — Build Group Chat System

```
Build group chats based on:
- `/docs/requirements.md` → F5.1–F5.8 (Group Chats)
- `/docs/architecture-flow.md` → Diagram 6 (Database ERD shows Group + GroupMember tables)

BACKEND:
1. POST /groups — create group { name, description, avatar, member_ids[] }
2. POST /groups/:id/invite — generate shareable invite link with expiry
3. POST /groups/join — join via invite link { code }
4. POST /groups/:id/members — add members (admin only)
5. DELETE /groups/:id/members/:user_id — remove member (admin only)
6. PUT /groups/:id/members/:user_id/role — promote/demote admin
7. POST /groups/:id/leave — leave group
8. PUT /groups/:id/settings — update group settings (name, avatar, retention, disappearing)
9. POST /groups/:id/pin — pin a message
10. GET /groups/:id/messages — paginated group message history

FLUTTER:
1. `group_create_screen.dart` — create group with member picker
2. `group_info_screen.dart` — group settings, member list, admin tools
3. `invite_link_screen.dart` — share invite link with QR code
4. `group_settings_sheet.dart` — retention, disappearing messages, pinned messages

DATABASE:
- Update Neon PostgreSQL: groups table, group_members table, conversation type = 'group'
- RLS policies: group members can read group messages; non-members cannot

VERIFICATION:
- Create a group → invite link works → members can send/receive in group
- Non-members cannot access group messages (RLS enforced)
- Admin can remove member → removed member can no longer access group
- `flutter analyze` clean

CRITICAL: Group access control. A non-member must NEVER be able to read group messages. RLS at the database level is the last defense — test this explicitly.
```

**Verify:** Test group creation, invite link joining, admin removal, and RLS enforcement.  
**Recovery:** "Non-members can still read group messages. Check the RLS policy — it must check group_members table, not just the messages table."

---

## Prompt 7 — Build Multi-Device Sync

```
Build native multi-device sync based on:
- `/docs/multi-device-sync.md` — full protocol specification
- `/docs/requirements.md` → F4.1–F4.6 (Multi-Device Sync)
- `/docs/architecture-flow.md` → Device Lifecycle sequence diagrams

IMPLEMENT:

BACKEND:
1. POST /devices/link — QR code flow (Prompt 3's logic, but now with full history sync)
2. GET /sync/messages?after={message_id} — incremental sync endpoint
   - Returns messages in ALL chats where the user is a participant
   - Batched: 50 messages per page, cursor-based pagination
   - Ordered by created_at ascending (oldest unseen first)
3. Server-side fan-out: when a message arrives, push to ALL linked devices of the recipient
4. GET /sync/status?after={timestamp} — sync status/stories too
5. DELETE /devices/:id — revoke device, close all active connections

FLUTTER:
1. `device_link_screen.dart` — QR code scanner for linking (on new device)
2. `device_management_screen.dart` — list linked devices, revoke from here
3. `sync_service.dart` — manages message sync state:
   - On app start: check if messages are behind, trigger catch-up sync
   - On reconnect: request sync from last known message_id
   - Progress indicator during large syncs
4. Apply exponential backoff for large backlogs:
   - < 100 msgs → deliver all immediately
   - 100-1000 msgs → deliver in 50-msg batches with 100ms gap
   - > 1000 msgs → deliver first 500, rest on demand with "Load older" button

STATE MANAGEMENT:
- Track `last_synced_message_id` per chat in local storage
- Avoid duplicate messages (idempotency by message_id)

VERIFICATION:
- Link a new device → see complete message history
- Send message on phone → appears on desktop in < 100ms
- Revoke device → device is logged out and cannot receive messages
- Device comes back online after 2 days → catch-up sync works with batching
- `flutter analyze` clean

CRITICAL DIFFERENCE FROM WHATSAPP: Phone is NOT required as a relay. Each device connects independently with its own WebTransport session and JWT. Test this: turn off the phone → desktop should still work independently.
```

**Verify:** Kill phone process → desktop still sends/receives. Link new device → full history syncs.  
**Recovery:** "New device doesn't receive old messages. Check GET /sync/messages — it should query ScyllaDB for messages in ALL chats where the user is a member, not just recent ones."

---

## Prompt 8 — Build Media Pipeline (Presigned URLs + Async Processing)

```
Build the media pipeline based on:
- `/docs/architecture-flow.md` → Diagram 11 (Media Upload & Processing)
- `/docs/architecture.md` → Key Decision #7 (Direct Media Upload)
- `/docs/requirements.md` → F3.2 (Media sharing)

BACKEND:
1. POST /media/upload-url — generate presigned S3 PUT URL { file_type, file_size, chat_id }
   - Validate: max file size (100MB), allowed types (image/jpeg, image/png, video/mp4, audio/opus, etc.)
   - Return: upload_url (expires 5min), media_id, cdn_url
2. POST /media/confirm — confirm upload complete { media_id, etag }
3. Lambda (async) on S3 ObjectCreated:
   - Virus scan with ClamAV → quarantine if infected
   - Image: generate thumbnails (100x100, 400x400, 1200x1200), convert to WebP/AVIF
   - Video: transcode to HLS (1080p, 720p, 480p)
   - Voice note: optimize to Opus
   - Update status to "ready", cache thumbnail URLs in Valkey (TTL: 1hr)
4. GET /media/:media_id — serve via CloudFront (signed URL for private media)

FLUTTER:
1. `media_picker.dart` — image picker, camera capture, file picker, voice recorder
2. Upload flow:
   - Request presigned URL from media service
   - Upload directly to S3 (show progress bar)
   - Confirm upload, then send message with media_id
   - Show thumbnail immediately (optimistic), replace with full-quality when processing done
3. `media_viewer.dart` — full-screen image/video viewer
4. Voice message UI: hold-to-record, release-to-send, waveform visualization

CRITICAL: Server NEVER touches raw media bytes. Upload goes directly Client → S3. This fixes WhatsApp's media quality loss problem. The server only manages metadata and triggers async processing.

VERIFICATION:
- Upload an image → presigned URL generated → file uploaded to S3 → thumbnail generated → message sent with thumbnail
- Upload a video → HLS transcoding works in background
- Upload a malware test file → virus scan detects and quarantines
- `flutter analyze` clean
```

**Verify:** Full upload flow works end-to-end. Media appears with correct thumbnail. Original quality preserved.  
**Recovery:** "Images are uploading but thumbnails aren't being generated. Check the Lambda trigger on S3 ObjectCreated events and the thumbnail generation code."

---

## Prompt 9 — Build Full-Text Search

```
Build search based on:
- `/docs/architecture-flow.md` → Diagram 14 (Full-Text Search)
- `/docs/requirements.md` → F3.8 (Message search)

BACKEND:
1. Create `search-service/` with Elasticsearch:
   - Index messages on create (listen to SQS for message events)
   - Index mapping: message_id, chat_id, sender_id, content (text), created_at, content_type, chat_name, sender_name
   - Index lifecycle: hot (7d), warm (30d), cold (90d+)

2. GET /search?q={query}&chat_id={optional}&from={date}&to={date}&sender={user_id}&page=1
   - Full-text search with relevance scoring
   - Filters: date range, specific chat, specific sender, media type
   - Highlights: return matching snippets with <em> tags
   - Cursor-based pagination
   - Rate limited: 30 queries per user per minute

3. Backfill: Lambda to batch-index all existing messages from ScyllaDB

FLUTTER:
1. `search_screen.dart`:
   - Search bar at top with debounce (300ms)
   - Results grouped by chat, sorted by relevance
   - Each result shows: snippet with highlight, chat name, sender, timestamp
   - Filter chips: date, sender, chat, media type
   - Tap result → navigate to exact message in chat (scroll-to-message)

2. Cache recent searches in local storage (last 20)

VERIFICATION:
- Send messages with specific keywords → search finds them with relevance ranking
- Filters work: by date, by sender, by chat
- Search across 10,000 messages returns in < 500ms
- `flutter analyze` clean
```

**Verify:** Search returns correct results with highlights. Filters narrow results. Performance < 500ms.  
**Recovery:** "Search is returning results from chats the user doesn't belong to. Add a filter: only index/show messages where the user is a chat participant."

---

## Prompt 10 — Build Privacy Controls & Contact Discovery

```
Build privacy controls based on:
- `/docs/requirements.md` → F2.1–F2.7 (Contact Discovery & Privacy)
- `/docs/architecture-flow.md` → Diagram 12 (Privacy-Preserving Contact Discovery)
- `/docs/whatsapp-gap-analysis.md` → Fix #5 (no raw contacts uploaded)

BACKEND:
1. POST /contacts/discover — privacy-preserving contact discovery
   - Input: array of SHA-256 hashed phone numbers
   - Output: matched user_ids + display_names + avatar_urls (no raw phone numbers)
   - Server NEVER stores or logs the raw hashes
   - Cache results in Valkey (TTL: 24hr)

2. User privacy settings (store in PostgreSQL user_settings table):
   - last_seen_visibility: nobody | everyone | contacts | contacts_except
   - profile_photo_visibility: nobody | everyone | contacts
   - read_receipts: boolean (global) + per_chat_overrides (JSONB)
   - group_add_permission: everyone | contacts | contacts_except
   - status_privacy: contacts | close_friends | public

3. Block/unblock:
   - POST /blocks/:user_id — block user
   - DELETE /blocks/:user_id — unblock user
   - Blocked user cannot: send messages, see last_seen, see profile photo, see status
   - Block list syncs across all devices

4. Enforce all privacy settings at the API layer AND database layer

FLUTTER:
1. `privacy_settings_screen.dart` — all privacy toggles
2. `block_list_screen.dart` — view/manage blocked users
3. `contact_discovery_screen.dart` — find contacts (with phone permission flow)
4. Enforce visibility on UI:
   - Hide last_seen based on user's setting
   - Hide profile photo based on setting
   - Show/hide read receipts per chat

CRITICAL: This fixes WhatsApp's biggest privacy problem. The server must NEVER see raw phone numbers. Hash-based discovery only.

VERIFICATION:
- Register two users → discover each other via hashed phone numbers
- Set last_seen to "nobody" → other users see "Last seen recently" only
- Block a user → blocked user cannot send messages
- `flutter analyze` clean
```

**Verify:** Contact discovery works without exposing raw numbers. All privacy settings enforced correctly.  
**Recovery:** "Blocked user can still send messages. Check the message service — it must check the blocks table before delivering, not just block the UI."

---

## Prompt 11 — Build Stories / Status

```
Build Stories/Status based on:
- `/docs/requirements.md` → F7.1–F7.6 (Stories / Status)
- `/docs/architecture-flow.md` → Diagram 15 (Stories / Status Flow)

BACKEND:
1. POST /status — create status { type: "image|video|text", content/media_id, privacy }
2. GET /status/updates — get status updates from contacts (sorted by most recent)
3. GET /status/:id/views — who viewed my status
4. POST /status/:id/view — mark as viewed { viewer_id }
5. POST /status/:id/reply — reply to status via DM
6. Lambda (hourly): delete expired statuses (created_at > 24h)

Storage: ScyllaDB (statuses table, status_views table)
- statuses: PK (user_id, created_at), TTL: 24h at DB level
- status_views: PK (status_id, viewer_id)

FLUTTER:
1. `status_list_screen.dart` — horizontal scroll of contact statuses (top of chat list)
   - Show all available statuses from contacts
   - My status at top (tap to add)
   - Muted contacts shown dimmed
2. `status_viewer_screen.dart` — tap-through status viewer
   - Auto-advance to next status after 5s
   - Tap left/right half to go prev/next
   - Swipe down to close
   - Show view count
3. `status_creator_screen.dart` — camera/gallery picker, text overlay, emoji, privacy selector
4. `status_privacy_screen.dart` — close friends list management

VERIFICATION:
- Post a status → appears in contacts' status list
- View a status → poster can see who viewed
- After 24h → status auto-deletes
- Privacy: "Close Friends" only visible to selected contacts
- `flutter analyze` clean
```

**Verify:** Status creation, viewing, view tracking, and auto-expiry all work.  
**Recovery:** "Status doesn't auto-delete after 24h. Check the Lambda cleanup function — it should compare expires_at timestamp, not created_at + 24h in code."

---

## Prompt 12 — Build Broadcast & Channels

```
Build Broadcast/Channels based on:
- `/docs/requirements.md` → F8.1–F8.5 (Broadcast & Channels)
- `/docs/architecture-flow.md` → Diagram 16 (Broadcast & Channels Flow)

BACKEND:
1. Broadcast lists:
   - POST /broadcasts — create broadcast list { name, member_ids[] }
   - POST /broadcasts/:id/send — send message to all members (each receives as DM)
   - GET /broadcasts — list my broadcast lists

2. Channels:
   - POST /channels — create channel { name, description, avatar, is_public }
   - POST /channels/:id/subscribe — subscribe to channel
   - POST /channels/:id/unsubscribe — unsubscribe
   - POST /channels/:id/messages — send channel message (admin only)
   - GET /channels/:id/messages — paginated channel messages
   - GET /channels/:id/subscribers — subscriber count + list (admin only)
   - GET /channels/discover — discover public channels

3. Fan-out for channels:
   - When admin sends to channel, push notification to ALL subscribers via SNS
   - Use SQS FIFO for ordered delivery (group_id = channel_id)

FLUTTER:
1. `broadcast_list_screen.dart` — create/manage broadcast lists
2. `channel_discover_screen.dart` — discover and subscribe to channels
3. `channel_screen.dart` — channel messages (read-only for subscribers)
4. `channel_admin_screen.dart` — subscriber list, analytics (admin only)

VERIFICATION:
- Create broadcast list → send message → all recipients receive as DM
- Create channel → subscribe → admin sends message → all subscribers receive
- `flutter analyze` clean
```

**Verify:** Broadcast sends individual DMs. Channel broadcasts to all subscribers.  
**Recovery:** "Channel messages are showing in the DM inbox. Channel messages should be in a separate ChannelMessages table, not the Messages table."

---

## Prompt 13 — Build AI Integration (Moderation + Assistant + Translation)

```
Build AI features based on:
- `/docs/architecture.md` → AI Infrastructure section
- `/docs/architecture-flow.md` → Diagram 5 (Content Moderation Pipeline)
- `/docs/requirements.md` → F11.1–F11.5 (Moderation), F12.1–F12.4 (AI Assistant)
- `/docs/security.md` → AI & Agent Security section

IMPLEMENT:

1. Content Moderation Pipeline:
   - Message → SQS FIFO → Lambda → Bedrock Guardrails (Claude 3.5 Haiku)
   - Natural-language policies: block hate speech, PII, harassment, spam
   - Passed: deliver message. Flagged: quarantine for human review.
   - GRACEFUL DEGRADATION: If Bedrock is down → pass-through mode with deferred scanning
   - Log all moderation actions to S3 for audit

2. AI Chat Assistant:
   - POST /ai/ask — ask assistant a question { question, chat_context? }
   - Bedrock AgentCore with episodic memory (per-user, never cross-tenant)
   - Memory persistence: remember user preferences, past questions
   - Rate limited: 10 calls per user per minute

3. Inline Message Translation:
   - POST /translate — translate message { message_id, target_language }
   - Auto-detect source language
   - Return translated text + detected source language
   - Cache translations in Valkey (TTL: 24hr)

4. Group Summaries:
   - POST /groups/:id/summarize — generate AI summary of recent messages
   - Scheduled Lambda: daily digest for active groups

FLUTTER:
1. Moderation: show "Message under review" for flagged content (don't block UI)
2. AI Assistant: dedicated chat screen or inline floating button
3. Translation: tap any message → "Translate" option in context menu
4. Group Summary: "View summary" button at top of group chat

CRITICAL: AI features must NEVER fail the core messaging experience. If AI is down:
- Moderation → pass-through (defer scanning)
- Translation → hide translate button
- Assistant → show "unavailable" message
This is non-negotiable.

VERIFICATION:
- Send a message with hate speech → flagged and quarantined
- Ask AI assistant a question → response with context memory
- Translate a message → correct translation returned
- Kill Bedrock API → messages still deliver (pass-through mode activates)
- `flutter analyze` clean
```

**Verify:** Moderation catches bad content. AI assistant remembers context. Translation works. Graceful degradation works.  
**Recovery:** "When Bedrock is down, messages are being rejected instead of passing through. Remove the hard error — catch Bedrock exceptions and set moderation_status to 'deferred' instead of failing."

---

## Prompt 14 — Build Admin Dashboard

```
Build the admin dashboard based on:
- `/docs/requirements.md` → F13.1–F13.6 (Admin Dashboard)
- `/docs/planning.md` → Phase 5 (Admin Dashboard & Operations)

Build `closetalk_frontend/` as a Flutter Web app (or React if you prefer).

PAGES:

1. Login (admin auth, separate from user auth):
   - Admin credentials or SSO (Google Workspace)

2. User Management:
   - Search users by name, email, phone, user_id
   - View user profile, active devices, message count, registration date
   - Disable/enable user account
   - View user's recent messages (privacy: only for moderation purposes)

3. Moderation Queue:
   - List flagged messages with: content, sender, chat, timestamp, flag reason
   - Actions: Approve (deliver message), Remove (delete message), Ban User
   - Filter by: flag reason, date range, user
   - Audit log: all actions logged with admin identity and timestamp

4. Analytics Dashboard:
   - DAU/MAU chart (last 30 days)
   - Messages per day chart
   - New signups per day
   - Retention cohort analysis (D1, D7, D30)
   - Top features by usage
   - Active groups count, channels count, statuses posted

5. System Health:
   - Service status (up/down) for all microservices
   - Latency charts (p50, p95, p99) per endpoint
   - Error rate per service
   - Database connection pool usage
   - SQS queue depth

6. Feature Flag Console:
   - List all feature flags with current state
   - Toggle on/off per flag
   - Set rollout percentage
   - Segment targeting: platform, region, user_id range
   - Kill switch (instant disable)

7. Audit Log Viewer:
   - Searchable log of all admin actions
   - Filter by: admin user, action type, date range

VERIFICATION:
- Login as admin → access all pages
- Flag a message via moderation → approve → message delivers
- Flag a different message → remove → message deleted
- Ban a user → user cannot log in
- Toggle a feature flag → effect visible in app within 5s
- `flutter analyze` clean (or npm run build for React)
```

**Verify:** All admin pages functional. Moderation actions reflected in app. Feature flags toggle correctly.  
**Recovery:** "Feature flag changes aren't reflected in the app. Check the Valkey TTL — flags should have a 5-second cache, not 5 minutes."

---

## Prompt 15 — Build Remaining Features (Polls, Stickers, Scheduling, Bookmarks)

```
Build advanced features based on:
- `/docs/requirements.md` → F10.1–F10.8 (Advanced Messaging)

IMPLEMENT EACH FEATURE:

1. **In-Chat Polls**:
   - POST /polls — create poll { chat_id, question, options[], multiple_choice }
   - POST /polls/:id/vote — vote { option_index }
   - GET /polls/:id/results — get live results
   - Storage: ScyllaDB (polls table)
   - UI: Poll composer, inline poll display with live bar chart

2. **Stickers & GIFs**:
   - Sticker packs: bundle of PNG/WebP images with metadata
   - GIF search: Tenor/Giphy API integration (server-side proxy with API key)
   - POST /stickers — upload custom sticker
   - UI: sticker picker drawer, GIF search bar, trending GIFs

3. **Scheduled Messages**:
   - POST /messages/schedule — schedule message { chat_id, content, send_at }
   - GET /messages/scheduled — list scheduled messages
   - DELETE /messages/scheduled/:id — cancel scheduled message
   - Lambda (cron): every minute, check for due messages and send
   - UI: calendar/time picker, "Scheduled" badge on chat list

4. **Bookmarks**:
   - POST /messages/:id/bookmark — bookmark a message
   - DELETE /messages/:id/bookmark — remove bookmark
   - GET /bookmarks — list all bookmarks (across all chats)
   - UI: bookmark icon on message, bookmarks tab in search screen

VERIFICATION:
- Create a poll → vote → see live results update in real-time
- Search GIFs → send GIF → appears in chat
- Schedule a message → message sends at correct time
- Bookmark a message → appears in bookmarks list → syncs across devices
- `flutter analyze` clean
```

**Verify:** All four features work end-to-end. Poll results update live. Scheduled message sends on time.  
**Recovery:** "Scheduled message didn't send at the right time. Check the Lambda cron — it should run every 60 seconds and query messages WHERE send_at <= now() AND status = 'scheduled'."

---

## Prompt 16 — Build Voice & Video Calling (WebRTC)

```
Build calling based on:
- `/docs/requirements.md` → F9.1–F9.5 (Voice & Video)
- `/docs/architecture-flow.md` → the call flow (referenced in transport protocol table)

IMPLEMENT:

BACKEND:
1. STUN/TURN server configuration (use Coturn or AWS-provided):
   - STUN: free discovery (built into WebRTC)
   - TURN: Coturn server (or AWS TURN) for NAT traversal

2. Signaling server:
   - WebSocket endpoint for call signaling
   - POST /calls/offer — send SDP offer { target_user_id, sdp }
   - POST /calls/answer — send SDP answer { call_id, sdp }
   - POST /calls/ice-candidate — exchange ICE candidates { call_id, candidate }
   - POST /calls/end — end call { call_id }
   - POST /calls/group — create group call { participant_ids[] }

3. Store active calls in Valkey (TTL: duration of call)
4. Push notification: incoming call notification (must be high priority)

FLUTTER:
1. Call screens:
   - `call_screen.dart` — full-screen call UI with:
     - Local video preview (PiP)
     - Remote video (full screen)
     - Mute, speaker, flip camera, end call buttons
     - Audio-only mode (tap to switch)
   - `incoming_call_screen.dart` — full-screen incoming call UI (even when app is in background)

2. Call service:
   - WebRTC peer connection management
   - ICE candidate handling
   - Connection state machine (connecting → connected → disconnected)
   - Reconnection on network drop

3. AI noise suppression:
   - Use AWS Bedrock or RNNoise library for real-time noise suppression
   - Apply to outgoing audio stream before sending

VERIFICATION:
- User A calls User B → B receives incoming call notification
- B answers → audio/video flows both directions
- Group call with 3+ participants works
- Mute, speaker toggle, flip camera all work
- Call persists on network reconnection
- `flutter analyze` clean
```

**Verify:** Two-way audio/video works. Group calls work. Incoming call notification appears.  
**Recovery:** "Video call connects but no audio. Check the SDP offer/answer exchange — audio transceiver direction should be 'sendrecv', not 'sendonly'."

---

## Prompt 17 — Build Account Recovery & Email Integration

```
Build account recovery based on:
- `/docs/requirements.md` → F1.6–F1.7 (Recovery codes)
- `/docs/architecture-flow.md` → Diagram 13 (Account Recovery Flow)

IMPLEMENT:

1. Recovery codes at signup:
   - Generate 10 cryptographically random recovery codes
   - Display ONCE to user (full-screen, force save)
   - Store SHA-256 hashes in PostgreSQL
   - User must confirm: re-enter 2 random codes from the list
   - Provide download as PDF + copy to clipboard options

2. Recovery code verification:
   - POST /auth/recover — verify recovery code { code }
   - Mark code as used (one-time use)
   - Return session token
   - Rate limit: 5 attempts per hour per user

3. Email recovery:
   - POST /auth/recover/email { email }
   - Send recovery link via AWS SES (expires in 15 min)
   - Verify link at POST /auth/recover/verify { token }
   - Rate limit: 1 email per 5 minutes per user

4. Trusted device recovery:
   - POST /auth/recover/trusted — request recovery from trusted device
   - Push notification to trusted device: "Someone is trying to recover your account"
   - User approves/rejects on trusted device
   - If approved, new device gets session token

5. Recovery settings screen:
   - View remaining recovery codes (show count, not the actual codes)
   - Generate new codes (invalidates old ones)
   - Manage trusted devices
   - Update recovery email

VERIFICATION:
- Sign up → 10 recovery codes displayed → download works
- Log out → recover with a code → code marked as used
- Try same code again → rejected (one-time use)
- Recover via email → link works within 15min, expires after
- Recover via trusted device → push notification → approve → session granted
- `flutter analyze` clean
```

**Verify:** All three recovery methods work. Codes are truly one-time. Email link expires.  
**Recovery:** "Recovery code can be used twice. Check — you must mark the code as 'used' in the database immediately when it's validated, not after the session is created."

---

## Prompt 18 — Build Infrastructure (Terraform + CI/CD + Monitoring)

```
Build infrastructure based on:
- `/docs/architecture.md` → Deployment Architecture, Scalability Path
- `/docs/architecture-flow.md` → Diagram 7 (Deployment & CI/CD), Diagram 10 (Scaling)
- `/docs/security.md` → Infrastructure Security, Maintenance Plan, Monitoring

IMPLEMENT:

1. **Terraform** (`closetalk_backend/infrastructure/terraform/`):
   - VPC with public/private/data subnets across 3 AZs
   - ECS Fargate cluster with auto-scaling (CPU > 70% triggers scale-out)
   - Application Load Balancer with health checks
   - WebTransport Gateway (NLB with UDP support for QUIC)
   - S3 buckets: media (with lifecycle: standard → IA → glacier), backups, logs, audit
   - SQS FIFO queues: message-delivery, media-processing, moderation
   - SNS topics: push-notifications, system-alerts
   - CloudFront distribution for media + static assets
   - AWS WAF with OWASP Top 10 rules
   - IAM roles (least privilege) for all services
   - Security groups: minimal ingress/egress rules

2. **CI/CD** (`.github/workflows/`):
   - `ci.yml`: on PR — lint → test → build → scan
   - `cd-staging.yml`: on push to main — deploy to staging
   - `cd-production.yml`: on tag — deploy to production (manual approval)

3. **Monitoring**:
   - CloudWatch dashboards: service health, latency, error rates, cost
   - Structured JSON logging from all services
   - Distributed tracing with AWS X-Ray
   - Alarms: latency > threshold, error rate > 2%, SQS DLQ not empty, cost anomaly
   - Synthetic monitoring: ping every minute from 3 regions, full send/receive test every 5 min

4. **Disaster Recovery**:
   - Multi-AZ deployment (failure < 1s failover)
   - Cross-region backup: S3 replication + Neon branching
   - Runbook for: AZ failure, region failure, DB corruption, security breach

VERIFICATION:
- `terraform plan` succeeds without errors
- `terraform apply` provisions all resources
- CI/CD workflows are valid YAML
- Two browser tabs can send messages through the deployed infrastructure
```

**Verify:** Terraform plan succeeds. CI/CD workflows are valid. Infrastructure deploys correctly.  
**Recovery:** "Terraform plan shows 403 errors on S3 bucket policy. Fix the IAM roles — ECS task role needs s3:PutObject permission on the media bucket only, not all buckets."

---

## Prompt 19 — Security Audit + Load Testing + Hardening

```
Run security and performance validation based on:
- `/docs/security.md` — full security guide
- `/docs/requirements.md` → N1.1–N1.10 (Performance), N4.1–N4.10 (Security)
- `/docs/architecture-flow.md` → Diagram 17 (Graceful Degradation), Diagram 19 (Feature Flags)

IMPLEMENT:

1. **Security Hardening**:
   - Flutter: enable `--obfuscate` and `--split-debug-info` in release build
   - Flutter: add certificate pinning
   - Flutter: `safe_device` package for root/jailbreak detection
   - Backend: add rate limiting headers to all responses
   - Backend: validate ALL inputs with JSON Schema
   - Backend: add `Idempotency-Key` support on POST /messages
   - Database: verify RLS policies with penetration test queries
   - Database: enable audit logging (pgaudit + ScyllaDB audit)
   - Infra: verify Security Group rules (no 0.0.0.0/0 except ALB)
   - Run `npm audit` / `go list -m all` / `flutter pub outdated` — fix vulnerabilities

2. **Graceful Degradation Tests**:
   - Kill moderation service → messages still deliver (pass-through mode)
   - Kill database → read-only mode activates
   - Kill Elasticsearch → basic text search still works
   - Kill WebTransport → WebSocket fallback activates
   - Verify no cascading failures

3. **Load Testing** (k6 scripts in `closetalk_backend/tests/load/`):
   ```javascript
   // k6 script for message send
   import http from 'k6/http';
   export let options = {
     stages: [
       { duration: '2m', target: 100 },   // ramp up to 100 users
       { duration: '5m', target: 100 },   // stay at 100
       { duration: '2m', target: 500 },   // ramp to 500
       { duration: '5m', target: 500 },   // stay at 500
       { duration: '2m', target: 0 },     // ramp down
     ],
     thresholds: {
       http_req_duration: ['p(95)<200', 'p(99)<500'],
       http_req_failed: ['rate<0.01'],
     },
   };
   ```
   - Test: 500 concurrent users sending messages
   - Test: 10,000 simultaneous WebTransport connections
   - Test: 50,000 messages in 5 minutes
   - Record p50, p95, p99 latency for each

4. **Feature Flag System** (final verification):
   - Toggle a flag off → feature disappears from app within 5 seconds
   - Set rollout to 50% → 50% of users see the feature
   - Kill switch → instant disable across all users
   - No performance impact from flag evaluation (< 1ms per check)

REPORT:
- Security: findings and fixes applied
- Performance: p50/p95/p99 under load, any bottlenecks found
- Graceful degradation: all scenarios tested and passing
- Feature flags: all scenarios working
```

**Verify:** All security hardening applied. Graceful degradation works in every scenario. Load test passes thresholds.  
**Recovery:** "Load test fails at 500 users — p99 > 2000ms. Check database query performance. Likely missing index on messages.chat_id + messages.created_at."

---

## Prompt 20 — App Store Preparation & Production Readiness

```
Prepare for production launch based on:
- `/docs/security.md` → PlayStore & App Store Compliance section
- `/docs/product-vision.md` → Success Metrics
- `/docs/planning.md` → Phase 7 (Launch & Scale)

COMPLETE CHECKLIST:

1. **Google Play Store Preparation**:
   - Create Privacy Policy page (hosted at /privacy on website)
   - Complete Data Safety section: declare account info, messages, contacts (hashed), device ID
   - Create app icon (512x512 + 1024x500 feature graphic)
   - Create screenshots (2-8 per device type: phone 6.5", phone 5.5", tablet)
   - Write app description (short: 80 chars, full: 4000 chars)
   - Set category: Communication, content rating: Teen
   - Enable Play App Signing
   - Set up Internal → Closed → Open testing tracks
   - For India: upload to MeitY portal

2. **Apple App Store Preparation**:
   - Create Privacy Nutrition Labels in App Store Connect
   - Offer Sign in with Apple (mandatory if using other social logins)
   - Create screenshots (6.5" iPhone + 5.5" iPhone + 12.9" iPad)
   - Set age rating: 12+
   - Export Compliance: declare TLS 1.3 encryption (apply for ERN)
   - Set up TestFlight (up to 10,000 testers)

3. **Both Stores**:
   - Privacy Policy URL ✅
   - Terms of Service ✅
   - Support email ✅
   - In-app account deletion ✅
   - In-app user reporting ✅

4. **Production Readiness**:
   - Verify all P0 requirements are complete (from docs/requirements.md)
   - Verify all P1 requirements for MVP are complete
   - Run full `flutter test` — all tests pass
   - Run `flutter analyze` — zero issues
   - Run `flutter build --release` for all target platforms — builds succeed
   - Final security scan
   - Load test results meet thresholds (p95 < 200ms, p99 < 500ms)
   - Disaster recovery drill: kill primary region → failover works in < 15 min
   - Monitoring dashboards show all services healthy

5. **Launch Plan**:
   - Alpha: 100 internal testers (Week 1)
   - Closed Beta: 1,000 users (Week 2-3)
   - Open Beta: 10,000 users (Week 4-6)
   - Production launch (Week 8)
   - Post-launch: monitor crash rates, latency, support tickets daily

VERIFY AND REPORT:
- ✅ Store checklist complete for both platforms
- ✅ All P0 requirements pass
- ✅ Release builds succeed on all platforms
- ✅ Load tests pass
- ✅ DR drill passes
- ❌ Any missing items → list as blockers with action items
```

**Verify:** All checklists complete. Release builds succeed. Store metadata ready to submit.  
**Recovery:** "Release build fails for iOS. Check: `flutter build ios --release` — likely a code signing issue in the iOS Xcode project settings."

---

## Additional Utility Prompts

### U1 — Code Review with Doc Compliance

```
Review the code in [file_path] against the requirements in `/docs/requirements.md`.
Check:
1. Does the code implement the correct requirement ID?
2. Does it handle the edge cases mentioned in the requirement?
3. Does it follow the architecture in `/docs/architecture-flow.md`?
4. Are there any security issues from `/docs/security.md`?

Report: what it does right, what it misses, and exactly what to fix.
```

### U2 — Architecture Diagram Generation

```
I need to update `/docs/architecture-flow.md` with a new flow diagram for [feature].
Read the existing diagrams in that file for style reference.
Then create a new Mermaid [sequence/flowchart/state] diagram showing:
- [describe the flow]
- Use the same styling conventions as the existing diagrams
- Place it at the end of the file with proper heading numbering
```

### U3 — Cross-Cutting Concern Check

```
I changed [file A]. Check if this change affects:
1. Any other services in `/docs/architecture.md`
2. Any requirements in `/docs/requirements.md`
3. Any security measures in `/docs/security.md`
4. Any flows in `/docs/architecture-flow.md`
5. Any planning phases in `/docs/planning.md`

List every file/docs section that needs updating because of this change.
```

### U4 — Database Migration Generation

```
Read the current schema in `closetalk_backend/infrastructure/migrations/`.
I need to add [new table or column] for [feature].
Generate the migration:
1. ALTER TABLE or CREATE TABLE SQL (PostgreSQL-compatible for Neon)
2. RLS policy if needed
3. Index recommendation
4. Rollback script

Reference `/docs/architecture-flow.md` → Diagram 6 for database relationships.
```

### U5 — Flutter Performance Audit

```
Run a comprehensive performance audit on `closetalk_app/`:
1. Check for unnecessary rebuilds (use `const` constructors)
2. Check for large build methods (split into widgets)
3. Check for missing `const` in widget constructors
4. Check for expensive operations in `build()` methods
5. Check image sizes (are we loading full-res images in lists?)
6. Check for memory leaks (StreamSubscription not disposed)
7. Check for slow list performance (are we using ListView.builder?)

Report: specific files and lines with performance issues + fix recommendations.
```

### U6 — Progress Sync Report

```
Based on the completed requirements in `/docs/requirements.md` and the planning in `/docs/planning.md`:

1. Which P0 requirements are implemented? Which are not?
2. Which P1 requirements are implemented? Which are not?
3. What percentage of Phase 3 (Frontend Features) is complete?
4. What are the next 3 things to build?

Read the actual code in `closetalk_app/lib/` and `closetalk_backend/` to verify — don't assume based on docs.
```

### U7 — Error Recovery Debugger

```
I'm getting this error in [scenario]:
[error message]

Read these docs to understand the context:
- `/docs/architecture-flow.md` — find the relevant flow
- `/docs/architecture.md` — check service dependencies

1. What is the root cause?
2. What's the fix?
3. What tests should I add to prevent this from happening again?
4. Were there any assumptions in the code that don't match the documented architecture?
```

### U8 — Multi-Device Consistency Check

```
Reference `/docs/multi-device-sync.md` and check if [feature] properly handles multi-device:
1. Does it sync state to the server (not just local)?
2. Does the server fan-out to ALL linked devices?
3. What happens if a device is offline — is there a catch-up mechanism?
4. Is there any local-only state that should be server-backed?

Report: any multi-device bugs or missing sync logic.
```

### U9 — Dependency Audit

```
Run a full dependency audit:
1. flutter pub outdated — list all outdated packages with versions
2. npm audit / go list -u -m all — for backend
3. Check for deprecated packages
4. Check for packages with known CVEs
5. For each: is there a breaking change? What needs to be updated?

Reference `/docs/security.md` → Maintenance Plan for update strategy.
```

### U10 — PR Description Generator

```
I'm about to merge changes for [feature description]. Read:
- `/docs/requirements.md` — find the relevant requirement IDs
- `/docs/planning.md` — find the phase
- `/docs/product-vision.md` — find the user-facing description

Generate a PR description with:
1. Title: type(scope): description
2. Summary: what this PR does from a user perspective
3. Technical changes: what files were changed and why
4. Requirements closed: e.g., "Closes F3.1, F3.2"
5. Testing: how the change was tested
6. Screenshots: if UI changes
7. Risk: low/medium/high and why
```
