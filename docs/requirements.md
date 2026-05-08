# CloseTalk — System Requirements

## Functional Requirements

### F1: User Management
| ID | Requirement | Priority |
|---|---|---|
| F1.1 | Users shall register with email, phone number, or OAuth provider | P0 |
| F1.2 | Users shall log in using registered credentials or SSO | P0 |
| F1.3 | Users shall create and edit their profile (avatar, display name, bio) | P1 |
| F1.4 | Users shall delete their account and all associated data | P1 |
| F1.5 | Users shall search for other users by name, email, or phone | P1 |
| F1.6 | Users shall receive 10 one-time recovery codes at signup for account recovery | P1 |
| F1.7 | Users shall recover their account via recovery codes, trusted device, or email | P1 |
| F1.8 | Users shall link/unlink multiple devices (phone, tablet, desktop, web) | P1 |
| F1.9 | Users shall view and remotely disconnect active sessions | P2 |

### F2: Contact Discovery & Privacy
| ID | Requirement | Priority |
|---|---|---|
| F2.1 | Users shall discover contacts via phone number (hash-based, no raw upload) | P1 |
| F2.2 | Users shall set last-seen visibility: Nobody / Everyone / My Contacts / My Contacts Except | P1 |
| F2.3 | Users shall set profile photo visibility: Nobody / Everyone / My Contacts | P1 |
| F2.4 | Users shall enable/disable read receipts globally and per-chat | P1 |
| F2.5 | Users shall set who can add them to groups: Everyone / My Contacts / My Contacts Except | P1 |
| F2.6 | Users shall block and unblock other users; blocks sync across all devices | P1 |
| F2.7 | Blocked users shall not see last-seen, profile photo, or status updates | P1 |

### F3: Messaging
| ID | Requirement | Priority |
|---|---|---|
| F3.1 | Users shall send and receive text messages in real-time | P0 |
| F3.2 | Users shall send and receive images, voice notes, files, and video | P1 |
| F3.3 | Users shall see message status (sending, sent, delivered, read) | P1 |
| F3.4 | Users shall reply to specific messages in threads | P2 |
| F3.5 | Users shall react to messages with emoji | P2 |
| F3.6 | Users shall edit messages within 15 minutes of sending (with edit history) | P2 |
| F3.7 | Users shall delete messages for everyone within 15 minutes | P2 |
| F3.8 | Users shall search through all message history with full-text search and filters | P2 |
| F3.9 | Users shall export chat history (JSON/HTML) | P3 |
| F3.10 | Users shall bookmark important messages; bookmarks sync across devices | P3 |

### F4: Multi-Device Sync
| ID | Requirement | Priority |
|---|---|---|
| F4.1 | Each device shall maintain an independent WebTransport connection | P1 |
| F4.2 | Messages shall sync to all linked devices in real-time | P1 |
| F4.3 | New devices shall sync message history from ScyllaDB on link | P1 |
| F4.4 | Phone shall not be required to stay online for other devices to work | P1 |
| F4.5 | Device revocation shall immediately terminate all connections on that device | P1 |
| F4.6 | E2EE key distribution shall support multiple devices per user (X3DH + Double Ratchet per device pair) | P2 |

### F5: Group Chats
| ID | Requirement | Priority |
|---|---|---|
| F5.1 | Users shall create groups with a name, description, and avatar | P1 |
| F5.2 | Users shall invite others to groups via shareable link or direct add | P1 |
| F5.3 | Group admins shall add / remove members and promote admins | P1 |
| F5.4 | Users shall leave groups they are a member of | P1 |
| F5.5 | Groups shall support up to 1,000 members | P1 |
| F5.6 | Group admins shall pin important messages | P3 |
| F5.7 | Group admins shall set message retention policy (off / 30d / 90d / 1yr) | P2 |
| F5.8 | Group admins shall enable/disable disappearing messages per group | P2 |

### F6: Real-Time Features
| ID | Requirement | Priority |
|---|---|---|
| F6.1 | Users shall see typing indicators for active conversations | P1 |
| F6.2 | Users shall see online / last-seen status of contacts | P1 |
| F6.3 | Users shall receive push notifications for new messages | P1 |
| F6.4 | Users shall see read receipts for their sent messages | P2 |
| F6.5 | Users shall receive notifications for @mentions in groups | P2 |

### F7: Stories / Status
| ID | Requirement | Priority |
|---|---|---|
| F7.1 | Users shall post photo, video, or text status that disappears in 24 hours | P1 |
| F7.2 | Users shall view contacts' status updates in a ranked list | P1 |
| F7.3 | Users shall see who viewed their status | P2 |
| F7.4 | Users shall reply to status updates via direct message | P2 |
| F7.5 | Users shall set status privacy: My Contacts / Close Friends / Public | P1 |
| F7.6 | Users shall mute status updates from specific contacts | P2 |

### F8: Broadcast & Channels
| ID | Requirement | Priority |
|---|---|---|
| F8.1 | Users shall send broadcast messages to multiple contacts at once | P2 |
| F8.2 | Users shall create public channels for one-to-many broadcasting | P2 |
| F8.3 | Users shall subscribe to and unsubscribe from public channels | P2 |
| F8.4 | Channel admins shall have moderation tools (remove subscribers, mute) | P3 |
| F8.5 | Channel admins shall see subscriber count and engagement analytics | P3 |

### F9: Voice & Video
| ID | Requirement | Priority |
|---|---|---|
| F9.1 | Users shall make one-to-one voice calls (WebRTC with STUN/TURN) | P2 |
| F9.2 | Users shall make one-to-one video calls (WebRTC) | P2 |
| F9.3 | Users shall make group voice/video calls (up to 8 participants) | P3 |
| F9.4 | Calls shall include AI-powered noise suppression | P3 |
| F9.5 | Calls shall support picture-in-picture mode on mobile | P2 |

### F10: Advanced Messaging
| ID | Requirement | Priority |
|---|---|---|
| F10.1 | Users shall schedule messages to send at a future time | P2 |
| F10.2 | Users shall translate messages inline via AI (tap to translate) | P2 |
| F10.3 | Users shall create and vote in in-chat polls | P2 |
| F10.4 | Users shall send stickers from sticker packs | P2 |
| F10.5 | Users shall search and send GIFs (Tenor/Giphy integration) | P2 |
| F10.6 | Users shall set disappearing messages per-chat (off / 5s / 30s / 5m / 1h / 24h) | P2 |
| F10.7 | Users shall set message retention per-chat (off / 30d / 90d / 1yr) | P2 |
| F10.8 | Users shall send voice messages (hold-to-record, Opus codec) | P1 |

### F11: Content Moderation
| ID | Requirement | Priority |
|---|---|---|
| F11.1 | System shall automatically flag and filter hate speech, PII, and harassment in real-time | P1 |
| F11.2 | System shall allow admin to review flagged content and take action | P2 |
| F11.3 | Users shall report messages or users for review | P2 |
| F11.4 | System shall distinguish context (e.g., medical summary vs. harmful PII leak) | P2 |
| F11.5 | System shall gracefully degrade to pass-through mode if AI moderation is unavailable | P2 |

### F12: AI Assistant
| ID | Requirement | Priority |
|---|---|---|
| F12.1 | System shall provide an AI chat assistant with persistent episodic memory | P2 |
| F12.2 | System shall generate automated summaries of group conversations | P3 |
| F12.3 | System shall support natural-language policy configuration for moderation | P3 |
| F12.4 | AI assistant memory shall be per-user and never shared across tenants | P1 |

### F13: Admin Dashboard
| ID | Requirement | Priority |
|---|---|---|
| F13.1 | Admins shall search, view, and manage user accounts | P1 |
| F13.2 | Admins shall review flagged messages and take action (approve/remove/ban) | P1 |
| F13.3 | Admins shall view system health (service status, latency, error rates) | P1 |
| F13.4 | Admins shall view analytics (DAU/MAU, retention, messages/day, signups) | P2 |
| F13.5 | Admins shall toggle feature flags on/off per segment | P1 |
| F13.6 | Admins shall view and search audit logs | P2 |

### F14: Webhooks & API
| ID | Requirement | Priority |
|---|---|---|
| F14.1 | System shall send event-driven webhooks (message sent, user joined, etc.) | P2 |
| F14.2 | Developers shall send messages and manage groups via Bot API | P3 |
| F14.3 | API keys shall be manageable via admin dashboard (create/revoke/rate-limit) | P2 |

### F15: Cross-Platform
| ID | Requirement | Priority |
|---|---|---|
| F15.1 | Application shall run on Android and iOS | P0 |
| F15.2 | Application shall run on Web browsers | P1 |
| F15.3 | Application shall run on Windows, macOS, and Linux | P2 |
| F15.4 | Users shall have seamless multi-device experience with real-time sync | P1 |
| F15.5 | Application UI shall support i18n (English + Hindi + 5 more languages at launch) | P2 |
| F15.6 | Application shall support RTL languages (Arabic, Hebrew, Urdu) | P3 |

---

## Non-Functional Requirements

### N1: Performance
| ID | Requirement | Target |
|---|---|---|
| N1.1 | Message delivery latency (end-to-end) | < 50ms (p99) |
| N1.2 | Message delivery latency (global, via Global Accelerator) | < 100ms (p99) |
| N1.3 | API response time (non-real-time) | < 200ms (p95) |
| N1.4 | App cold start time | < 2 seconds |
| N1.5 | Concurrent connections per server | 10,000+ |
| N1.6 | Database write throughput (message history) | 500,000 msgs/day minimum |
| N1.7 | Full-text search response time | < 500ms (p95) |
| N1.8 | Media upload (presigned URL generation) | < 50ms |
| N1.9 | Thumbnail generation latency | < 2 seconds (async) |
| N1.10 | Status load time (stories) | < 1 second |

### N2: Scalability
| ID | Requirement | Target |
|---|---|---|
| N2.1 | Registered users | 100,000 |
| N2.2 | Daily active users (DAU) | 10,000 (baseline) |
| N2.3 | Group chat size | Up to 1,000 members |
| N2.4 | Messages per day | 500,000 (growth target) |
| N2.5 | Devices per user | Up to 5 linked devices |
| N2.6 | Horizontal scaling | Linear, auto-scaling via ECS Fargate |
| N2.7 | Database scaling | Shard-per-core (ScyllaDB) + read replicas (PostgreSQL) |
| N2.8 | Search index capacity | 50M+ messages |

### N3: Availability & Reliability
| ID | Requirement | Target |
|---|---|---|
| N3.1 | Uptime SLA | 99.9% (target 99.99%) |
| N3.2 | Message durability | No message loss; exactly-once delivery |
| N3.3 | Failover time | < 1 second (Global Accelerator) |
| N3.4 | Backup frequency | Continuous (WAL archiving) |
| N3.5 | Disaster recovery | Multi-AZ, cross-region backup |
| N3.6 | Offline message retention | Retain all undelivered messages for 30 days |
| N3.7 | Graceful degradation | No cascading failures; per-service fallbacks |

### N4: Security
| ID | Requirement | Target |
|---|---|---|
| N4.1 | Encryption in transit | TLS 1.3 (all endpoints) |
| N4.2 | Encryption at rest | AES-256 (S3, RDS, ScyllaDB) |
| N4.3 | Authentication | JWT with short expiry (15m) + refresh tokens (7d) |
| N4.4 | Authorization | Row Level Security (PostgreSQL RLS) |
| N4.5 | Data isolation | Multi-tenant with hardware-level Nitro isolation |
| N4.6 | Secrets management | AWS Secrets Manager or AgentCore Token Vault |
| N4.7 | Rate limiting | Per-user, per-IP, per-chat, per-endpoint |
| N4.8 | Contact privacy | Hash-based contact discovery; no raw phone numbers on server |
| N4.9 | Account recovery | 10 one-time codes; email fallback; trusted device verification |
| N4.10 | Virus scanning | All uploaded media scanned before delivery |

### N5: Cost Efficiency
| ID | Requirement | Target |
|---|---|---|
| N5.1 | MVP monthly infra cost | $5–$10 (free tier optimized) |
| N5.2 | Target stage monthly infra cost | ~$990 (10,000 DAU) |
| N5.3 | Memory tier efficiency | Valkey 8.1 (28% better density vs Redis) |
| N5.4 | NoSQL storage cost | 50% less than DynamoDB (ScyllaDB) |
| N5.5 | Media storage cost | S3 lifecycle: standard → infrequent → glacier |

### N6: Maintainability
| ID | Requirement | Target |
|---|---|---|
| N6.1 | Deployment model | Containerized (Docker + ECS Fargate) |
| N6.2 | Database migrations | Automated with Neon branching for dev/staging |
| N6.3 | Monitoring | CloudWatch dashboards + structured logging |
| N6.4 | CI/CD | GitHub Actions (lint, test, build, deploy) |
| N6.5 | Code quality | Flutter analyze pass, Go/Node.js lint pass |
| N6.6 | Feature flags | Centralized flag system with gradual rollout |
| N6.7 | Schema versioning | Forward-compatible message serialization (Protobuf) |

### N7: Privacy & Compliance
| ID | Requirement | Target |
|---|---|---|
| N7.1 | Data retention policy | Configurable auto-delete per chat (off / 30d / 90d / 1yr) |
| N7.2 | User data export | GDPR-compliant data export (JSON) |
| N7.3 | Right to be forgotten | Full account deletion with data purge within 30 days |
| N7.4 | Log retention | 90 days (configurable) |
| N7.5 | Legal hold | Preserve specific user/chat data for compliance when required |
| N7.6 | Moderation audit trail | All moderation actions logged with admin identity and timestamp |
