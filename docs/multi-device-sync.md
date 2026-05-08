# CloseTalk — Multi-Device Sync Protocol

## Overview

CloseTalk supports **native multi-device** from day 1 — unlike WhatsApp which retrofitted it years later and required the phone to stay online as a relay. In CloseTalk, each device connects independently to the server with its own WebTransport connection, its own identity key, and its own session.

### Key Design Principles

1. **Phone is NOT a relay** — every device is equal and independent
2. **Each device has its own identity key** — E2EE sessions are per-device-pair
3. **Messages sync in real-time** — via server-side fan-out to all linked devices
4. **History sync on link** — new device fetches message history from ScyllaDB
5. **Device revocation is instant** — terminate all connections of revoked device

```
┌────────────────────────────────────────────────────┐
│                    User Alice                        │
│                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │  Phone   │  │  Tablet  │  │ Desktop  │          │
│  │ (Main)   │  │ (Linked) │  │ (Linked) │          │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
│       │             │             │                 │
│       │  Independent WebTransport Connections        │
│       │  (Each has own JWT + identity key)           │
└───────┼─────────────┼─────────────┼─────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼─────────────────┐
│                   Server                              │
│                                                       │
│  ┌─────────────────────────────────────────────┐     │
│  │         Message Service                       │     │
│  │  Receives message → persists to ScyllaDB     │     │
│  │  → fans out to ALL linked devices             │     │
│  └─────────────────────────────────────────────┘     │
│                                                       │
│  ┌─────────────────────────────────────────────┐     │
│  │         Valkey Session Store                  │     │
│  │  user_123:{                                    │     │
│  │    devices: [                                  │     │
│  │      { id: "phone", last_active: ... },        │     │
│  │      { id: "tablet", last_active: ... },       │     │
│  │      { id: "desktop", last_active: ... }       │     │
│  │    ]                                           │     │
│  │  }                                             │     │
│  └─────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

---

## Device Lifecycle

### 1. Linking a New Device

```mermaid
sequenceDiagram
    participant P as Primary Device (Phone)
    participant N as New Device (Desktop)
    participant AS as Auth Service
    participant VL as Valkey
    participant DB as ScyllaDB

    N->>N: Generate device identity key pair
    N->>P: Display QR code with public key + device info

    P->>P: Scan QR, prompt user "Link this device?"
    P->>AS: POST /devices/link { device_pub_key, device_name, device_type }
    AS->>AS: Verify primary device JWT
    AS->>AS: Generate device-specific JWT for new device
    AS->>VL: STORE device_123:{ user_id, device_id, pub_key, linked_at, last_active }
    AS->>P: Return device_token + one-time setup code
    P->>N: Send session_token + device_token (via QR/secure channel)

    N->>N: Store tokens in secure storage
    N->>AS: Connect with device_token
    AS->>VL: Mark device active, add to user's active device list

    Note over N,DB: Sync message history
    N->>AS: GET /sync/messages?since={last_message_id}
    AS->>DB: SELECT messages WHERE user_id AND created_at > since
    AS->>N: Batch deliver history (paginated)
    N->>N: Index messages locally, update UI
```

### 2. Sending a Message (Multi-Device Flow)

```mermaid
sequenceDiagram
    participant S as Sender Device
    participant MS as Message Service
    participant SDB as ScyllaDB
    participant R1 as Recipient Device 1
    participant R2 as Recipient Device 2
    participant R3 as Recipient Device 3 (offline)

    S->>MS: POST /messages { chat_id, content, device_id }
    MS->>MS: Validate, rate-limit, store
    MS->>SDB: INSERT message

    MS->>MS: Look up recipient's linked devices in Valkey

    par Send to Device 1 (online)
        MS->>R1: Push via WebTransport stream
        R1->>MS: ACK (delivered)
    and Send to Device 2 (online)
        MS->>R2: Push via WebTransport stream
        R2->>MS: ACK (delivered)
    and Send to Device 3 (offline)
        MS->>MS: Queue for later delivery
        MS->>SNS: Push notification (APNs/FCM)

    MS->>S: Delivery status update
```

### 3. Receiving Messages on Offline Device (Catch-Up Sync)

When a device comes back online:

```mermaid
sequenceDiagram
    participant D as Device (reconnecting)
    participant WT as WebTransport Gateway
    participant MS as Message Service
    participant DB as ScyllaDB

    D->>WT: QUIC handshake + JWT
    WT->>D: Connected + last_message_id

    D->>D: Compare last_message_id with local latest
    alt Local is behind
        D->>MS: GET /sync/messages?after={last_message_id}
        MS->>DB: Query messages > after_id for this user's chats
        MS->>D: Batch 1: messages [latest 50]
        D->>D: Apply locally, request next batch
        MS->>D: Batch 2: next 50
        D->>D: Continue until caught up
    end

    D->>WT: Resume real-time stream
```

### 4. Device Revocation

```mermaid
sequenceDiagram
    participant U as User (on Phone)
    participant AS as Auth Service
    participant VL as Valkey
    participant D as Revoked Device (Desktop)
    participant WT as WebTransport Gateway

    U->>AS: POST /devices/revoke { device_id: "desktop-abc" }
    AS->>AS: Verify user JWT
    AS->>VL: DELETE device_session:desktop-abc
    AS->>U: 200 OK (device revoked)

    par Push revocation to device
        AS->>WT: Force-close connection device_id=desktop-abc
        WT--xD: Connection closed (reason: device_revoked)
        D->>D: Show "Logged out remotely"
        D->>D: Clear local data
    and Update active sessions list
        AS->>VL: UPDATE user_sessions:{user_id} (remove device)
    end

    U->>U: Updated device list shown in settings
```

---

## Data Structures

### Device Record (Valkey)

```json
{
  "device_id": "uuid-v4",
  "user_id": "uuid-v4",
  "device_name": "Alice's MacBook Pro",
  "device_type": "desktop",       // phone | tablet | desktop | web
  "platform": "macos",            // android | ios | windows | macos | linux | web
  "public_key": "base64-encoded-ed25519-pubkey",
  "push_token": "fcm-or-apns-token",
  "linked_at": "2026-05-09T10:00:00Z",
  "last_active": "2026-05-09T14:30:00Z",
  "app_version": "1.0.0",
  "is_active": true
}
```

### Message Sync Response

```json
{
  "sync_id": "uuid",
  "messages": [
    {
      "message_id": "uuid",
      "chat_id": "uuid",
      "sender_id": "uuid",
      "sender_device_id": "uuid",
      "content_type": "text",
      "content": "Hello!",
      "created_at": "2026-05-09T14:00:00Z",
      "status": "sent"
    }
  ],
  "has_more": false,
  "next_cursor": "cursor-token"
}
```

---

## E2EE Key Distribution (Multi-Device)

For E2EE chats, each device pair has its own session key:

```
User A (Phone) ─────────────────── User B (Phone)
       │                                    │
       ├── Session Key A-phone ↔ B-phone    │
       │                                    │
User A (Desktop) ────────────────── User B (Desktop)
       │                                    │
       ├── Session Key A-desktop ↔ B-desktop│
       │                                    │
User A (Tablet) ─────────────────── User B (Tablet)
       │                                    │
       └── Session Key A-tablet ↔ B-tablet  ┘
```

When User A sends a message from their phone, it is:
1. E2EE encrypted with the session key for `A-phone → B-phone`
2. Sent to the server
3. Server decrypts it (if server-side delivery) OR stores encrypted (if true E2EE)
4. Delivered to ALL of B's devices using the per-device-pair key

---

## Device Limits & Policies

| Constraint | Limit |
|---|---|
| Max devices per user | 5 (configurable) |
| Max devices per platform | 2 (e.g., 2 phones, 2 tablets) |
| History sync batch size | 50 messages per page |
| History sync max depth | 30 days (configurable) |
| Device idle timeout | 30 days (auto-revoke if inactive) |
| Link cooldown | 5 min between new device links |
