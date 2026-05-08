# CloseTalk — Project Planning Checklist

## Phase 1: Foundation & Setup

- [ ] **Define project scope & goals**
  - Target: 100,000 registered users, 10,000 DAU
  - Platform: Mobile (Android/iOS), Web, Desktop (macOS/Linux/Windows)
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

## Phase 2: Backend Infrastructure

### Compute Layer

- [ ] **Choose backend runtime**
  - Option A: Node.js 25 (async I/O, large ecosystem)
  - Option B: Go 1.26 (performance, low memory)
  - Decision: ____

- [ ] **Set up container orchestration**
  - AWS ECS Fargate (Graviton5 instances)
  - Dockerfile + docker-compose for local dev
  - Auto-scaling configuration

- [ ] **Configure API Gateway**
  - REST endpoints for CRUD operations
  - WebSocket/WebTransport endpoints for real-time

### Database Layer

- [ ] **Set up Neon Serverless PostgreSQL**
  - User accounts, group metadata, settings
  - Row Level Security for multi-tenancy
  - Database branching for dev/staging

- [ ] **Set up ScyllaDB Cloud**
  - Message history (high-volume writes)
  - Alternator API (DynamoDB-compatible)
  - Partition key design for chat rooms

- [ ] **Set up Valkey 8.1 (ElastiCache)**
  - Session management
  - Presence/status tracking
  - Pub/sub for real-time events

### Real-Time Transport

- [ ] **Implement WebTransport endpoint**
  - Interactive states (typing, presence)
  - Unreliable datagrams for ephemeral data

- [ ] **Implement SSE over HTTP/3**
  - Standard message delivery
  - Fallback: WebSocket for legacy support

- [ ] **Implement WebSocket fallback**
  - Universal reachability
  - Graceful degradation

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

## Phase 3: Frontend Features

### Authentication & Onboarding

- [ ] Sign-up / Sign-in (email, phone, OAuth)
- [ ] Profile creation (avatar, display name, bio)
- [ ] Contact sync / invite flow

### Core Messaging

- [ ] One-to-one chat
- [ ] Group chat (create, join, leave)
- [ ] Message send / receive (text)
- [ ] Message status (sent, delivered, read)
- [ ] Media sharing (images, voice notes, files)
- [ ] Message reply / thread
- [ ] Message reactions (emoji)
- [ ] Message search

### Real-Time Features

- [ ] Typing indicators (WebTransport datagrams)
- [ ] Online / presence status
- [ ] Push notifications
- [ ] Read receipts

### Advanced Features

- [ ] Voice / video calling (WebRTC)
- [ ] Message edit / delete
- [ ] Message pinning
- [ ] Chat export
- [ ] Dark mode
- [ ] Multi-device sync

## Phase 4: AI & Agentic Services

- [ ] **Set up Amazon Bedrock AgentCore**
  - Foundation model selection (Claude 3.5 Haiku / Nova Micro)

- [ ] **Content moderation pipeline**
  - API Gateway → SQS FIFO → Lambda → Bedrock Guardrails
  - Natural-language policy enforcement
  - Real-time flagging & auto-removal

- [ ] **AI chat assistant**
  - Supervised agent pattern
  - Episodic memory (AgentCore Memory)
  - Context-aware replies

- [ ] **Automated group summaries**
  - Scheduled summary generation
  - Digest delivery

## Phase 5: Infrastructure & DevOps

- [ ] **Networking — AWS Global Accelerator**
  - Anycast IP routing
  - Sub-50ms global latency
  - Sub-second failover

- [ ] **CDN — CloudFront**
  - Static asset delivery
  - Media caching

- [ ] **Monitoring & Observability**
  - CloudWatch dashboards
  - Structured logging (JSON)
  - Distributed tracing

- [ ] **Alerting**
  - Latency thresholds
  - Error rate thresholds
  - Cost anomaly detection

- [ ] **Backup & Disaster Recovery**
  - Automated PostgreSQL backups (Neon branching)
  - ScyllaDB backup to S3
  - Multi-AZ deployment

## Phase 6: Launch & Scale

- [ ] **MVP Launch (0–1,000 DAU)**
  - Core messaging + basic auth
  - Serverless (near-zero cost)
  - Free tier optimized

- [ ] **Target Stage (10,000 DAU)**
  - Full feature set
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
