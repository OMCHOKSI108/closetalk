# CloseTalk — System Architecture

## Architecture Overview

CloseTalk follows a **disaggregated cloud-native architecture** — compute and storage are fully decoupled for independent scaling. The system is designed for 100,000 registered users (10,000 DAU) with linear horizontal scaling to 1M+ users.

Every WhatsApp architectural mistake is fixed:
- **No TCP head-of-line blocking** → WebTransport over QUIC
- **No co-located monolith** → Disaggregated microservices
- **No manual sharding** → ScyllaDB auto-sharding with Tablets
- **No phone-dependent multi-device** → Independent device connections from day 1
- **No raw contact upload** → Hash-based contact discovery
- **No media quality loss** → Direct S3 uploads via presigned URLs
- **No reactive moderation** → Real-time AI moderation pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                          Clients                                 │
│  Flutter App (Android/iOS/Web/Desktop) × 5 devices per user     │
│  WebTransport (primary) | SSE/HTTP-3 | WebSocket (fallback)     │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                    Edge Layer                                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  AWS Global Accelerator (Anycast IP — sub-50ms global)   │   │
│  │  AWS WAF (OWASP Top 10 + IP reputation + rate limiting)  │   │
│  │  CloudFront CDN (static assets + cached media)           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────┬───────────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────────┐
│                Application Layer (ECS Fargate Graviton5)         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐   │
│  │ Message  │ │  Auth    │ │ Presence │ │  Media Service   │   │
│  │ Service  │ │  Service │ │ Service  │ │  (presigned URLs) │   │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────────────┤   │
│  │ Group    │ │  User    │ │ Search   │ │  Notification    │   │
│  │ Service  │ │  Service │ │ Service  │ │  Service         │   │
│  ├──────────┤ ├──────────┤ ├──────────┤ ├──────────────────┤   │
│  │   AI Agent Service (Bedrock AgentCore)                   │   │
│  │   • Content Moderation  • Chat Assistant  • Translation  │   │
│  │   • Group Summaries     • Noise Suppression              │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────┬──────────────┬────────────────┬────────────────┬──────┘
         │              │                │                │
┌────────▼──────┐ ┌─────▼──────┐ ┌──────▼───────┐ ┌─────▼──────────┐
│  Neon Server- │ │  ScyllaDB  │ │  Valkey 8.1  │ │  Elasticsearch │
│  less Post-   │ │  Cloud     │ │  (ElastiCache)│ │  (Search)      │
│  greSQL        │ │  (NoSQL)   │ │              │ │                │
│               │ │            │ │ • Session    │ │ • Message      │
│  • Users      │ │ • Messages │ │ • Presence   │ │   index        │
│  • Groups     │ │ • History  │ │ • Pub/Sub    │ │ • Full-text    │
│  • Contacts   │ │ • Media    │ │ • Rate Limit │ │   search       │
│  • Settings   │ │   refs     │ │ • Thumbnail  │ │ • Filters      │
│  • RLS        │ │ • Polls    │ │   cache      │ │                │
│  • Sessions   │ │ • Status   │ │              │ │                │
└───────────────┘ └────────────┘ └──────────────┘ └────────────────┘
         │              │                │
┌────────▼──────────────▼────────────────▼────────────────────────┐
│                    Event Processing Layer                        │
│  ┌──────────┐ ┌────────────────┐ ┌──────────┐ ┌──────────────┐ │
│  │SQS FIFO  │ │EventBridge     │ │  SNS     │ │  Dead Letter │ │
│  │(Ordered  │ │Pipes (Logic-   │ │  (Push)  │ │  Queues      │ │
│  │ Delivery)│ │less Glue)      │ │          │ │  (Retry)     │ │
│  └──────────┘ └────────────────┘ └──────────┘ └──────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────────────────┐
│                    Async Processing Layer (Lambda)               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐│
│  │ Thumbnail    │ │ Video        │ │  Virus / Malware         ││
│  │ Generation   │ │ Transcoding  │ │  Scanning                ││
│  ├──────────────┤ ├──────────────┤ ├──────────────────────────┤│
│  │ Image Opt.   │ │ Voice Opt.   │ │  Index to Elasticsearch  ││
│  │ (WebP/AVIF)  │ │ (Opus)       │ │                          ││
│  └──────────────┘ └──────────────┘ └──────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| **Frontend** | Flutter (Dart) | Single codebase for 6 platforms |
| **Backend Runtime** | Node.js 25 or Go 1.26 | Async I/O, high throughput |
| **Compute** | AWS ECS Fargate (Graviton5) | Serverless containers, auto-scale, Nitro security |
| **Relational DB** | Neon Serverless PostgreSQL | Scale-to-zero, copy-on-write branching, RLS |
| **NoSQL** | ScyllaDB Cloud (DynamoDB API) | 10x lower p99 latency than DynamoDB, 50% cheaper |
| **Cache** | Valkey 8.1 (AWS ElastiCache) | 28% better memory density than Redis, 33% cheaper |
| **Search** | Elasticsearch / AWS OpenSearch | Full-text search with relevance, filters, aggregation |
| **Real-Time Transport** | WebTransport + SSE/HTTP-3 | Sub-50ms latency, no head-of-line blocking, 0-RTT |
| **Messaging** | SQS FIFO + EventBridge Pipes | Ordered delivery, exactly-once, minimal Lambda |
| **AI/Agents** | Amazon Bedrock AgentCore | Managed agent orchestration with persistent memory |
| **Media** | S3 + CloudFront + Lambda | Direct upload, async processing, CDN delivery |
| **Networking** | AWS Global Accelerator | Sub-second failover, optimized global routing |
| **Identity** | Clerk / Auth0 + Amazon Cognito | OAuth, JWT, RLS integration |

## Key Architectural Decisions

### 1. Disaggregated Compute & Storage
Each layer scales independently. Adding more users means adding more stateless Fargate tasks — no manual sharding. This fixes WhatsApp's co-located Erlang/Mnesia problem.

### 2. Polyglot Persistence
- **PostgreSQL (Neon)**: User accounts, groups, contacts, settings — needs ACID + RLS
- **ScyllaDB**: Messages, polls, status — needs high write throughput, horizontal scaling, hot partition handling
- **Valkey**: Sessions, presence, pub/sub, rate limits — needs low-latency in-memory operations
- **Elasticsearch**: Full-text search index — needs relevance scoring, filtering, aggregation
- **S3**: Media files, backups, audit logs — needs durable object storage

### 3. WebTransport + SSE over HTTP/3
WebSockets are the fallback. Primary transport uses QUIC (UDP-based) to eliminate TCP head-of-line blocking — WhatsApp's biggest performance problem. Unreliable datagrams for ephemeral state (typing, presence, cursor), reliable streams for messages.

### 4. Multi-Device Architecture (Native, Not Retrofitted)
Unlike WhatsApp which added multi-device support years later (requiring phone as relay), CloseTalk supports independent device connections from day 1:
- Each device gets its own identity key pair
- Each device maintains independent WebTransport connection
- Phone is NOT required as a relay for other devices
- Message history syncs to new devices from ScyllaDB
- E2EE key exchange uses X3DH per device pair

### 5. Privacy-Preserving Contact Discovery
Unlike WhatsApp which uploads raw phone numbers to servers:
- Client sends SHA-256 hashes of contacts' phone numbers
- Server matches against hashed user database
- Server never stores or sees raw phone numbers

### 6. Agentic AI Integration
Bedrock AgentCore provides serverless AI agents with:
- Episodic memory for context-aware conversations
- Natural-language moderation policies
- Supervisor agent pattern (coordinating moderation, summary, and task agents)

### 7. Direct Media Upload (No Quality Loss)
Unlike WhatsApp which re-compresses media through the server:
- Client requests presigned URL from Media Service
- Client uploads directly to S3 (bypasses application servers)
- Async Lambda processes: thumbnails, transcoding, virus scan
- Original file preserved at full quality

### 8. Graceful Degradation
Every downstream service has circuit breakers:
- AI moderation down → pass-through mode with deferred scanning
- Database degraded → read-only mode, writes queued locally
- Search down → fall back to basic filter-only search
- WebTransport down → downgrade to SSE → WebSocket
- Any critical service down → feature-flag kill switch

## Scalability Path

| Stage | Users | DAU | Architecture | Monthly Cost |
|---|---|---|---|---|
| **MVP** | 0–1,000 | 0–1,000 | Serverless (Lambda, Neon Free, Valkey Serverless, ScyllaDB Free) | $5–$10 |
| **Growth** | 1K–100K | 1K–10K | ECS Fargate + provisioned DBs + Global Accelerator | ~$990 |
| **Scale** | 100K–1M | 10K–100K | Direct S3 uploads, MSK Serverless, provisioned ScyllaDB on EC2 | TBD |

## Security Architecture

- **Zero-Trust**: Every request authenticated via JWT
- **Row Level Security**: PostgreSQL RLS ensures tenant isolation at the database level
- **Nitro Isolation**: AWS Graviton5 hardware-verified memory isolation
- **TLS 1.3**: All endpoints encrypted in transit
- **AgentCore Token Vault**: AI agents access APIs without credential exposure
- **Hash-based Contact Discovery**: No raw phone numbers on server
- **E2EE (Optional)**: Signal Protocol with per-device key pairs

## Deployment Architecture

```
GitHub Repo
    │
    ├── closetalk_app/       → Flutter build → App Store / Play Store / Web
    ├── closetalk_backend/   → Docker build → ECR → ECS Fargate
    ├── closetalk_frontend/  → Docker build → ECR → ECS Fargate / CloudFront
    ├── docs/                → Documentation
    └── .github/             → CI/CD workflows

CI/CD:
  GitHub Actions → lint → test → build → scan → deploy (staging → prod)
  Feature flags control rollout percentage per service
  Neon branching for ephemeral dev/staging DBs
```

## Missing Components (Added vs Original)

| Component | Original Architecture | Updated Architecture |
|---|---|---|
| Search | ❌ Not present | ✅ Elasticsearch with full-text search |
| Media Pipeline | ❌ Basic upload | ✅ Presigned URLs + async processing + CDN |
| Multi-Device | ❌ Mentioned only | ✅ Native protocol with per-device keys |
| Contact Discovery | ❌ Not present | ✅ Hash-based, privacy-preserving |
| Account Recovery | ❌ Not present | ✅ Recovery codes + trusted devices |
| Privacy Controls | ❌ Basic mention | ✅ Granular per-setting visibility |
| Graceful Degradation | ❌ Not present | ✅ Circuit breakers + fallback modes |
| Feature Flags | ❌ Not present | ✅ Centralized flag system |
| Admin Dashboard | ❌ Not present | ✅ Web admin with moderation + analytics |
| Webhooks/API | ❌ Not present | ✅ Event-driven webhooks + Bot API |
| Stories/Status | ❌ Not present | ✅ 24h ephemeral with privacy controls |
| Broadcast/Channels | ❌ Not present | ✅ One-to-many broadcast + channels |
| Polls | ❌ Not present | ✅ In-chat polls |
| Stickers/GIFs | ❌ Not present | ✅ Sticker packs + GIF search |
| Message Translation | ❌ Not present | ✅ AI inline translation |
| Message Scheduling | ❌ Not present | ✅ Scheduled send |
| Message Retention | ❌ Not present | ✅ Per-chat configurable auto-delete |
| Load Testing | ❌ Not present | ✅ k6 scripts + chaos engineering |
