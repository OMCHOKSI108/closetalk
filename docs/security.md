# CloseTalk — Security, Compliance & Maintenance Guide

## Table of Contents
1. [Security Architecture](#security-architecture)
2. [Application Security](#application-security)
3. [Backend & API Security](#backend--api-security)
4. [Chat & Message Security](#chat--message-security)
5. [Database Security](#database-security)
6. [Infrastructure Security](#infrastructure-security)
7. [AI & Agent Security](#ai--agent-security)
8. [PlayStore & App Store Compliance](#playstore--app-store-compliance)
9. [Maintenance Plan](#maintenance-plan)
10. [Incident Response](#incident-response)

---

## Security Architecture

CloseTalk follows a **defense-in-depth** model with Zero-Trust principles. No component trusts another by default — every request is authenticated, authorized, and encrypted.

```
┌─────────────────────────────────────────────────────────┐
│                  Defense-in-Depth Layers                  │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Client Security (App hardening, secure store)  │
│  Layer 2: Transport Security (TLS 1.3, QUIC, mTLS)      │
│  Layer 3: API Security (JWT, rate limiting, WAF)        │
│  Layer 4: Application Security (RLS, input validation)   │
│  Layer 5: Database Security (encryption at rest, IAM)   │
│  Layer 6: Infrastructure Security (Nitro, VPC, SG)      │
│  Layer 7: Monitoring & Response (audit logs, alerting)  │
└─────────────────────────────────────────────────────────┘
```

---

## Application Security

### Flutter App Hardening

| Measure | Implementation |
|---|---|
| **Code Obfuscation** | Enable Flutter's `--obfuscate` and `--split-debug-info` for release builds |
| **Root/Jailbreak Detection** | Use `safe_device` package to detect compromised devices |
| **Certificate Pinning** | Pin TLS certificates using `http_client` with `BadCertificateCallback` disabled in production |
| **Secure Storage** | Store tokens and sensitive data using `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences on Android) |
| **Input Validation** | Sanitize all user inputs on the client side before sending |
| **Screenshot Prevention** | Use `FLAG_SECURE` on Android to block screenshots in sensitive screens |
| **App Attestation** | iOS: DeviceCheck + AppAttest; Android: Play Integrity API |
| **Minimal Permissions** | Request only necessary permissions at runtime, not at install |
| **Deep Link Validation** | Validate all incoming deep links against a whitelist of allowed schemes/hosts |

### Web App Security

| Measure | Implementation |
|---|---|
| **CSP Headers** | Strict Content-Security-Policy to prevent XSS |
| **HTTPS Only** | HSTS preload, redirect all HTTP to HTTPS |
| **XSS Protection** | React/Flutter web auto-escapes output; no `dangerouslySetInnerHTML` |
| **CSRF Tokens** | Anti-CSRF tokens on all state-changing requests |
| **Cookie Flags** | `SameSite=Strict`, `Secure`, `HttpOnly` on all cookies |
| **IFrame Protection** | `X-Frame-Options: DENY` to prevent clickjacking |
| **Subresource Integrity** | SRI hashes on all loaded scripts and stylesheets |

---

## Backend & API Security

### Authentication

| Measure | Implementation |
|---|---|
| **JWT-based Auth** | Short-lived access tokens (15 min) + long-lived refresh tokens (7 days) |
| **OAuth 2.0 / OIDC** | Support Google, GitHub, Apple Sign-In via Clerk/Auth0 |
| **Password Policy** | Min 8 chars, mixed case + numbers, bcrypt hashing (cost 12+) |
| **MFA** | Optional TOTP or SMS-based multi-factor authentication |
| **Session Management** | Server-side session store in Valkey; force-invalidate on password change |
| **Device Tracking** | Track active sessions per user; allow remote logout of specific devices |

### API Security

| Measure | Implementation |
|---|---|
| **Rate Limiting** | Per-user: 100 req/min; Per-IP: 1000 req/min; Per-chat: 30 msg/min |
| **WAF** | AWS WAF with OWASP Top 10 ruleset + IP reputation lists |
| **API Keys** | Server-to-server communication uses short-lived mTLS certificates |
| **Request Validation** | JSON schema validation on all endpoints; reject unknown fields |
| **Idempotency** | POST endpoints support `Idempotency-Key` header to prevent duplicate processing |
| **GraphQL Depth Limiting** | If using GraphQL, limit query depth to 5 levels |

### WebSocket / WebTransport Security

| Measure | Implementation |
|---|---|
| **Connection Auth** | Validate JWT before establishing WebSocket/WebTransport connection |
| **Origin Check** | Verify `Origin` header matches allowed domains |
| **Message Validation** | Validate every incoming frame against schema |
| **Rate Limiting** | Throttle messages per connection (30 msg/sec max) |
| **Connection Limits** | Max 10 concurrent connections per user |
| **Idle Timeout** | Drop connections idle for > 60 seconds |

---

## Chat & Message Security

### Message-Level Protections

| Measure | Implementation |
|---|---|
| **End-to-End Encryption (E2EE)** | Optional: Signal Protocol (X3DH + Double Ratchet) for one-to-one chats using `libsignal` |
| **E2EE Group Chats** | Sender Keys protocol for groups (optional, when enabled) |
| **Message Integrity** | HMAC signatures on all messages |
| **Ephemeral Messages** | Optional disappearing messages (5s, 30s, 5m, 1h, 24h) |
| **Forward Secrecy** | E2EE sessions rotate keys per-message (Double Ratchet) |

### Content Moderation

```
User sends message
       │
       ▼
┌──────────────────┐
│  SQS FIFO Queue   │  ← Ordered processing
└────────┬─────────┘
         ▼
┌──────────────────┐
│  Lambda Function  │  ← Invokes Bedrock
│  + Bedrock Guard- │     Guardrails
│  rails            │
└────────┬─────────┘
         ▼
  ┌──────┴──────┐
  ▼              ▼
Safe         Flagged
    │              │
    ▼              ▼
Deliver    Review Queue
            (Human-in-loop)
```

| Measure | Implementation |
|---|---|
| **Automated Filtering** | Bedrock Guardrails with natural-language hate/PII/harassment policies |
| **Media Scanning** | AWS Rekognition for image/video NSFW detection |
| **Link Scanning** | Check URLs against known phishing/malware databases |
| **User Reporting** | In-app report button; reports go to moderation queue |
| **Rate Limit on Send** | Prevent spam bursts per user |
| **Auto-Mute** | Auto-mute users sending > 50 messages/min to a group |

### Multi-Tenant Isolation

| Measure | Implementation |
|---|---|
| **Row Level Security (RLS)** | PostgreSQL RLS policies enforce user can only access chats they belong to |
| **Query Scoping** | All database queries include `WHERE user_id = current_user_id` |
| **Data Segregation** | No cross-tenant queries; each tenant's data is isolated at the DB row level |
| **Shared-Nothing Backend** | No in-memory state shared between tenants |

---

## Database Security

### Neon PostgreSQL

| Measure | Implementation |
|---|---|
| **Encryption at Rest** | AES-256 (enabled by default) |
| **Encryption in Transit** | TLS 1.3 enforced; reject non-TLS connections |
| **IAM Database Auth** | No passwords — use AWS IAM roles for authentication |
| **Network Isolation** | Deploy in private VPC subnets; no public access |
| **Automated Backups** | Continuous WAL archiving; point-in-time recovery to any second |
| **Branching for Dev** | Neon branching creates isolated DB copies for development — no production data exposure |
| **Audit Logging** | pgaudit extension logs all DDL and DML operations |
| **Connection Pooling** | PgBouncer with strict limit on concurrent connections per user |

### ScyllaDB

| Measure | Implementation |
|---|---|
| **Encryption at Rest** | AES-256 (enabled by default) |
| **Encryption in Transit** | Node-to-node and client-to-node TLS |
| **IAM Auth** | ScyllaDB Cloud IAM integration |
| **Network Isolation** | Private VPC endpoints only |
| **Backup** | Automated daily snapshots to S3 |
| **Audit Logging** | ScyllaDB audit log for all queries |

### Valkey

| Measure | Implementation |
|---|---|
| **Encryption in Transit** | In-transit TLS enabled (Valkey 8.1) |
| **Auth Token** | Strong random token for `AUTH` command |
| **Network Isolation** | Deploy inside VPC; no public endpoint |
| **Data Volatility** | No persistent PII in cache; TTL on all keys |
| **Command Renaming** | Disable dangerous commands (`FLUSHALL`, `CONFIG`, etc.) |

---

## Infrastructure Security

### AWS Infrastructure

| Measure | Implementation |
|---|---|
| **VPC Isolation** | All services in private subnets; only ALB/Global Accelerator are public |
| **Security Groups** | Least-privilege ingress/egress rules per service |
| **NACLs** | Stateless network ACLs as second layer of defense |
| **Nitro Isolation** | Graviton5 instances with hardware-verified memory isolation |
| **AWS Shield** | Shield Standard (free) + Shield Advanced for DDoS protection |
| **GuardDuty** | Continuous threat detection on accounts, workloads, and data |
| **AWS Config** | Monitor resource configuration compliance |
| **CloudTrail** | API activity logging across all AWS services |
| **Secrets Manager** | Rotate secrets automatically; never hardcode credentials |
| **IAM Roles** | No long-lived access keys; EC2/ECS tasks use IAM roles |

### Container Security

| Measure | Implementation |
|---|---|
| **Image Scanning** | ECR scanning for vulnerabilities on every push |
| **Minimal Base Images** | Distroless or Alpine-based Docker images |
| **Read-Only Root FS** | Containers run with read-only root filesystem |
| **Non-Root User** | Containers run as non-root user |
| **Resource Limits** | CPU/memory limits on every ECS task definition |
| **Secrets Injection** | Secrets injected via AWS Secrets Manager at runtime, not baked into images |

---

## AI & Agent Security

| Measure | Implementation |
|---|---|
| **AgentCore Token Vault** | AI agents use managed tokens, never raw API keys in code |
| **Prompt Injection Protection** | Bedrock Guardrails block prompt injection attempts |
| **Output Validation** | Agent outputs validated against schema before reaching users |
| **Human-in-Loop** | Moderation actions require human approval |
| **Audit Trail** | Every agent action logged: who, what, when, which model |
| **Policy Boundaries** | Natural-language Cedar policies limit what agents can do |
| **Rate Limit AI Calls** | Max 10 AI assistant calls per user per minute |
| **Data Isolation for AI** | Agent memory is per-user; never shared across tenants |

---

## PlayStore & App Store Compliance

### Android (Google Play Store)

| Requirement | Implementation |
|---|---|
| **Target API Level** | Target latest Android API level (34+) |
| **Privacy Policy** | Host a publicly accessible privacy policy URL |
| **Data Safety Section** | Declare all data collected (account info, messages, contacts, device ID) |
| **Play Integrity API** | Verify app integrity and licensing at startup |
| **Content Rating** | Complete the content rating questionnaire (likely "Everyone" or "Teen") |
| **App Signing** | Use Play App Signing for key management |
| **Publishing Checklist** | - App icon (512x512) + feature graphic (1024x500) <br> - Screenshots (2-8 per device type) <br> - App description (short + full) <br> - Category: Communication <br> - Contact email for support |
| **Permissions** | Declare only: INTERNET, CAMERA, MICROPHONE, NOTIFICATIONS, STORAGE (for media) |
| **GDPR / User Data** | Provide data deletion mechanism (in-app account deletion) |
| **Ads Policy** | If no ads, declare no ads. If ads, use AdMob compliant with policies |
| **In-App Purchases** | If monetizing, use Play Billing (30% commission) |
| **Subscription Policy** | Clear subscription terms, cancellation policy, and refunds |
| **Government Upload** | For India: upload app to MeitY portal for security testing |
| **Family Policy** | If targeting 13-18, comply with Google's Families Policy |
| **Testing Track** | Release to Internal / Closed / Open testing before production |

### iOS (Apple App Store)

| Requirement | Implementation |
|---|---|
| **Minimum iOS Version** | Target iOS 16+ |
| **Privacy Nutrition Labels** | Declare data collection categories in App Store Connect |
| **Sign in with Apple** | Must offer Sign in with Apple if using other social logins |
| **App Tracking Transparency** | Request ATT permission if tracking users across apps |
| **Data Deletion** | Provide in-app mechanism to delete account and associated data |
| **Content Ratings** | Set age rating: 4+ (chat only, no mature content) or 12+ (moderated) |
| **Screenshot Requirements** | 6.5" iPhone + 5.5" iPhone + 12.9" iPad screenshots |
| **App Preview Video** | Optional but recommended (30s max) |
| **App Review Guidelines** | - 2.1: App completeness <br> - 4.1: Copycats (unique design) <br> - 5.1: Privacy (data collection transparency) <br> - 5.6: Developer identity |
| **Subscription (iOS)** | App Store commission: 15% (small business) or 30% (standard) |
| **TestFlight** | Use TestFlight for beta testing (up to 10,000 testers) |
| **Export Compliance** | Declare encryption (TLS 1.3) — may need ERN (Exempt Registration Number) |
| **NDA / Confidentiality** | Distribution via TestFlight is under Apple's NDA |

### Common Requirements (Both Stores)

| Requirement | Implementation |
|---|---|
| **Privacy Policy URL** | Required by both stores |
| **Terms of Service** | Required by both stores |
| **Contact Support** | Support email and/or website |
| **Age Gate** | 13+ minimum age (COPPA compliance) |
| **Content Moderation Notice** | State that user-generated content is moderated |
| **Reporting Mechanism** | In-app user reporting for messages/users |
| **Account Deletion** | Self-service account deletion (GDPR requirement) |
| **Data Export** | User-requested data export (GDPR requirement) |

### Recommended Store Metadata

**App Name:** CloseTalk  
**Short Description:** Fast, private messaging with AI-powered features  
**Full Description:**  
CloseTalk is a modern real-time messaging app that connects you with friends, family, and communities. Features include instant messaging with read receipts, group chats up to 1,000 members, voice and video calling, AI-powered content moderation, smart chat summaries, and end-to-end encryption. Available on all your devices.  
**Keywords:** messaging, chat, secure, group chat, video call, AI assistant  
**Category:** Communication  
**Content Rating:** Teen (mild profanity, moderated)  

---

## Maintenance Plan

### Routine Maintenance

| Frequency | Task | Owner |
|---|---|---|
| **Daily** | - Monitor error rates and latency dashboards <br> - Check SQS dead-letter queues <br> - Review CloudWatch alarms | DevOps |
| **Weekly** | - Rotate API keys and secrets (if auto-rotation not enabled) <br> - Review GuardDuty findings <br> - Check ScyllaDB table health (repair status) | DevOps |
| **Monthly** | - Apply OS/container security patches <br> - Review IAM roles and policies for drift <br> - Analyze cost report and optimize <br> - Review Valkey memory usage and resize if needed <br> - Check Neon branch cleanup (delete stale branches) | DevOps |
| **Quarterly** | - Penetration testing (internal or third-party) <br> - Dependency audit (`flutter pub outdated`, npm audit) <br> - Review and update Bedrock Guardrails policies <br> - Update incident response runbook <br> - Certificate renewal check (TLS certs) <br> - Full disaster recovery drill | Security + DevOps |
| **Annually** | - SOC 2 / ISO 27001 audit (if applicable) <br> - Third-party security audit <br> - Privacy policy review and update <br> - Terms of Service review <br> - App Store metadata refresh <br> - Load testing to validate scalability targets | Team-wide |

### Maintenance Procedures

#### Database Maintenance

```
Neon PostgreSQL:
  - Monthly: VACUUM ANALYZE on high-traffic tables
  - Quarterly: Check for unused indexes; remove if > 10% read ratio
  - Branch cleanup: Delete dev/staging branches older than 30 days

ScyllaDB:
  - Weekly: `nodetool repair` on all keyspaces
  - Monthly: `nodetool cleanup` after node additions/removals
  - Quarterly: Review compaction strategy (TWCS vs STCS)

Valkey:
  - Daily: Monitor eviction rate (> 0 evictions → resize)
  - Weekly: Review TTL distribution; remove unnecessary keys
  - Monthly: Defragmentation if enabled (Valkey 8.1 auto-defrag)
```

#### Backup Verification

```
- Daily: Automated backup status check (all services)
- Weekly: Restore a backup to staging environment and verify data integrity
- Monthly: Documented restore time objective (RTO) and restore point objective (RPO)
```

#### Dependency Updates

```
Flutter:
  flutter pub outdated        # Check for updates
  flutter pub upgrade         # Apply safe upgrades
  flutter analyze            # Verify no regressions

Backend (npm):
  npm audit                   # Check vulnerabilities
  npm update                  # Apply safe updates
  npm run test               # Verify no regressions

Backend (Go):
  go list -u -m all          # Check available updates
  go mod tidy                # Clean up dependencies
  go test ./...              # Verify no regressions
```

### Monitoring & Alerting Thresholds

| Metric | Warning | Critical | Action |
|---|---|---|---|
| API p99 latency | > 200ms | > 500ms | Scale up / investigate |
| Message delivery latency | > 100ms | > 300ms | Check WebTransport/SSE |
| Error rate (5xx) | > 0.5% | > 2% | Rollback / page on-call |
| CPU utilization | > 70% | > 90% | Scale out ECS tasks |
| Memory utilization | > 75% | > 90% | Scale out / increase instance size |
| Valkey evictions | > 0/hr | > 100/hr | Resize cache cluster |
| SQS DLQ messages | > 0 | > 100 | Investigate consumer failures |
| ScyllaDB p99 latency | > 20ms | > 50ms | Check node health / rebalance |
| DB connection count | > 80% of max | > 95% of max | Scale connection pool |
| 4xx error rate | > 5% | > 15% | Check for auth failures / attacks |

### Disaster Recovery

| Scenario | RTO | RPO | Recovery Procedure |
|---|---|---|---|
| Single AZ failure | < 1 min | 0 | Multi-AZ deployment auto-failover |
| Region failure | < 15 min | < 5 min | Route53 DNS failover to secondary region |
| Database corruption | < 1 hr | < 5 min | Point-in-time recovery (Neon WAL) |
| Accidental data deletion | < 1 hr | < 15 min | Restore from ScyllaDB snapshot |
| Security breach | < 1 hr | N/A | Isolate affected resources, rotate all keys, forensics |
| Full AWS account compromise | < 4 hr | < 1 hr | Restore from cross-account backup |

### Maintenance Windows

| Type | Window | Communication |
|---|---|---|
| **Critical patch** | Immediate | Status page + in-app notification |
| **Routine deploy** | Mon–Fri 09:00–17:00 local | No notification (zero-downtime) |
| **Database migration** | Scheduled 02:00–04:00 local | 48hr advance notice via email + app |
| **Major version upgrade** | Scheduled weekend | 1 week advance notice |

---

## Incident Response

### Severity Levels

| Severity | Definition | Response Time |
|---|---|---|
| **S0 — Critical** | Complete service outage, data breach confirmed | < 5 min |
| **S1 — High** | Major feature degraded, potential breach | < 15 min |
| **S2 — Medium** | Partial feature degradation, no data risk | < 1 hr |
| **S3 — Low** | Cosmetic issue, non-critical bug | < 24 hr |

### Response Steps

1. **Detect** — Automated alert or user report triaged
2. **Triage** — Determine severity, assign owner
3. **Contain** — Isolate affected components, block attack vectors
4. **Eradicate** — Remove root cause (rollback, patch, rotate keys)
5. **Recover** — Restore services from backup or redeploy
6. **Post-Mortem** — Document timeline, root cause, prevent recurrence

### Communication Plan

| Stakeholder | S0 | S1 | S2 |
|---|---|---|---|
| **Internal team** | Slack + phone call | Slack | Slack |
| **Users** | Status page + email | Status page | No notification |
| **App Store** | N/A (only if users impacted > 1hr) | N/A | N/A |
| **Regulatory** | Within 72hr (GDPR breach) | N/A | N/A |
