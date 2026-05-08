# CloseTalk

**High-performance, cross-platform real-time communication app** — modern messaging built for 2026.

CloseTalk is a real-time chat application that connects people through instant messaging, group conversations, voice/video calls, and AI-powered features. Built with Flutter for cross-platform reach and a cloud-native backend for scale.

CloseTalk fixes every major problem WhatsApp users have faced — TCP head-of-line blocking, phone-dependent multi-device, raw contact upload to servers, media quality loss, manual spam reporting, and hard-to-scale architecture.

## Features

- **Instant Messaging** — Send text, images, voice notes, and files with real-time delivery and read receipts
- **Group Chats** — Create groups up to 1,000 members with admin controls, @mentions, and pinned messages
- **Voice & Video Calls** — One-to-one and group calls with AI noise suppression
- **Native Multi-Device** — Phone NOT required as relay. Each device connects independently with its own WebTransport session
- **AI Assistant** — Context-aware chat assistant with persistent memory for summaries, suggestions, and answers
- **Content Moderation** — Real-time AI-powered filtering for hate speech, PII, and harassment using Bedrock Guardrails
- **Stories / Status** — 24h ephemeral photo, video, and text posts with privacy controls
- **Broadcast & Channels** — One-to-many messaging with subscribe/unsubscribe
- **In-Chat Polls** — Create, vote, and see live results
- **Inline Translation** — Tap any message to translate via AI
- **Full-Text Search** — Search across all chats with filters (date, sender, chat)
- **Typing Indicators & Presence** — Live typing status and online presence via WebTransport datagrams (QUIC, <20ms)
- **Message Retention** — Per-chat auto-delete: off / 30d / 90d / 1yr
- **Disappearing Messages** — 5s / 30s / 5m / 1h / 24h per chat
- **Block List & Privacy Controls** — Granular last-seen, profile photo, read receipts, and group add permissions
- **End-to-End Encryption** — Optional Signal Protocol with per-device key pairs
- **Cross-Platform** — Android, iOS, Web, Windows, macOS, and Linux from a single Flutter codebase

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) — Android, iOS, Web, Desktop |
| Backend | Node.js 25 / Go 1.26 on ECS Fargate (Graviton5) |
| Transport | WebTransport (QUIC) + SSE/HTTP-3 + WebSocket fallback |
| Relational DB | Neon Serverless PostgreSQL (RLS, copy-on-write branching) |
| NoSQL | ScyllaDB Cloud (DynamoDB-compatible, 50% cheaper, 10x lower latency) |
| Cache | Valkey 8.1 (ElastiCache — 28% better density than Redis) |
| AI | Amazon Bedrock AgentCore (Claude 3.5 Haiku / Nova Micro) |
| Events | SQS FIFO + EventBridge Pipes + SNS |
| Networking | AWS Global Accelerator (sub-50ms global latency) |
| CDN | Amazon CloudFront |

## Architecture

```
Clients ──▶ Global Accelerator ──▶ ALB ──▶ Services (ECS Fargate)
                                              │
                               ┌──────────────┼──────────────┐
                               ▼              ▼              ▼
                         Neon PostgreSQL  ScyllaDB Cloud  Valkey 8.1
                         (Users/Groups)   (Messages)     (Session/Presence)
                                              │
                                         EventBridge Pipes
                                              │
                                    ┌─────────┴─────────┐
                                    ▼                   ▼
                              Bedrock AI            SNS Push
                           (Moderation/Agent)     (Notifications)
```

The system uses a **disaggregated architecture** — each layer scales independently. Compute is stateless (just add more Fargate tasks). Data is routed to the best engine for each job: ACID metadata to PostgreSQL, high-throughput messages to ScyllaDB, low-latency session state to Valkey.

## Getting Started

### Prerequisites

- Flutter SDK 3.11+
- Dart 3.11+
- Docker (for backend development)

### Run the Flutter App

```bash
cd closetalk_app
flutter pub get
flutter run
```

### Run Tests

```bash
cd closetalk_app
flutter test
```

## Project Structure

```
closetalk/
├── closetalk_app/       # Flutter app (Android, iOS, Web, Desktop)
├── closetalk_backend/   # Backend services (placeholder)
├── closetalk_frontend/  # Web admin dashboard (placeholder)
├── docs/
│   ├── architecture.md       # System architecture deep-dive
│   ├── architecture-flow.md  # Architecture diagrams (Mermaid)
│   ├── security.md           # Security, compliance & maintenance
│   ├── requirements.md       # Functional & non-functional requirements
│   ├── planning.md           # Project planning checklist
│   ├── product-vision.md     # Product vision & user experience
│   └── closetalk-architecture.md  # Full 2026 architectural standard
└── README.md
```

## Documentation

| Document | Description |
|---|---|
| Architecture | docs/architecture.md |
| Architecture Diagrams (Mermaid) | docs/architecture-flow.md |
| Security, Compliance & Maintenance | docs/security.md |
| Requirements (Functional + Non-Functional) | docs/requirements.md |
| Project Planning Checklist | docs/planning.md |
| Product Vision & UX | docs/product-vision.md |
| Multi-Device Sync Protocol | docs/multi-device-sync.md |
| WhatsApp Gap Analysis & Fixes | docs/whatsapp-gap-analysis.md |
| Full Architectural Standard (PDF extract) | docs/closetalk-architecture.md |

## Cost Overview

| Stage | Users | DAU | Monthly Cost |
|---|---|---|---|
| MVP | 0–1,000 | 0–1,000 | $5–$10 |
| Growth | 1K–100K | 1K–10K | ~$990 |
| Scale | 100K–1M | 10K–100K | TBD (infra optimized) |

## License

MIT
