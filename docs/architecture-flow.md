# CloseTalk — Architecture & Service Flow

## 1. High-Level System Architecture

```mermaid
graph TB
    subgraph Clients["Clients"]
        FA["Flutter App<br/>(Android / iOS / Web / Desktop)"]
    end

    subgraph Edge["Edge Layer"]
        GA["AWS Global Accelerator<br/>Anycast IP · Sub-50ms"]
        CF["CloudFront CDN<br/>Static Assets & Media"]
        WAF["AWS WAF<br/>OWASP Top 10 · Rate Limiting"]
    end

    subgraph Gateway["API Gateway Layer"]
        ALB["Application Load Balancer"]
        API["REST API Gateway<br/>/api/v1/*"]
        WT["WebTransport Gateway<br/>/wt/* (QUIC)"]
        WS["WebSocket Gateway<br/>/ws/* (Fallback)"]
    end

    subgraph Compute["Compute Layer (ECS Fargate Graviton5)"]
        MS["Message Service<br/>Send · Receive · History"]
        AS["Auth Service<br/>Login · Register · JWT"]
        PS["Presence Service<br/>Online · Typing · Status"]
        NS["Notification Service<br/>Push · In-App"]
        MOD["Moderation Service<br/>Content Filtering"]
        AI["AI Agent Service<br/>Bedrock AgentCore"]
        US["User Service<br/>Profile · Settings · Contacts"]
        GS["Group Service<br/>Create · Manage · Invite"]
        MEDIA["Media Service<br/>Upload · Download · Optimize"]
    end

    subgraph EventBus["Event Processing Layer"]
        SQS["SQS FIFO Queues<br/>Ordered Delivery · Exactly-Once"]
        EB["EventBridge Pipes<br/>Transform · Filter · Route"]
        SNS["SNS Topics<br/>Push Notifications · Fan-Out"]
        DLQ["Dead Letter Queues<br/>Failed Message Handling"]
    end

    subgraph Cache["Cache Layer (Valkey 8.1)"]
        SESSION["Session Store<br/>JWT Refresh · Device Tokens"]
        PRESENCE["Presence Pub/Sub<br/>Online · Typing Broadcast"]
        RATE["Rate Limiter<br/>Token Bucket per User/IP"]
    end

    subgraph Storage["Storage Layer"]
        PG[("Neon PostgreSQL<br/>Users · Groups · Metadata<br/>Row Level Security")]
        SDB[("ScyllaDB Cloud<br/>Message History · Media Refs<br/>Horizontal Scale")]
        S3[("S3 Buckets<br/>Media Files · Backups · Logs")]
    end

    subgraph AI_Infra["AI Infrastructure"]
        BR["Amazon Bedrock<br/>Claude 3.5 Haiku / Nova Micro"]
        GR["Bedrock Guardrails<br/>Hate · PII · Harassment<br/>Natural-Language Policies"]
        AG["AgentCore<br/>Episodic Memory · Supervisor Agent<br/>Token Vault"]
    end

    subgraph CI_CD["CI/CD Pipeline"]
        GH["GitHub Repository"]
        GA_CI["GitHub Actions<br/>Lint · Test · Build"]
        ECR["Amazon ECR<br/>Container Registry"]
        TF["Terraform<br/>Infrastructure as Code"]
    end

    FA --> GA
    FA --> CF
    GA --> WAF
    WAF --> ALB
    ALB --> API
    ALB --> WT
    ALB --> WS

    API --> MS
    API --> AS
    API --> US
    API --> GS
    API --> MEDIA

    WT --> PS
    WT --> MS
    WT --> AI
    WS --> MS
    WS --> PS

    MS --> SQS
    MS --> SNS
    SQS --> EB
    EB --> MOD
    EB --> AI
    EB --> NS
    SQS --> DLQ

    PS --> PRESENCE
    AS --> SESSION
    AS --> RATE

    MS --> SDB
    US --> PG
    GS --> PG
    MEDIA --> S3

    MOD --> BR
    MOD --> GR
    AI --> AG
    AG --> BR

    GH --> GA_CI
    GA_CI --> ECR
    GA_CI --> TF
    ECR --> Compute
    TF --> Gateway
    TF --> EventBus
    TF --> Storage
```

---

## 2. User Authentication Flow

```mermaid
sequenceDiagram
    actor U as User
    participant FA as Flutter App
    participant GA as Global Accelerator
    participant AS as Auth Service
    participant IDP as Clerk/Auth0 (OAuth)
    participant PG as PostgreSQL
    participant VL as Valkey Session
    participant S3 as S3 (Avatar)

    U->>FA: Enter email/password<br/>or tap Google/Apple Sign-In

    alt OAuth Flow
        FA->>IDP: Open OAuth provider (Google/Apple)
        IDP->>U: Login to provider
        U->>IDP: Grant access
        IDP->>FA: Authorization code
        FA->>AS: POST /auth/oauth { code, provider }
    else Email/Password Flow
        FA->>AS: POST /auth/login { email, password }
    end

    AS->>IDP: Verify access token (OAuth case)
    AS->>PG: SELECT user WHERE email = ?
    alt User not found
        AS->>PG: INSERT new user (sign-up)
        AS->>S3: Upload default avatar (init)
    end

    AS->>AS: Generate JWT (access 15m + refresh 7d)
    AS->>VL: STORE refresh_token, device_id, user_agent
    AS->>FA: 200 { access_token, refresh_token, user_profile }

    FA->>FA: Store tokens in flutter_secure_storage
    FA->>GA: Establish WebTransport connection with JWT
    GA->>AS: Validate JWT
    AS->>VL: Mark user online, subscribe to presence

    Note over FA,VL: User is now authenticated & connected
```

---

## 3. Real-Time Message Delivery Flow

```mermaid
sequenceDiagram
    actor Alice as Alice
    actor Bob as Bob
    participant FA_A as Flutter App (Alice)
    participant GA as Global Accelerator
    participant WT as WebTransport Gateway
    participant MS as Message Service
    participant SQS as SQS FIFO
    participant MOD as Moderation Service
    participant SDB as ScyllaDB
    participant SNS as SNS / Push
    participant FA_B as Flutter App (Bob)

    Alice->>FA_A: Type & send message
    FA_A->>FA_A: Apply optimistic UI (grey tick)

    FA_A->>GA: WebTransport datagram & stream
    GA->>WT: Route to WebTransport gateway
    WT->>MS: Forward message payload

    MS->>MS: Validate schema & permissions
    MS->>MS: Check rate limit (Valkey)

    alt Rate Limited
        MS->>FA_A: Error 429 (too fast)
        FA_A->>Alice: Show "Sending too fast" warning
    else Passes Checks
        MS->>SQS: Send to FIFO queue (group_id = chat_id)
        MS->>FA_A: ACK (message_id, server_timestamp)
        FA_A->>FA_A: Update tick: grey → single tick (delivered to server)

        SQS->>MOD: Message consumed by Moderation Service
        loop Check via Bedrock Guardrails
            MOD->>MOD: Invoke Bedrock Guardrails (hate, PII, harassment)
            alt Flagged
                MOD->>MS: FLEG (quarantine message)
                MS->>S3: Store flagged content for review
                MS->>FA_A: Notify "Message under review"
            end
        end

        MOD->>SDB: INSERT message (persist)

        SDB->>SNS: Trigger push notification

        alt Bob is Online (WebTransport active)
            SNS->>FA_B: Push notification (APNs/FCM)
            FA_B->>WT: Stream event to Bob's session
            WT->>FA_B: Deliver message
            FA_B->>FA_B: Show message, generate read receipt
            FA_B->>WT: Send read receipt (datagram)
            WT->>MS: Update read status
            MS->>SDB: UPDATE read_at timestamp
            MS->>FA_A: Push read receipt event
            FA_A->>FA_A: Update tick: single → double tick (read)
        else Bob is Offline
            SNS->>FA_B: Push notification (APNs/FCM)
            Note over FA_B: Message delivered when Bob reconnects
        end
    end
```

---

## 4. WebTransport Connection & Presence Flow

```mermaid
sequenceDiagram
    participant Client as Flutter Client
    participant GA as Global Accelerator
    participant WT as WebTransport Gateway
    participant PS as Presence Service
    participant VL as Valkey Pub/Sub
    participant Sub as Subscribers (Friends in Chat)

    Client->>GA: QUIC handshake (0-RTT)
    GA->>WT: Route to WebTransport endpoint
    Client->>WT: CONNECT with JWT token

    WT->>WT: Validate JWT
    WT->>PS: Register session (user_id, device_id)

    PS->>VL: PUBLISH user.online { user_id, status: "online" }
    VL-->>Sub: RECEIVE user.online event

    Client->>WT: Send typing indicator datagram
    WT->>PS: Forward typing state
    PS->>VL: PUBLISH chat.typing { chat_id, user_id, is_typing: true }
    VL-->>Sub: RECEIVE chat.typing event
    Sub->>Sub: Show "Alice is typing..."

    Client->>WT: Send presence ping (every 30s)
    WT->>PS: Update TTL for session
    PS->>VL: REFRESH user.presence TTL

    Note over Client,Sub: Connection maintained via QUIC keepalive

    Client->>WT: Send cursor position (unreliable datagram)
    WT->>PS: Forward (fire-and-forget)
    PS->>VL: PUBLISH chat.cursor { chat_id, user_id, position }
    VL-->>Sub: RECEIVE cursor update

    Note over Client,VL: On disconnect:
    Client--xWT: Connection closed
    WT->>PS: Unregister session
    PS->>VL: Check other sessions for this user
    alt No more sessions
        PS->>VL: PUBLISH user.offline { user_id, last_seen: now }
    end
```

---

## 5. Content Moderation Pipeline Flow

```mermaid
flowchart TB
    subgraph Ingress["Message Ingestion"]
        A["User Sends Message"]
        API["API Gateway"]
        SQS_FIFO["SQS FIFO Queue<br/>group_id = chat_id"]
    end

    subgraph Moderation["Moderation Pipeline"]
        LAMBDA["Lambda Consumer"]
        GW["Bedrock Guardrails"]
        BR["Bedrock Runtime<br/>Claude 3.5 Haiku"]
    end

    subgraph Decision["Decision"]
        PASS["✅ Passes Moderation"]
        FLAG["🚩 Flagged Content"]
        REVIEW["👁️ Human Review Queue"]
    end

    subgraph Action["Action"]
        DELIVER["Deliver to Chat"]
        QUAR["Quarantine Message"]
        NOTIFY["Notify Sender & Admins"]
        BLOCK["Block User (Auto-Ban)"]
        S3_LOG["Log to S3 (Audit)"]
    end

    A --> API
    API --> SQS_FIFO
    SQS_FIFO --> LAMBDA
    LAMBDA --> GW
    GW --> BR

    BR --> PASS
    BR --> FLAG

    PASS --> DELIVER
    FLAG --> REVIEW

    REVIEW -- Human Rejects --> QUAR
    REVIEW -- Human Approves --> DELIVER
    REVIEW -- Severe Violation --> BLOCK

    QUAR --> NOTIFY
    BLOCK --> NOTIFY

    QUAR --> S3_LOG
    BLOCK --> S3_LOG
    PASS --> S3_LOG

    style PASS fill:#4CAF50,color:#fff
    style FLAG fill:#FF9800,color:#fff
    style BLOCK fill:#f44336,color:#fff
    style DELIVER fill:#4CAF50,color:#fff
    style QUAR fill:#FF9800,color:#fff
```

---

## 6. Database Architecture (Polyglot Persistence)

```mermaid
erDiagram
    USER ||--o{ MESSAGE : sends
    USER ||--o{ USER_DEVICE : owns
    USER ||--o{ CONTACT : has
    USER }|--|| GROUP_MEMBER : "is member of"
    GROUP ||--|{ GROUP_MEMBER : contains
    GROUP ||--o{ MESSAGE : "receives messages in"
    CONVERSATION ||--|{ MESSAGE : contains
    CONVERSATION }|--|| USER : "between (1:1)"
    CONVERSATION }|--|| GROUP : "or group"

    USER {
        uuid id PK
        string email UK
        string phone UK
        string display_name
        string avatar_url
        string password_hash
        timestamp created_at
        timestamp last_seen
        boolean is_online
        boolean e2ee_enabled
    }

    MESSAGE {
        uuid id PK
        uuid conversation_id FK
        uuid sender_id FK
        text content
        string content_type "text | image | file | voice"
        string media_url
        string status "sent | delivered | read"
        timestamp created_at
        timestamp edited_at
        uuid reply_to_id FK
        int moderation_status "0=pending 1=passed 2=flagged"
    }

    GROUP {
        uuid id PK
        string name
        string description
        string avatar_url
        uuid created_by FK
        timestamp created_at
        int member_limit
        boolean is_public
    }

    GROUP_MEMBER {
        uuid group_id FK
        uuid user_id FK
        string role "admin | member"
        timestamp joined_at
        timestamp muted_until
    }

    USER_DEVICE {
        uuid id PK
        uuid user_id FK
        string device_type "ios | android | web | desktop"
        string device_token
        string refresh_token
        timestamp last_active
    }

    CONTACT {
        uuid user_id FK
        uuid contact_id FK
        timestamp added_at
        boolean is_blocked
    }

    CONVERSATION {
        uuid id PK
        string type "direct | group"
        uuid target_id "user_id or group_id"
        timestamp last_message_at
    }
```

### Database Mapping to Storage Engines

```mermaid
flowchart LR
    subgraph Neon["Neon Serverless PostgreSQL"]
        U[users]
        G[groups]
        GM[group_members]
        C[contacts]
        UD[user_devices]
        CONV[conversations]
    end

    subgraph ScyllaDB["ScyllaDB Cloud"]
        MSG[messages]
        MR[message_reads]
        MF[message_flags]
        ML[message_likes]
    end

    subgraph Valkey["Valkey 8.1"]
        S[sessions]
        P[presence]
        RT[rate_limiter]
        PUB[pub/sub channels]
    end

    subgraph S3["Amazon S3"]
        MEDIA[media/images/files]
        BACKUP[backups]
        LOG[moderation_logs]
    end

    Neon -->|RLS policies| App
    ScyllaDB -->|Alternator API| App
    Valkey -->|low-latency| App
    S3 -->|presigned URLs| App

    classDef neon fill:#336791,color:#fff
    classDef scylla fill:#3949AB,color:#fff
    classDef valkey fill:#D81B60,color:#fff
    classDef s3 fill:#569A31,color:#fff
    class App neon,scylla,valkey,s3
```

---

## 7. Deployment & CI/CD Flow

```mermaid
flowchart LR
    DEV["👨‍💻 Developer Push"] --> GH["GitHub Repository"]
    GH --> ACTIONS["GitHub Actions"]

    subgraph CI["CI Pipeline"]
        LINT["flutter analyze<br/>go vet / npm lint"]
        TEST["flutter test<br/>go test / jest"]
        BUILD["flutter build<br/>docker build"]
        SCAN["Trivy / Snyk<br/>Vulnerability Scan"]
    end

    subgraph CD["CD Pipeline"]
        ECR_PUSH["Push to ECR"]
        TERRAFORM["Terraform Plan/Apply"]
        MIGRATE["Neon DB Branch + Migrate"]
        DEPLOY_STAGING["Deploy to Staging"]
        E2E["E2E Tests on Staging"]
        DEPLOY_PROD["Deploy to Production"]
        SMOKE["Smoke Tests on Prod"]
    end

    subgraph Env["Environments"]
        DEV_ENV["Development<br/>Neon Branch per PR"]
        STAGING["Staging<br/>Full Mirror"]
        PROD["Production<br/>Multi-AZ"]
    end

    ACTIONS --> CI
    CI --> CD
    CD --> DEV_ENV
    CD --> STAGING
    CD --> PROD

    style PROD fill:#f44336,color:#fff
    style STAGING fill:#FF9800,color:#fff
    style DEV_ENV fill:#4CAF50,color:#fff
```

---

## 8. Service-to-Service Communication

```mermaid
flowchart TB
    subgraph Clients["Client Layer"]
        FA[Flutter App]
        WB[Web Browser]
    end

    subgraph Edge["Edge / CDN"]
        GA[Global Accelerator<br/>port 443 UDP/QUIC]
        CF[CloudFront<br/>Static Assets]
    end

    subgraph Public["Public Subnet"]
        ALB[ALB<br/>HTTPS / WSS]
        WT_GW[WebTransport GW<br/>QUIC]
    end

    subgraph Private["Private Subnet"]
        MS[Message Service<br/>:8080]
        AS[Auth Service<br/>:8081]
        PS[Presence Service<br/>:8082]
        NS[Notification Service<br/>:8083]
        MOD[Moderation Service<br/>:8084]
        AI[AI Agent Service<br/>:8085]
        US[User Service<br/>:8086]
        GS[Group Service<br/>:8087]
        MEDIA[Media Service<br/>:8088]
    end

    subgraph Data["Data Subnet"]
        PG[(Neon<br/>PostgreSQL<br/>:5432)]
        SDB[(ScyllaDB<br/>:9042)]
        VL[(Valkey<br/>:6379)]
    end

    subgraph AWS_Services["AWS Managed"]
        SQS[SQS FIFO]
        EB[EventBridge Pipes]
        SNS[SNS]
        S3[S3 Buckets]
        BR[Bedrock]
    end

    FA --> GA
    WB --> CF
    GA --> ALB
    GA --> WT_GW

    ALB --> MS
    ALB --> AS
    ALB --> US
    ALB --> GS

    WT_GW --> PS
    WT_GW --> MS

    MS --> SQS
    MS <--> SDB
    MS --> VL
    MS --> PG

    AS --> PG
    AS --> VL

    PS --> VL

    NS --> SNS
    SNS --> FA

    MOD --> SQS
    MOD --> BR
    MOD --> S3

    AI --> BR
    AI --> PG

    US --> PG
    GS --> PG
    MEDIA --> S3

    style Public fill:#FFE0B2,color:#333
    style Private fill:#BBDEFB,color:#333
    style Data fill:#C8E6C9,color:#333
    style AWS_Services fill:#E1BEE7,color:#333
```

---

## 9. Data Flow: Message Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Composing: User types message
    Composing --> Sending: Hit send

    Sending --> Validating: Client sends to server
    Validating --> RateChecked: Schema & permissions pass
    Validating --> Rejected: Validation fails
    Rejected --> [*]: Show error

    RateChecked --> Queued: Under rate limit
    RateChecked --> Throttled: Over rate limit
    Throttled --> Composing: Retry after cooldown

    Queued --> Moderating: SQS FIFO consumes
    Moderating --> Persisted: Passes moderation
    Moderating --> Flagged: Content flagged
    Flagged --> ReviewQueue: Human review
    ReviewQueue --> Persisted: Approved
    ReviewQueue --> Quarantined: Rejected
    Quarantined --> [*]: Show "removed" to recipient

    Persisted --> Delivering: Dispatch to recipient(s)
    Delivering --> Delivered: Recipient online (WebTransport)
    Delivering --> PendingPush: Recipient offline
    PendingPush --> PushSent: APNs/FCM sent
    PushSent --> Delivered: Recipient opens app

    Delivered --> Read: Recipient views
    Read --> [*]: Read receipt sent to sender
```

---

## 10. Scaling Flow (Auto-Scaling)

```mermaid
flowchart LR
    subgraph Trigger["Auto-Scaling Triggers"]
        CPU["CPU > 70%"]
        MEM["Memory > 75%"]
        LAT["p99 Latency > 200ms"]
        CONN["Active Connections > 80% Capacity"]
    end

    subgraph ScaleOut["Scale-Out Process"]
        CLOUDWATCH["CloudWatch Alarm"]
        ASG["ECS Service Auto-Scaling"]
        TASK["New Fargate Task Spawned<br/>(~30s warm-up)"]
        REGISTER["Register with ALB<br/>Health Check Pass"]
    end

    subgraph ScaleIn["Scale-In Process"]
        CW_IN["CloudWatch Alarm (low traffic)"]
        ASG_IN["Cooldown Period (300s)"]
        DRAIN["Connection Draining<br/>(30s grace)"]
        DEREGISTER["Deregister from ALB"]
    end

    CPU --> CLOUDWATCH
    MEM --> CLOUDWATCH
    LAT --> CLOUDWATCH
    CONN --> CLOUDWATCH

    CLOUDWATCH --> ASG
    ASG --> TASK
    TASK --> REGISTER
    REGISTER --> SVC["Service Capacity +1"]

    CW_IN --> ASG_IN
    ASG_IN --> DRAIN
    DRAIN --> DEREGISTER
    DEREGISTER --> SVC_IN["Service Capacity -1"]

    NB["Note: Database layer scales independently:<br/>Neon: compute auto-pause/resume<br/>ScyllaDB: add nodes via Tablets rebalancing<br/>Valkey: cluster mode sharding"]

---

## 11. Media Upload & Processing Pipeline

```mermaid
sequenceDiagram
    participant Client as Flutter Client
    participant MS as Media Service
    participant S3 as S3 Bucket
    participant Lambda as Async Lambda
    participant CF as CloudFront CDN
    participant VL as Valkey (Thumbnail Cache)
    participant CV as ClamAV (Virus Scan)

    Client->>MS: POST /media/upload-url { file_type, file_size, chat_id }
    MS->>MS: Validate file size & type
    MS->>S3: Generate presigned PUT URL (expires in 5 min)
    MS->>Client: 200 { upload_url, media_id, cdn_url }

    Client->>S3: PUT directly to S3 (raw file, original quality)
    S3->>Client: 201 ETag
    Client->>MS: POST /media/confirm { media_id, etag }

    Note over S3,CV: Server never touches raw bytes (no quality loss)

    S3->>Lambda: Trigger on s3:ObjectCreated

    par Virus Scan
        Lambda->>S3: Read file bytes
        Lambda->>CV: Scan for malware
        alt Malware Detected
            Lambda->>S3: Move file to quarantine/
            Lambda->>MS: Update status: "quarantined"
            MS->>Client: Alert "File flagged for review"
        end
    and Thumbnail Generation (images)
        Lambda->>Lambda: Generate thumbnails (100x100, 400x400, 1200x1200)
        Lambda->>S3: Store thumbnails
    and Video Transcoding (if video)
        Lambda->>Lambda: Transcode to HLS (1080p, 720p, 480p)
        Lambda->>S3: Store HLS segments + playlist
    and Image Optimization
        Lambda->>Lambda: Convert to WebP/AVIF
        Lambda->>S3: Store optimized versions
    end

    Lambda->>VL: Cache thumbnail URLs (TTL: 1hr)
    Lambda->>MS: Update status: "ready"
    MS->>Client: Push notification: media ready

    Client->>CF: GET /media/{media_id}/thumbnail.jpg
    CF->>S3: Fetch from origin (if not cached)
    CF->>Client: Deliver thumbnail (cached at edge)
```

## 12. Privacy-Preserving Contact Discovery Flow

```mermaid
sequenceDiagram
    participant Client as Flutter Client
    participant US as User Service
    participant PG as PostgreSQL
    participant VL as Valkey (Cache)

    Note over Client: User grants contact permission
    Client->>Client: Read phone contacts (local only)
    Client->>Client: SHA-256 hash each phone number

    Client->>US: POST /contacts/discover { hashes: [hash1, hash2, ...] }

    Note over US: Server NEVER sees raw phone numbers

    US->>VL: Check cache for known hashes
    alt Cache miss
        US->>PG: SELECT user_id, display_name, avatar_url WHERE phone_hash IN (...)
        PG->>US: Return matched users
        US->>VL: Cache results (TTL: 24hr)
    end

    US->>Client: 200 { contacts: [{ user_id, display_name, avatar_url, is_registered: true }] }

    Client->>Client: Show "X contacts on CloseTalk"
    Client->>Client: Mark registered contacts with app icon

    Note over Client,US: No raw contacts stored on server — ever
```

## 13. Account Recovery Flow

```mermaid
sequenceDiagram
    actor U as User
    participant Client as Flutter App
    participant AS as Auth Service
    participant PG as PostgreSQL
    participant SM as SES (Email)

    Note over U: User lost phone / can't log in

    U->>Client: Tap "Forgot / Lost access?"

    alt Have Recovery Codes
        Client->>U: Enter one of 10 recovery codes
        U->>Client: Enter code XXXXX-XXXXX
        Client->>AS: POST /auth/recover { code }
        AS->>PG: Verify recovery code hash
        alt Valid
            AS->>PG: Invalidate used code, generate new session
            AS->>Client: 200 { session_token, prompt: "Link new device?" }
        else Invalid
            AS->>Client: 401 { attempts_remaining: N }
        end

    else Email Recovery
        Client->>AS: POST /auth/recover/email { email }
        AS->>SM: Send recovery link to registered email
        SM->>U: Click link (expires in 15 min)
        U->>Client: Open link → verify identity
        Client->>AS: POST /auth/recover/verify { token }
        AS->>Client: 200 { session_token }

    else Trusted Device
        Client->>AS: POST /auth/recover/trusted { device_id }
        AS->>Client: Show list of trusted devices
        U->>Client: Select trusted device
        Client->>AS: POST /auth/recover/approve { device_id }
        Note over AS,Client: Push notification to trusted device
        AS->>Client: 200 { session_token } (after approval)

    end

    Note over U: Recovery codes are displayed ONCE at signup
    Note over U: User must save them (screenshot / print / password manager)
```

## 14. Full-Text Search Flow

```mermaid
sequenceDiagram
    participant Client as Flutter Client
    participant SS as Search Service
    participant ES as Elasticsearch
    participant VL as Valkey (Cache)
    participant MS as Message Service

    Note over Client: User types in search bar
    Client->>Client: Debounce input (300ms)

    Client->>SS: GET /search?q=meeting+tomorrow&chat_id=optional&from=date&to=date&sender=user_id&page=1

    SS->>VL: Check cache for identical query
    alt Cache hit
        VL->>SS: Return cached results
    else Cache miss
        SS->>ES: Search index with filters + relevance scoring
        ES->>SS: Return hits with scores, highlights, pagination
        SS->>VL: Cache results (TTL: 5 min)
    end

    SS->>Client: 200 { results: [{ message_id, chat_id, snippet, sender, date, score }], total, page }

    Client->>Client: Display results grouped by chat, sorted by relevance

    Note over Client: Tap result → navigate to exact message in chat

    SS->>MS: Log search query (anonymized, for analytics)
```

## 15. Stories / Status Flow

```mermaid
sequenceDiagram
    actor Alice as Alice (Poster)
    actor Bob as Bob (Viewer)
    participant Client_A as Flutter (Alice)
    participant SS as Status Service
    participant S3 as S3
    participant SDB as ScyllaDB
    participant Client_B as Flutter (Bob)

    Note over Alice,Bob: POSTING A STATUS

    Alice->>Client_A: Take photo / record video / type text
    Client_A->>SS: POST /status { type: "image"|"video"|"text", content, privacy: "contacts"|"close_friends"|"public" }
    SS->>S3: Store media (presigned URL)
    SS->>SDB: INSERT status { user_id, media_url, type, privacy, created_at, expires_at: now+24h }
    SS->>Client_A: 200 { status_id }

    Note over Alice,Bob: VIEWING STATUSES

    Bob->>Client_B: Open status tab
    Client_B->>SS: GET /status/updates
    SS->>SDB: SELECT statuses WHERE (privacy = "public" OR viewer in allowed_list) AND expires_at > now
    SS->>Client_B: 200 { updates: [{ user, statuses: [...] }] }

    Bob->>Client_B: Tap to view Alice's status
    Client_B->>SS: POST /status/{id}/view { viewer_id: bob }
    SS->>SDB: INSERT status_view { status_id, viewer_id, viewed_at }
    SS->>Client_B: 200 OK

    Note over Alice: Later...
    Alice->>Client_A: Open "Who viewed my status"
    Client_A->>SS: GET /status/{id}/views
    SS->>SDB: SELECT viewers WHERE status_id = ?
    SS->>Client_A: 200 { viewers: [{ user_id, display_name, viewed_at }] }

    Note over SS,SDB: Auto-cleanup: Lambda runs every hour, deletes expired statuses (>24h)
```

## 16. Broadcast & Channels Flow

```mermaid
sequenceDiagram
    actor Admin as Channel Admin
    actor Sub as Subscriber
    participant Client_A as Flutter (Admin)
    participant CS as Channel Service
    participant SDB as ScyllaDB
    participant SNS as SNS Push
    participant Client_B as Flutter (Subscriber)

    Note over Admin,Sub: CREATING A CHANNEL

    Admin->>Client_A: Create channel { name, description, avatar }
    Client_A->>CS: POST /channels { name, description, is_public: true }
    CS->>SDB: INSERT channel
    CS->>Client_A: 200 { channel_id, invite_link }

    Admin->>Client_A: Share invite link with subscribers

    Sub->>Client_B: Tap invite link
    Client_B->>CS: POST /channels/{id}/subscribe
    CS->>SDB: INSERT channel_subscriber { channel_id, user_id, subscribed_at }
    CS->>Client_B: 200 { channel_name, message_count }

    Note over Admin,Sub: SENDING A BROADCAST

    Admin->>Client_A: Send message to channel
    Client_A->>CS: POST /channels/{id}/messages { content }
    CS->>SDB: INSERT channel_message
    CS->>SDB: SELECT subscribers WHERE channel_id = ?
    CS->>SNS: Fan-out push notification to all subscribers
    SNS-->>Client_B: Push notification
    Client_B->>CS: GET /channels/{id}/messages?since=last_id
    CS->>Client_B: 200 { messages: [...] }
```

## 17. Graceful Degradation & Circuit Breakers

```mermaid
flowchart TB
    subgraph Normal["Normal Operation"]
        REQ["Request Incoming"]
        CB_OK["Circuit Breaker: CLOSED"]
        PROXY["Proxy to Service"]
        RESP["Return Response"]
    end

    subgraph Degraded["Service Failure"]
        REQ_FAIL["Request Incoming"]
        CB_OPEN["Circuit Breaker: OPEN<br/>(Fail Fast)"]
        FALLBACK["Fallback Handler"]
    end

    subgraph Recovery["Recovery"]
        CB_HALF["Circuit Breaker: HALF-OPEN<br/>(Test Request)"]
        TEST_OK["Test Succeeds"]
        TEST_FAIL["Test Fails"]
    end

    REQ --> CB_OK
    CB_OK --> PROXY
    PROXY -->|Error Threshold Exceeded| CB_OPEN
    PROXY --> RESP

    REQ_FAIL --> CB_OPEN
    CB_OPEN --> FALLBACK

    FALLBACK -->|Timeout elapsed| CB_HALF
    CB_HALF --> TEST_OK
    CB_HALF --> TEST_FAIL
    TEST_OK --> CB_OK
    TEST_FAIL --> CB_OPEN

    subgraph Fallbacks["Per-Service Fallbacks"]
        AI["AI Moderation Down"] --> AI_FB["Pass-through + Deferred Scan"]
        DB["Database Degraded"] --> DB_FB["Read-Only Mode + Queue Writes"]
        SEARCH["Search Down"] --> SRCH_FB["Basic SQL LIKE + No Relevance"]
        WT["WebTransport Down"] --> WT_FB["SSE → WebSocket Fallback"]
        PUSH["Push Service Down"] --> PUSH_FB["Poll on Reconnect"]
    end

    FALLBACK --> Fallbacks

    style Normal fill:#4CAF50,color:#fff
    style Degraded fill:#FF9800,color:#fff
    style Recovery fill:#2196F3,color:#fff
    style CB_OK fill:#4CAF50,color:#fff
    style CB_OPEN fill:#f44336,color:#fff
    style CB_HALF fill:#FF9800,color:#fff
```

## 18. Offline Message Queue & Catch-Up Sync

```mermaid
sequenceDiagram
    participant Sender as Sender Device
    participant MS as Message Service
    participant SDB as ScyllaDB
    participant VL as Valkey
    participant SNS as Push Notification
    participant Recipient as Recipient (Reconnecting)

    Note over Sender,Recipient: User goes offline

    Sender->>MS: Send message
    MS->>SDB: Persist message (status: "pending")

    MS->>VL: Check recipient online status
    alt Recipient OFFLINE
        MS->>SNS: Push notification via APNs/FCM

        Note over SNS,Recipient: Days later — recipient reconnects

        Recipient->>MS: WebTransport reconnect + JWT
        MS->>VL: Update status to online

        Recipient->>MS: GET /sync/messages?after={last_known_id}

        MS->>SDB: Query pending messages > last_known_id for this user
        SDB->>MS: Return backlog

        MS->>Recipient: Deliver messages (batched, ordered)

        Note over Recipient: Apply exponential backoff for large backlogs:
        Note over Recipient: < 100 msgs → deliver all immediately
        Note over Recipient: 100-1000 msgs → deliver in 50-msg batches
        Note over Recipient: > 1000 msgs → deliver first 500, rest on demand

        Recipient->>MS: Process each batch
        Recipient->>MS: GET /sync/messages?after={last_id}
        MS->>Recipient: Next batch (if any)
    end

    MS->>MS: Update message status to "delivered"
    MS->>Sender: Push delivery receipt (if sender online)
```

## 19. Feature Flag System

```mermaid
flowchart TB
    subgraph Admin["Admin Console"]
        FF_TOGGLE["Toggle Feature Flag"]
        FF_CONFIG["Set Rollout %<br/>Set User Segments<br/>Set Platform Filter"]
    end

    subgraph Storage["Flag Storage"]
        VL_FLAGS["Valkey (Hot)<br/>TTL: 5 min"]
        PG_FLAGS["PostgreSQL (Source of Truth)"]
    end

    subgraph Client["Client Request"]
        APP_START["App Start / Event"]
        SDK_CHECK["Feature Flag SDK<br/>Check: isEnabled('feature_x')"]
    end

    subgraph Decision["Decision Logic"]
        ROLLOUT["Rollout % Check<br/>user_id hash < %"]
        SEGMENT["Segment Check<br/>region / platform / plan"]
        KILL["Kill Switch Check<br/>globally disabled?"]
    end

    Admin -->|Write| PG_FLAGS
    PG_FLAGS -->|Sync every 5s| VL_FLAGS

    APP_START --> SDK_CHECK
    SDK_CHECK --> VL_FLAGS
    VL_FLAGS --> KILL
    KILL -->|Killed| BLOCK["Feature Hidden"]
    KILL -->|Active| ROLLOUT
    ROLLOUT -->|In Rollout| ENABLE["Feature Enabled"]
    ROLLOUT -->|Not in Rollout| BLOCK

    SEGMENT -->|Matches| ENABLE
    SEGMENT -->|No Match| BLOCK

    subgraph UseCases["Use Cases"]
        UC1["Gradual Rollout: 1% → 5% → 25% → 100%"]
        UC2["Kill Switch: Disable AI Moderation instantly"]
        UC3["Platform Filter: iOS only beta feature"]
        UC4["Region Filter: Enable Stories in India first"]
        UC5["A/B Test: 50% see new UI, 50% see old"]
    end
```
