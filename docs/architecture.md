# CloseTalk — System Architecture

## Architecture Overview

CloseTalk follows a **disaggregated cloud-native architecture** — compute and storage are fully decoupled for independent scaling. The system is designed for 100,000 registered users (10,000 DAU) with linear horizontal scaling to 1M+ users.

```
┌─────────────────────────────────────────────────────────────┐
│                        Clients                               │
│  Flutter App (Android/iOS/Web/Desktop)                       │
│  WebTransport | SSE/HTTP/3 | WebSocket (fallback)            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│              AWS Global Accelerator                           │
│         (Anycast IP — sub-50ms global latency)               │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│              Application Layer (ECS Fargate)                  │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ Message API │  │ WebTransport │  │ WebSocket Gateway │   │
│  │ (REST/SSE)  │  │  Endpoint    │  │  (Fallback)       │   │
│  ├─────────────┤  ├──────────────┤  ├───────────────────┤   │
│  │ Auth API    │  │ Presence Hub │  │ Agentic Service   │   │
│  └─────────────┘  └──────────────┘  │ (Bedrock AgentCore)│   │
│                                       └───────────────────┘   │
└────────┬──────────────┬──────────────────┬───────────────────┘
         │              │                  │
┌────────▼──────┐ ┌─────▼──────┐ ┌─────────▼─────────────────┐
│  Neon Server- │ │  ScyllaDB  │ │  Valkey 8.1 (ElastiCache) │
│  less Post-   │ │  Cloud     │ │  ┌─────────────────────┐  │
│  greSQL        │ │  (NoSQL)   │ │  │ Session Store      │  │
│               │ │            │ │  │ Presence Pub/Sub   │  │
│  • Users      │ │ • Messages │ │  │ Rate Limiter       │  │
│  • Groups     │ │ • History  │ │  └─────────────────────┘  │
│  • Metadata   │ │ • Media    │ └───────────────────────────┘
│  • RLS        │ │   refs     │
│               │ │            │
└───────────────┘ └────────────┘
         │                  │
┌────────▼──────────────────▼────────────────────────────────┐
│              Event Processing Layer                          │
│  ┌──────────┐  ┌───────────────┐  ┌────────────────────┐   │
│  │SQS FIFO  │  │EventBridge    │  │  SNS              │   │
│  │(Ordered  │  │Pipes (Logic-  │  │  (Push Notif)     │   │
│  │ Delivery)│  │less Glue)     │  │                   │   │
│  └──────────┘  └───────────────┘  └────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| **Frontend** | Flutter (Dart) | Single codebase for 6 platforms |
| **Backend Runtime** | Node.js 25 or Go 1.26 | Async I/O, high throughput |
| **Compute** | AWS ECS Fargate (Graviton5) | Serverless containers, auto-scale, Nitro security |
| **Relational DB** | Neon Serverless PostgreSQL | Scale-to-zero, copy-on-write branching |
| **NoSQL** | ScyllaDB Cloud (DynamoDB API) | 10x lower p99 latency than DynamoDB, 50% cheaper |
| **Cache** | Valkey 8.1 (AWS ElastiCache) | 28% better memory density than Redis, 33% cheaper |
| **Real-Time Transport** | WebTransport + SSE/HTTP-3 | Sub-50ms latency, no head-of-line blocking |
| **Messaging** | SQS FIFO + EventBridge Pipes | Ordered delivery, exactly-once, minimal Lambda |
| **AI/Agents** | Amazon Bedrock AgentCore | Managed agent orchestration with persistent memory |
| **Networking** | AWS Global Accelerator | Sub-second failover, optimized global routing |
| **CDN** | Amazon CloudFront | Static/media asset delivery |
| **Identity** | Clerk / Auth0 + Amazon Cognito | OAuth, JWT, RLS integration |

## Key Architectural Decisions

### 1. Disaggregated Compute & Storage
Each layer scales independently. Adding more users means adding more stateless Fargate tasks — no manual sharding.

### 2. Polyglot Persistence
- **PostgreSQL (Neon)**: User accounts, groups, settings — needs ACID + RLS
- **ScyllaDB**: Message history — needs high write throughput, horizontal scaling
- **Valkey**: Sessions, presence, pub/sub — needs low-latency in-memory operations

### 3. WebTransport + SSE over HTTP/3
WebSockets are the fallback. Primary transport uses QUIC (UDP-based) to eliminate TCP head-of-line blocking. Unreliable datagrams for ephemeral state (typing, presence), reliable streams for messages.

### 4. Agentic AI Integration
Bedrock AgentCore provides serverless AI agents with:
- Episodic memory for context-aware conversations
- Natural-language moderation policies
- Supervisor agent pattern (coordinating moderation, summary, and task agents)

### 5. Event-Driven Architecture
SQS FIFO guarantees ordered message delivery within a chat. EventBridge Pipes eliminates custom Lambda code for stream transformations. SNS handles push notification fan-out.

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

## Deployment Architecture

```
GitHub Repo
    │
    ├── closetalk_app/    → Flutter build → App Store / Play Store / Web
    ├── closetalk_backend/ → Docker build → ECR → ECS Fargate
    ├── closetalk_frontend/→ Docker build → ECR → ECS Fargate / CloudFront
    └── docs/             → Documentation
```

- **CI/CD**: GitHub Actions → lint → test → build → deploy
- **Database Migrations**: Neon branching for ephemeral dev/staging DBs
- **Monitoring**: CloudWatch + structured JSON logging + distributed tracing
