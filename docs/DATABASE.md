# CloseTalk — Database Schema & Data Model

> Complete schema for all four persistence engines: Neon PostgreSQL, ScyllaDB Cloud, Valkey 8.1, and Elasticsearch.

---

## 1. Polyglot Persistence Overview

| Engine | Data | Access Pattern | Consistency |
|---|---|---|---|
| **Neon PostgreSQL** | Users, groups, contacts, settings, conversations | ACID, row-level security | Strong (primary) |
| **ScyllaDB Cloud** | Messages, polls, statuses, message reads/reactions | High-write throughput, time-series | Tunable (eventual per chat) |
| **Valkey 8.1** | Sessions, presence, rate limits, pub/sub, thumbnail cache | Sub-millisecond reads/writes | Eventual |
| **Elasticsearch** | Message search index | Full-text search, relevance scoring | Near-real-time |

---

## 2. Neon PostgreSQL Schema

### 2.1 Enable Extensions

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pgaudit";
```

### 2.2 Table: `users`

```sql
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           TEXT UNIQUE,
    phone           TEXT UNIQUE,
    phone_hash      TEXT UNIQUE,          -- SHA-256 of phone number (privacy)
    display_name    TEXT NOT NULL,
    bio             TEXT DEFAULT '',
    avatar_url      TEXT DEFAULT '',
    password_hash   TEXT,
    oauth_provider  TEXT,                 -- 'google' | 'apple' | 'github' | NULL
    oauth_id        TEXT,
    is_active       BOOLEAN DEFAULT true,
    is_admin        BOOLEAN DEFAULT false,
    e2ee_enabled    BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    last_seen       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ           -- soft delete, NULL = active
);

CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_phone_hash ON users(phone_hash) WHERE phone_hash IS NOT NULL;
CREATE INDEX idx_users_display_name ON users USING gin(display_name gin_trgm_ops);
CREATE INDEX idx_users_created_at ON users(created_at);
```

### 2.3 Table: `recovery_codes`

```sql
CREATE TABLE recovery_codes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash       TEXT NOT NULL,         -- SHA-256 of the recovery code
    is_used         BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now(),
    used_at         TIMESTAMPTZ
);

CREATE INDEX idx_recovery_codes_user ON recovery_codes(user_id);
-- Only allow 10 active (unused) codes per user
CREATE UNIQUE INDEX idx_recovery_codes_active_limit
    ON recovery_codes(user_id) WHERE is_used = false;
```

### 2.4 Table: `user_devices`

```sql
CREATE TABLE user_devices (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name     TEXT NOT NULL,
    device_type     TEXT NOT NULL CHECK (device_type IN ('phone', 'tablet', 'desktop', 'web')),
    platform        TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    public_key      TEXT,                  -- Ed25519 public key for E2EE
    push_token      TEXT,                  -- FCM or APNs token
    app_version     TEXT,
    is_active       BOOLEAN DEFAULT true,
    linked_at       TIMESTAMPTZ DEFAULT now(),
    last_active     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_active ON user_devices(user_id) WHERE is_active = true;
```

### 2.5 Table: `user_settings`

```sql
CREATE TABLE user_settings (
    user_id                     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    last_seen_visibility        TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (last_seen_visibility IN ('nobody', 'everyone', 'contacts', 'contacts_except')),
    profile_photo_visibility    TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (profile_photo_visibility IN ('nobody', 'everyone', 'contacts')),
    read_receipts_global        BOOLEAN DEFAULT true,
    read_receipts_overrides     JSONB DEFAULT '{}',  -- { chat_id: false, ... }
    group_add_permission        TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (group_add_permission IN ('everyone', 'contacts', 'contacts_except')),
    status_privacy              TEXT NOT NULL DEFAULT 'contacts'
                                CHECK (status_privacy IN ('contacts', 'close_friends', 'public')),
    close_friends               UUID[] DEFAULT '{}',  -- array of user_ids
    disappearing_msg_default    TEXT DEFAULT 'off'
                                CHECK (disappearing_msg_default IN ('off', '5s', '30s', '5m', '1h', '24h')),
    language                    TEXT DEFAULT 'en',
    updated_at                  TIMESTAMPTZ DEFAULT now()
);
```

### 2.6 Table: `contacts`

```sql
CREATE TABLE contacts (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    added_at        TIMESTAMPTZ DEFAULT now(),
    is_favorite     BOOLEAN DEFAULT false,
    custom_name     TEXT,                  -- user's custom label for this contact
    PRIMARY KEY (user_id, contact_id),
    CHECK (user_id != contact_id)         -- no self-contact
);

CREATE INDEX idx_contacts_user ON contacts(user_id);
```

### 2.7 Table: `blocks`

```sql
CREATE TABLE blocks (
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, blocked_user_id),
    CHECK (user_id != blocked_user_id)
);

CREATE INDEX idx_blocks_user ON blocks(user_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_user_id);  -- for enforcing block checks
```

### 2.8 Table: `conversations`

```sql
CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type            TEXT NOT NULL CHECK (type IN ('direct', 'group')),
    created_at      TIMESTAMPTZ DEFAULT now(),
    last_message_at TIMESTAMPTZ,
    message_count   BIGINT DEFAULT 0,
    -- For direct chats: the two participants
    -- For group chats: references groups.id
    metadata        JSONB DEFAULT '{}'     -- flexible metadata
);

CREATE INDEX idx_conversations_last_message ON conversations(last_message_at DESC);
```

### 2.9 Table: `conversation_participants`

```sql
CREATE TABLE conversation_participants (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ DEFAULT now(),
    last_read_at    TIMESTAMPTZ,          -- for unread count tracking
    is_muted        BOOLEAN DEFAULT false,
    disappeared_at  TIMESTAMPTZ,          -- NULL = off, else auto-delete at this time
    retention_days  INTEGER DEFAULT 0,    -- 0 = off, 30, 90, 365
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX idx_conv_participants_user ON conversation_participants(user_id);
```

### 2.10 Table: `groups`

```sql
CREATE TABLE groups (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    description     TEXT DEFAULT '',
    avatar_url      TEXT DEFAULT '',
    created_by      UUID NOT NULL REFERENCES users(id),
    is_public       BOOLEAN DEFAULT false,
    member_limit    INTEGER DEFAULT 1000,
    invite_code     TEXT UNIQUE,           -- shareable invite code
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_groups_invite_code ON groups(invite_code) WHERE invite_code IS NOT NULL;
```

### 2.11 Table: `group_members`

```sql
CREATE TABLE group_members (
    group_id        UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role            TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at       TIMESTAMPTZ DEFAULT now(),
    invited_by      UUID REFERENCES users(id),
    muted_until     TIMESTAMPTZ,
    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX idx_group_members_user ON group_members(user_id);
```

### 2.12 Table: `pinned_messages`

```sql
CREATE TABLE pinned_messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id        UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    message_id      TEXT NOT NULL,          -- references ScyllaDB message.id
    pinned_by       UUID NOT NULL REFERENCES users(id),
    pinned_at       TIMESTAMPTZ DEFAULT now(),
    unpinned_at     TIMESTAMPTZ             -- NULL = still pinned
);

CREATE INDEX idx_pinned_messages_group ON pinned_messages(group_id)
    WHERE unpinned_at IS NULL;
```

### 2.13 Table: `channels`

```sql
CREATE TABLE channels (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    description     TEXT DEFAULT '',
    avatar_url      TEXT DEFAULT '',
    created_by      UUID NOT NULL REFERENCES users(id),
    is_public       BOOLEAN DEFAULT true,
    subscriber_count BIGINT DEFAULT 0,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_channels_public ON channels(is_public, created_at DESC);
```

### 2.14 Table: `channel_subscribers`

```sql
CREATE TABLE channel_subscribers (
    channel_id      UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subscribed_at   TIMESTAMPTZ DEFAULT now(),
    is_muted        BOOLEAN DEFAULT false,
    PRIMARY KEY (channel_id, user_id)
);

CREATE INDEX idx_channel_subs_user ON channel_subscribers(user_id);
```

### 2.15 Table: `feature_flags`

```sql
CREATE TABLE feature_flags (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT UNIQUE NOT NULL,
    description     TEXT,
    is_enabled      BOOLEAN DEFAULT true,
    rollout_pct     INTEGER DEFAULT 100 CHECK (rollout_pct BETWEEN 0 AND 100),
    platform_filter TEXT[] DEFAULT '{}',   -- ['ios', 'android', 'web', 'desktop']
    region_filter   TEXT[] DEFAULT '{}',   -- ['us-east-1', 'ap-south-1', ...]
    user_segment    TEXT,                  -- 'alpha' | 'beta' | 'internal' | NULL
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);
```

### 2.16 Table: `audit_log`

```sql
CREATE TABLE audit_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_id        UUID REFERENCES users(id),
    action          TEXT NOT NULL,          -- 'user.disabled', 'message.removed', 'flag.toggled', etc.
    target_type     TEXT,                   -- 'user' | 'message' | 'flag' | 'channel'
    target_id       TEXT,
    details         JSONB DEFAULT '{}',
    ip_address      INET,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_audit_log_admin ON audit_log(admin_id);
CREATE INDEX idx_audit_log_action ON audit_log(action);
CREATE INDEX idx_audit_log_created ON audit_log(created_at DESC);
```

### 2.17 Table: `webhooks`

```sql
CREATE TABLE webhooks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    url             TEXT NOT NULL,
    secret          TEXT NOT NULL,          -- HMAC signing secret
    events          TEXT[] NOT NULL,        -- ['message.sent', 'message.received', 'user.joined']
    is_active       BOOLEAN DEFAULT true,
    retry_count     INTEGER DEFAULT 3,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_webhooks_owner ON webhooks(owner_id);
```

### 2.18 Table: `api_keys`

```sql
CREATE TABLE api_keys (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    owner_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    key_prefix      TEXT NOT NULL,          -- first 8 chars of the key (for identification)
    key_hash        TEXT NOT NULL,          -- SHA-256 of the full key
    name            TEXT NOT NULL,
    permissions     TEXT[] DEFAULT '{}',    -- ['messages:read', 'messages:write', ...]
    rate_limit      INTEGER DEFAULT 100,    -- requests per minute
    is_active       BOOLEAN DEFAULT true,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now(),
    last_used_at    TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_owner ON api_keys(owner_id);
CREATE INDEX idx_api_keys_prefix ON api_keys(key_prefix);
```

### 2.19 Table: `scheduled_messages`

```sql
CREATE TABLE scheduled_messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    content_type    TEXT DEFAULT 'text',
    send_at         TIMESTAMPTZ NOT NULL,
    status          TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled')),
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_scheduled_pending ON scheduled_messages(send_at, status)
    WHERE status = 'pending';
```

### 2.20 Row-Level Security (RLS) Policies

```sql
-- Enable RLS on all tenant-isolated tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_subscribers ENABLE ROW LEVEL SECURITY;

-- Users: can only see own profile (except admins)
CREATE POLICY user_isolation ON users
    FOR SELECT
    USING (id = current_setting('app.current_user_id')::UUID
           OR current_setting('app.is_admin')::BOOLEAN = true);

CREATE POLICY user_update_self ON users
    FOR UPDATE
    USING (id = current_setting('app.current_user_id')::UUID);

-- Devices: users see own devices only
CREATE POLICY device_isolation ON user_devices
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);

-- Contacts: users see own contact list only
CREATE POLICY contact_isolation ON contacts
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);

-- Conversation participants: only participants can see membership
CREATE POLICY conv_participant_isolation ON conversation_participants
    FOR SELECT
    USING (conversation_id IN (
        SELECT conversation_id FROM conversation_participants
        WHERE user_id = current_setting('app.current_user_id')::UUID
    ));

-- Group members: only members can see member list
CREATE POLICY group_member_isolation ON group_members
    FOR SELECT
    USING (group_id IN (
        SELECT group_id FROM group_members
        WHERE user_id = current_setting('app.current_user_id')::UUID
    ));

-- Channels: subscribers see subscribed channels; public channels visible to all
CREATE POLICY channel_select ON channels
    FOR SELECT
    USING (is_public = true
           OR EXISTS (SELECT 1 FROM channel_subscribers
                      WHERE channel_id = channels.id
                      AND user_id = current_setting('app.current_user_id')::UUID));
```

---

## 3. ScyllaDB Cloud Schema

> Using Alternator API (DynamoDB-compatible) or CQL. All tables use ScyllaDB's Tablets technology for auto-rebalancing.

### 3.1 Keyspace

```cql
CREATE KEYSPACE IF NOT EXISTS closetalk
    WITH replication = {
        'class': 'NetworkTopologyStrategy',
        'us-east-1': 3
    };
```

### 3.2 Table: `messages`

```cql
CREATE TABLE closetalk.messages (
    chat_id         TEXT,                  -- conversation UUID as string
    created_at      TIMESTAMP,            -- clustering key for time-ordered queries
    message_id      UUID,                 -- unique message identifier
    sender_id       TEXT,                 -- user UUID as string
    sender_device_id TEXT,                -- device UUID as string
    content         TEXT,
    content_type    TEXT,                 -- 'text' | 'image' | 'video' | 'file' | 'voice' | 'poll'
    media_url       TEXT,                 -- S3/CDN URL for media messages
    media_id        TEXT,                 -- reference to media record
    reply_to_id     UUID,                -- parent message_id for threads
    status          TEXT,                 -- 'pending' | 'sent' | 'delivered' | 'read'
    moderation_status TEXT,              -- 'pending' | 'passed' | 'flagged' | 'quarantined'
    edit_history    TEXT,                -- JSON array of { content, edited_at }
    is_deleted      BOOLEAN DEFAULT false,
    disappeared_at  TIMESTAMP,           -- auto-delete at this time (NULL = permanent)
    ttl             INT DEFAULT 0,       -- ScyllaDB TTL in seconds (0 = no TTL)
    PRIMARY KEY (chat_id, created_at, message_id)
) WITH CLUSTERING ORDER BY (created_at DESC, message_id ASC)
   AND COMPACTION = { 'class': 'TimeWindowCompactionStrategy',
                      'compaction_window_size': 1,
                      'compaction_window_unit': 'DAYS' }
   AND DEFAULT_TIME_TO_LIVE = 0;
```

**Partition strategy**: `chat_id` is the partition key, `created_at` is the clustering key. This enables efficient cursor-based pagination: `SELECT WHERE chat_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT 50`. Each chat is a hot partition; ScyllaDB's Tablets technology rebalances across nodes automatically.

**Secondary indexes** (ScyllaDB materialized views):

```cql
-- For sync queries: find messages by recipient across all chats
CREATE MATERIALIZED VIEW closetalk.messages_by_recipient AS
    SELECT * FROM closetalk.messages
    WHERE recipient_id IS NOT NULL AND chat_id IS NOT NULL
        AND created_at IS NOT NULL AND message_id IS NOT NULL
    PRIMARY KEY (recipient_id, created_at, message_id, chat_id)
    WITH CLUSTERING ORDER BY (created_at DESC);
```

### 3.3 Table: `message_reads`

```cql
CREATE TABLE closetalk.message_reads (
    message_id      UUID,
    user_id         TEXT,
    read_at         TIMESTAMP,
    PRIMARY KEY (message_id, user_id)
);
```

### 3.4 Table: `message_reactions`

```cql
CREATE TABLE closetalk.message_reactions (
    message_id      UUID,
    user_id         TEXT,
    emoji           TEXT,
    created_at      TIMESTAMP,
    PRIMARY KEY (message_id, user_id, emoji)
);
```

### 3.5 Table: `polls`

```cql
CREATE TABLE closetalk.polls (
    poll_id         UUID PRIMARY KEY,
    chat_id         TEXT,
    creator_id      TEXT,
    question        TEXT,
    options         TEXT,                 -- JSON array of option strings
    multiple_choice BOOLEAN DEFAULT false,
    is_closed       BOOLEAN DEFAULT false,
    created_at      TIMESTAMP,
    expires_at      TIMESTAMP
);
```

### 3.6 Table: `poll_votes`

```cql
CREATE TABLE closetalk.poll_votes (
    poll_id         UUID,
    user_id         TEXT,
    option_index    INT,
    voted_at        TIMESTAMP,
    PRIMARY KEY (poll_id, user_id)
);
```

### 3.7 Table: `statuses`

```cql
CREATE TABLE closetalk.statuses (
    user_id         TEXT,
    created_at      TIMESTAMP,
    status_id       UUID,
    type            TEXT,                 -- 'image' | 'video' | 'text'
    content         TEXT,                 -- text content or S3 media URL
    privacy         TEXT,                 -- 'contacts' | 'close_friends' | 'public'
    expires_at      TIMESTAMP,
    PRIMARY KEY (user_id, created_at, status_id)
) WITH CLUSTERING ORDER BY (created_at DESC)
   AND DEFAULT_TIME_TO_LIVE = 86400;     -- 24h auto-expire
```

### 3.8 Table: `status_views`

```cql
CREATE TABLE closetalk.status_views (
    status_id       UUID,
    viewer_id       TEXT,
    viewed_at       TIMESTAMP,
    PRIMARY KEY (status_id, viewer_id)
);
```

### 3.9 Table: `channel_messages`

```cql
CREATE TABLE closetalk.channel_messages (
    channel_id      TEXT,
    created_at      TIMESTAMP,
    message_id      UUID,
    sender_id       TEXT,
    content         TEXT,
    content_type    TEXT DEFAULT 'text',
    is_pinned       BOOLEAN DEFAULT false,
    PRIMARY KEY (channel_id, created_at, message_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

### 3.10 Table: `bookmarks`

```cql
CREATE TABLE closetalk.bookmarks (
    user_id         TEXT,
    message_id      UUID,
    chat_id         TEXT,
    content_preview TEXT,
    created_at      TIMESTAMP,
    PRIMARY KEY (user_id, created_at, message_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

---

## 4. Valkey 8.1 Schema

> Key naming convention: `{namespace}:{entity}:{id}:{field}`

### 4.1 Session Store

```
Key:    session:{refresh_token_hash}
Type:   HASH
TTL:    604800 (7 days)
Fields: user_id, device_id, created_at, expires_at
```

```
Key:    user_sessions:{user_id}
Type:   SET
TTL:    None (managed separately)
Members: device_id strings
```

### 4.2 Device Sessions

```
Key:    device:{device_id}
Type:   HASH
TTL:    2592000 (30 days — auto-revoke if inactive)
Fields: user_id, device_name, device_type, platform, public_key,
        push_token, app_version, linked_at, last_active, is_active
```

### 4.3 Presence Tracking

```
Key:    presence:{user_id}
Type:   HASH
TTL:    60 (seconds — refreshed every 30s by client ping)
Fields: status (online | offline), last_seen, device_count
```

```
Key:    presence:online:{chat_id}
Type:   SET
TTL:    60 (seconds)
Members: user_ids who are online and in this chat
```

### 4.4 Rate Limiting

```
Key:    ratelimit:{endpoint}:{user_id}
Type:   STRING (counter)
TTL:    60 (seconds — sliding window)
Value:  Incremented per request
```

```
Key:    ratelimit:ip:{ip_address}
Type:   STRING (counter)
TTL:    60 (seconds)
Value:  Incremented per request
```

```
Key:    ratelimit:chat:{chat_id}:{user_id}
Type:   STRING (counter)
TTL:    60 (seconds)
Value:  Incremented per message sent
```

### 4.5 Thumbnail Cache

```
Key:    thumbnail:{media_id}:{size}
Type:   STRING (JSON)
TTL:    3600 (1 hour)
Value:  { url, width, height, format, expires_at }
```

Sizes: `sm` (100x100), `md` (400x400), `lg` (1200x1200)

### 4.6 Pub/Sub Channels

```
Channel: presence:{user_id}
Payload: { event: "online"|"offline"|"typing", chat_id, timestamp }
```

```
Channel: chat:{chat_id}
Payload: { event: "message.new"|"typing.start"|"typing.stop", ... }
```

### 4.7 Feature Flags Cache

```
Key:    feature_flag:{flag_name}
Type:   HASH
TTL:    300 (5 minutes — refreshed from PostgreSQL)
Fields: is_enabled, rollout_pct, platform_filter, region_filter,
        user_segment, updated_at
```

### 4.8 Search Cache

```
Key:    search:query:{sha256(query + filters)}
Type:   STRING (JSON)
TTL:    300 (5 minutes)
Value:  { results, total, page }
```

### 4.9 Recovery Rate Limit

```
Key:    recover:attempts:{user_id}
Type:   STRING (counter)
TTL:    3600 (1 hour)
Value:  Number of recovery attempts in the last hour (max 5)
```

---

## 5. Elasticsearch Index

### 5.1 Index: `messages`

```json
{
  "index": "messages",
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2,
    "analysis": {
      "analyzer": {
        "message_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "stop", "snowball"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "message_id":    { "type": "keyword" },
      "chat_id":       { "type": "keyword" },
      "sender_id":     { "type": "keyword" },
      "content":       { "type": "text", "analyzer": "message_analyzer" },
      "content_type":  { "type": "keyword" },
      "created_at":    { "type": "date" },
      "chat_name":     { "type": "text" },
      "sender_name":   { "type": "text" },
      "participants":  { "type": "keyword" },
      "is_deleted":    { "type": "boolean" },
      "moderation_status": { "type": "keyword" }
    }
  }
}
```

### 5.2 Index Lifecycle Policy

| Phase | Duration | Action |
|---|---|---|
| **hot** | 7 days | Fast SSD, full indexing, replica=2 |
| **warm** | 30 days | Standard storage, reduced replica=1 |
| **cold** | 90+ days | Frozen, searchable but slower, replica=0 |

### 5.3 Indexing Pipeline

```
Message written to ScyllaDB
       │
       ▼
SQS FIFO → Lambda → Index to Elasticsearch
       │
       ▼
Client searches → Search Service → Elasticsearch query
       │
       ▼
Results returned with relevance scores + highlights
```

---

## 6. Migration Strategy

### 6.1 PostgreSQL Migrations (Neon)

Use `golang-migrate` or `node-pg-migrate`:

```
closetalk_backend/infrastructure/migrations/
├── 000001_create_users.up.sql
├── 000001_create_users.down.sql
├── 000002_create_user_devices.up.sql
├── 000002_create_user_devices.down.sql
...
```

Neon branching creates isolated database copies per PR for zero-risk migrations.

### 6.2 ScyllaDB Schema Changes

- **Add column**: `ALTER TABLE closetalk.messages ADD new_column text;` — online, no downtime
- **Change compaction**: `ALTER TABLE closetalk.messages WITH compaction = {...};` — online
- **Add materialized view**: Create asynchronously, backfill in background
- **Drop table**: `DROP TABLE closetalk.old_table;` — irreversible, backup first

### 6.3 Valkey Key Migration

- Key-based: hot keys are re-generated on miss
- Cluster resize: Valkey cluster mode handles resharding automatically
- No persistent schema migrations needed (cached data regenerates)

### 6.4 Elasticsearch Reindex

```json
POST /_reindex
{
  "source": { "index": "messages-v1" },
  "dest":   { "index": "messages-v2" }
}
```

Zero-downtime: index to both versions during migration, then swap alias.

---

## 7. Data Flow Summary

```
┌──────────────┐    ┌──────────────────┐    ┌────────────────────┐
│  Auth/Write  │───▶│  Neon PostgreSQL  │    │  ScyllaDB Cloud    │
│  (Users,     │    │  (ACID, RLS)      │    │  (Messages, Polls, │
│   Groups,    │    └──────────────────┘    │   Statuses)         │
│   Settings)  │                            └─────────┬──────────┘
└──────────────┘                                      │
                                                      ▼
┌──────────────┐    ┌──────────────────┐    ┌────────────────────┐
│  Reads       │───▶│  Valkey 8.1       │    │  Elasticsearch     │
│  (Session,   │    │  (Cache, Pub/Sub) │    │  (Search Index)    │
│   Presence)  │    └──────────────────┘    └────────────────────┘
└──────────────┘
```

- **Writes**: Go to the authoritative store first (PostgreSQL for metadata, ScyllaDB for messages)
- **Reads**: Go to Valkey (hot cache), fallback to source of truth on miss
- **Search**: Indexed asynchronously via SQS → Lambda → Elasticsearch
- **Presence**: Pushed to Valkey Pub/Sub, subscribers receive real-time updates
