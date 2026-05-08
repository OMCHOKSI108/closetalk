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
