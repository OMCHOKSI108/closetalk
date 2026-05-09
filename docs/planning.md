# CloseTalk — Project Planning Checklist

## Phase 1: Foundation & Setup

- [ ] **Define project scope & goals**
  - Target: 100,000 registered users, 10,000 DAU
  - Platform: Mobile (Android/iOS), Web, Desktop (macOS/Linux/Windows)
  - Key differentiator: Fix every WhatsApp problem (see docs/whatsapp-gap-analysis.md)
  - Timeline: TBD

- [ ] **Set up monorepo structure**
  - `closetalk_app/` — Flutter frontend (existing)
  - `closetalk_backend/` — Backend services
  - `closetalk_frontend/` — Web admin dashboard
  - `docs/` — Documentation & architecture

- [ ] **Initialize Flutter app** ✅ Done
  - Multi-platform: Android, iOS, macOS, Linux, Windows, Web
  - Default counter app scaffold (to be replaced)

- [ ] **Set up version control** ✅ Done
  - Git repo initialized
  - Pushed to GitHub: `OMCHOKSI108/closetalk`
  - `.gitignore` configured

- [ ] **Configure CI/CD pipeline**
  - GitHub Actions for lint, test, build
  - Flutter analyze on PR
  - Automated mobile builds (optional)

- [ ] **Set up feature flag system**
  - Gradual rollout mechanism
  - Kill switches for each feature
  - A/B testing support

## Phase 2: Backend Infrastructure

### Compute Layer

- [ ] **Choose backend runtime**
  - Option A: Node.js 25 (async I/O, large ecosystem)
  - Option B: Go 1.26 (performance, low memory)
  - Decision: __B__

- [ ] **Set up container orchestration**
  - AWS ECS Fargate (Graviton5 instances)
  - Dockerfile + docker-compose for local dev
  - Auto-scaling with circuit breakers for graceful degradation

- [ ] **Configure API Gateway**
  - REST endpoints for CRUD operations
  - WebSocket/WebTransport endpoints for real-time

- [ ] **Implement circuit breakers & graceful degradation**
  - Fallback when AI moderation is down (pass-through mode)
  - Read-only mode when database is degraded
  - Local-first message queue when offline

### Database Layer

- [ ] **Set up Neon Serverless PostgreSQL**
  - User accounts, group metadata, settings
  - Row Level Security for multi-tenancy
  - Database branching for dev/staging

- [ ] **Set up ScyllaDB Cloud**
  - Message history (high-volume writes)
  - Alternator API (DynamoDB-compatible)
  - Partition key design for chat rooms (hot partition handling)

- [ ] **Set up Valkey 8.1 (ElastiCache)**
  - Session management
  - Presence/status tracking
  - Pub/sub for real-time events

- [ ] **Set up Elasticsearch (or OpenSearch)**
  - Full-text search index for messages
  - Search across all chats with filters (date, sender, chat)
  - Incremental indexing pipeline

### Real-Time Transport

- [ ] **Implement WebTransport endpoint**
  - Interactive states (typing, presence)
  - Unreliable datagrams for ephemeral data
  - 0-RTT handshake for reconnections

- [ ] **Implement SSE over HTTP/3**
  - Standard message delivery
  - Fallback: WebSocket for legacy support

- [ ] **Implement WebSocket fallback**
  - Universal reachability
  - Graceful degradation

### Media Pipeline

- [ ] **Set up presigned URL upload flow**
  - Client requests upload URL from Media Service
  - Client uploads directly to S3
  - Server never touches raw media bytes

- [ ] **Set up async media processing**
  - Lambda triggered on S3 upload
  - Thumbnail generation (multiple sizes)
  - Image compression (WebP/AVIF)
  - Video transcoding (HLS/DASH)
  - Voice note optimization (Opus)
  - Virus/malware scanning

- [ ] **Set up CDN delivery**
  - CloudFront distribution for media
  - Cache invalidation on new uploads
  - Signed URLs for private media

- [ ] **Thumbnail service**
  - Generate 3 sizes: small (100x100), medium (400x400), large (1200x1200)
  - Cache thumbnails in Valkey for hot content
  - Lazy generation for rarely accessed media

### Event Processing

- [ ] **Set up SQS FIFO queues**
  - Ordered message delivery per chat
  - Exactly-once processing

- [ ] **Set up EventBridge Pipes**
  - "Normalizer" pattern for event transformation
  - "Claim Check" pattern for large payloads

- [ ] **Set up SNS**
  - Mobile push notifications
  - Fan-out to microservices

- [ ] **Set up dead letter queues & retry policies**
  - Exponential backoff for failed messages
  - DLQ alerts for manual intervention

### Search Pipeline

- [ ] **Implement message indexing service**
  - Index messages to Elasticsearch on write
  - Batch indexing for backfill
  - Index lifecycle management (hot/warm/cold)

- [ ] **Implement search API**
  - Full-text search with relevance scoring
  - Filters: date range, sender, chat, media type
  - Pagination with cursor-based pagination
  - Rate-limited per user

## Phase 3: Frontend Features

### Authentication & Onboarding

- [ ] Sign-up / Sign-in (email, phone, OAuth)
- [ ] **Privacy-preserving contact discovery** — hash-based, no raw numbers to server
- [ ] **Account recovery flow** — 10 one-time recovery codes at signup
- [ ] **Trusted device setup** — QR code scan to link new device
- [ ] Profile creation (avatar, display name, bio)
- [ ] **Recovery code display & backup** — force user to save codes

### Privacy Controls (per-user settings)

- [ ] **Last-seen visibility** — Nobody / Everyone / My Contacts / My Contacts Except
- [ ] **Profile photo visibility** — Nobody / Everyone / My Contacts
- [ ] **Read receipts** — Global on/off + per-chat override
- [ ] **Group add permission** — Everyone / My Contacts / My Contacts Except
- [ ] **Block list** — Block/unblock users, syncs across all devices
- [ ] **Status privacy** — My Contacts / Close Friends / Public

### Core Messaging

- [ ] One-to-one chat
- [ ] Group chat (create, join, leave)
- [ ] Message send / receive (text)
- [ ] Message status (sent, delivered, read)
- [ ] **Offline message queue** — backlog sync on reconnect with smart catch-up
- [ ] Media sharing (images, voice notes, files, video)
- [ ] Message reply / thread
- [ ] Message reactions (emoji)
- [ ] **Full-text message search** — across all chats with filters
- [ ] **Message bookmarks** — save important messages, sync across devices

### Advanced Messaging

- [ ] **Multi-device sync** — independent connections per device, phone not required
- [ ] **Message edit / delete** — edit within 15min, delete for everyone
- [ ] **Message pinning** — pinned messages at top of chat
- [ ] **Chat export** — JSON or HTML format
- [ ] **Disappearing messages** — per-chat: off / 5s / 30s / 5m / 1h / 24h
- [ ] **Message retention** — per-chat auto-delete: off / 30d / 90d / 1yr
- [ ] **Scheduled messages** — write now, send later
- [ ] **Inline message translation** — tap to translate via AI
- [ ] **In-chat polls** — create, vote, live results
- [ ] **Stickers & GIFs** — sticker packs, GIF search, custom sticker upload
- [ ] **Voice messages** — hold-to-record, Opus codec

### Stories / Status

- [ ] **Post status** — photo, video, or text that disappears in 24h
- [ ] **View status** — tap contact to view, see who viewed
- [ ] **Status privacy** — My Contacts / Close Friends / Public
- [ ] **Status replies** — reply to status via DM
- [ ] **Text formatting** — font styles, background colors

### Broadcast & Channels

- [ ] **Broadcast lists** — send message to multiple contacts at once
- [ ] **Channel creation** — one-to-many broadcast channel
- [ ] **Channel subscribe/unsubscribe**
- [ ] **Channel admin tools** — add admins, remove subscribers, analytics

### Real-Time Features

- [ ] Typing indicators (WebTransport datagrams)
- [ ] Online / presence status
- [ ] Push notifications (APNs/FCM)
- [ ] Push notification backoff (exponential for offline users)
- [ ] Read receipts

### Voice & Video Calling

- [ ] One-to-one voice (WebRTC with STUN/TURN)
- [ ] One-to-one video (WebRTC)
- [ ] Group calls (up to 8 participants)
- [ ] Picture-in-picture mode
- [ ] Noise suppression (AI-powered)

### Cross-Cutting

- [ ] **Dark mode** — light / dark / system
- [ ] **Multi-language (i18n)** — English + Hindi + 5 more at launch
- [ ] **RTL support** — Arabic, Hebrew, Urdu
- [ ] **Accessibility** — screen reader support, high contrast

## Phase 4: AI & Agentic Services

- [ ] **Set up Amazon Bedrock AgentCore**
  - Foundation model selection (Claude 3.5 Haiku / Nova Micro)

- [ ] **Content moderation pipeline**
  - API Gateway → SQS FIFO → Lambda → Bedrock Guardrails
  - Natural-language policy enforcement
  - Real-time flagging & auto-removal
  - Graceful fallback: pass-through if AI is down

- [ ] **AI chat assistant**
  - Supervised agent pattern
  - Episodic memory (AgentCore Memory)
  - Context-aware replies
  - Per-user memory isolation

- [ ] **Automated group summaries**
  - Scheduled summary generation
  - Digest delivery (daily/weekly)

- [ ] **Inline message translation**
  - Language auto-detection
  - Tap-to-translate on any message
  - Source/target language preference

- [ ] **AI noise suppression** (for voice calls)
- [ ] **AI-powered search relevance** — semantic search beyond keyword matching

## Phase 5: Admin Dashboard & Operations

### Web Admin Dashboard

- [ ] **User management** — search users, view profile, disable account
- [ ] **Moderation queue** — review flagged messages, take action (approve/remove/ban)
- [ ] **System health** — service status, latency charts, error rates
- [ ] **Analytics dashboard** — DAU/MAU, retention, messages/day, signups
- [ ] **Feature flag console** — toggle features on/off per user segment
- [ ] **Audit log viewer** — searchable log of admin actions

### Webhook & API System

- [ ] **Event-driven webhooks** — message sent, message received, user joined, etc.
- [ ] **Bot API** — send messages, manage groups, listen to events
- [ ] **API key management** — create/revoke keys, rate limits per key
- [ ] **Webhook retry** — exponential backoff, dead letter on failure

## Phase 6: Infrastructure & DevOps

- [ ] **Networking — AWS Global Accelerator**
  - Anycast IP routing
  - Sub-50ms global latency
  - Sub-second failover

- [ ] **CDN — CloudFront**
  - Static asset delivery
  - Media caching with signed URLs
  - Cache invalidation on content update

- [ ] **Monitoring & Observability**
  - CloudWatch dashboards
  - Structured logging (JSON)
  - Distributed tracing (X-Ray)

- [ ] **Alerting**
  - Latency thresholds
  - Error rate thresholds
  - Cost anomaly detection
  - Dead letter queue alerts

- [ ] **Synthetic monitoring**
  - Ping endpoints every minute from multiple regions
  - Full message send/receive flow test every 5 minutes
  - API endpoint health checks

- [ ] **Chaos engineering**
  - Monthly game day: kill a service, verify degradation works
  - Network latency injection
  - Database failover drill

- [ ] **Load testing**
  - k6 scripts for message send/receive at target throughput
  - Connection burst test (10K simultaneous connections)
  - Database write throughput validation
  - Regular load tests before major releases

- [ ] **Backup & Disaster Recovery**
  - Automated PostgreSQL backups (Neon branching)
  - ScyllaDB backup to S3
  - Multi-AZ deployment
  - Cross-region DR plan

### Feature Flag System

- [ ] **Flag management console** — admin UI for toggling features
- [ ] **Gradual rollout** — percentage-based rollouts (1% → 5% → 25% → 100%)
- [ ] **Kill switches** — instant disable for any feature
- [ ] **Targeted rollouts** — by platform, region, user segment
- [ ] **A/B testing** — split users into control/treatment groups

### Graceful Degradation

- [ ] **Circuit breakers** for all downstream service calls
- [ ] **Fallback: AI moderation down** → pass-through mode with logging
- [ ] **Fallback: Database degraded** → read-only mode, queue writes
- [ ] **Fallback: Search down** → basic filter-only search
- [ ] **Fallback: WebTransport down** → downgrade to SSE → WebSocket
- [ ] **Local-first message queue** — messages save locally and sync when online

## Phase 7: Launch & Scale

- [ ] **Alpha (100 users)** — internal testing, all core features
- [ ] **Beta (1,000 users)** — closed beta, full feature set, bug fixes
- [ ] **MVP Launch (0–1,000 DAU)**
  - Core messaging + basic auth
  - Serverless (near-zero cost)
  - Free tier optimized

- [ ] **Target Stage (10,000 DAU)**
  - Full feature set (including stories, polls, broadcast)
  - ECS Fargate + provisioned DBs
  - Estimated cost: ~$990/mo

- [ ] **Scale to 1M users (100,000 DAU)**
  - Direct S3 uploads (pre-signed URLs)
  - WebTransport datagrams for presence
  - MSK Serverless replacing SQS
  - Provisioned ScyllaDB on EC2

- [ ] **Post-launch iterations**
  - User feedback collection
  - Performance tuning
  - Feature prioritization
  - App store ratings management
