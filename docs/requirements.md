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

### F2: Messaging
| ID | Requirement | Priority |
|---|---|---|
| F2.1 | Users shall send and receive text messages in real-time | P0 |
| F2.2 | Users shall send and receive images, voice notes, files, and video | P1 |
| F2.3 | Users shall see message status (sending, sent, delivered, read) | P1 |
| F2.4 | Users shall reply to specific messages in threads | P2 |
| F2.5 | Users shall react to messages with emoji | P2 |
| F2.6 | Users shall edit or delete their own messages within a time window | P2 |
| F2.7 | Users shall search through message history | P2 |
| F2.8 | Users shall export chat history | P3 |

### F3: Group Chats
| ID | Requirement | Priority |
|---|---|---|
| F3.1 | Users shall create groups with a name, description, and avatar | P1 |
| F3.2 | Users shall invite others to groups via link or direct add | P1 |
| F3.3 | Group admins shall add / remove members and promote admins | P1 |
| F3.4 | Users shall leave groups they are a member of | P1 |
| F3.5 | Groups shall support up to 1,000 members | P1 |
| F3.6 | Group admins shall pin important messages | P3 |

### F4: Real-Time Features
| ID | Requirement | Priority |
|---|---|---|
| F4.1 | Users shall see typing indicators for active conversations | P1 |
| F4.2 | Users shall see online / last-seen status of contacts | P1 |
| F4.3 | Users shall receive push notifications for new messages | P1 |
| F4.4 | Users shall see read receipts for their sent messages | P2 |
| F4.5 | Users shall receive notifications for @mentions in groups | P2 |

### F5: Voice & Video
| ID | Requirement | Priority |
|---|---|---|
| F5.1 | Users shall make one-to-one voice calls (WebRTC) | P2 |
| F5.2 | Users shall make one-to-one video calls (WebRTC) | P2 |
| F5.3 | Users shall make group voice/video calls (up to 8 participants) | P3 |

### F6: Content Moderation
| ID | Requirement | Priority |
|---|---|---|
| F6.1 | System shall automatically flag and filter hate speech, PII, and harassment | P1 |
| F6.2 | System shall allow admin to review flagged content and take action | P2 |
| F6.3 | Users shall report messages or users for review | P2 |
| F6.4 | System shall distinguish context (e.g., medical summary vs. harmful PII leak) | P2 |

### F7: AI Assistant
| ID | Requirement | Priority |
|---|---|---|
| F7.1 | System shall provide an AI chat assistant with persistent memory | P2 |
| F7.2 | System shall generate automated summaries of group conversations | P3 |
| F7.3 | System shall support natural-language policy configuration for moderation | P3 |

### F8: Cross-Platform
| ID | Requirement | Priority |
|---|---|---|
| F8.1 | Application shall run on Android and iOS | P0 |
| F8.2 | Application shall run on Web browsers | P1 |
| F8.3 | Application shall run on Windows, macOS, and Linux | P2 |
| F8.4 | Users shall have seamless multi-device experience with sync | P2 |

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

### N2: Scalability
| ID | Requirement | Target |
|---|---|---|
| N2.1 | Registered users | 100,000 |
| N2.2 | Daily active users (DAU) | 10,000 (baseline) |
| N2.3 | Group chat size | Up to 1,000 members |
| N2.4 | Horizontal scaling | Linear, auto-scaling via ECS Fargate |
| N2.5 | Database scaling | Shard-per-core (ScyllaDB) + read replicas (PostgreSQL) |

### N3: Availability & Reliability
| ID | Requirement | Target |
|---|---|---|
| N3.1 | Uptime SLA | 99.9% (target 99.99%) |
| N3.2 | Message durability | No message loss; exactly-once delivery |
| N3.3 | Failover time | < 1 second (Global Accelerator) |
| N3.4 | Backup frequency | Continuous (WAL archiving) |
| N3.5 | Disaster recovery | Multi-AZ, cross-region backup |

### N4: Security
| ID | Requirement | Target |
|---|---|---|
| N4.1 | Encryption in transit | TLS 1.3 (all endpoints) |
| N4.2 | Encryption at rest | AES-256 (S3, RDS, ScyllaDB) |
| N4.3 | Authentication | JWT with short expiry + refresh tokens |
| N4.4 | Authorization | Row Level Security (PostgreSQL RLS) |
| N4.5 | Data isolation | Multi-tenant with hardware-level Nitro isolation |
| N4.6 | Secrets management | AWS Secrets Manager or AgentCore Token Vault |
| N4.7 | Rate limiting | Per-user, per-IP, per-chat |

### N5: Cost Efficiency
| ID | Requirement | Target |
|---|---|---|
| N5.1 | MVP monthly infra cost | $5–$10 (free tier optimized) |
| N5.2 | Target stage monthly infra cost | ~$990 (10,000 DAU) |
| N5.3 | Memory tier efficiency | Valkey 8.1 (28% better density vs Redis) |
| N5.4 | NoSQL storage cost | 50% less than DynamoDB (ScyllaDB) |

### N6: Maintainability
| ID | Requirement | Target |
|---|---|---|
| N6.1 | Deployment model | Containerized (Docker + ECS Fargate) |
| N6.2 | Database migrations | Automated with Neon branching for dev/staging |
| N6.3 | Monitoring | CloudWatch dashboards + structured logging |
| N6.4 | CI/CD | GitHub Actions (lint, test, build, deploy) |
| N6.5 | Code quality | Flutter analyze pass, Go/Node.js lint pass |

### N7: Privacy & Compliance
| ID | Requirement | Target |
|---|---|---|
| N7.1 | Data retention policy | Configurable auto-delete for messages |
| N7.2 | User data export | GDPR-compliant data export |
| N7.3 | Right to be forgotten | Full account deletion with data purge |
| N7.4 | Log retention | 90 days (configurable) |
