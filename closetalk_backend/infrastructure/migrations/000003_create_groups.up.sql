-- 003: Create groups, group_members, pinned_messages, group_settings tables

CREATE TABLE IF NOT EXISTS conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type            TEXT NOT NULL CHECK (type IN ('direct', 'group')),
    created_at      TIMESTAMPTZ DEFAULT now(),
    last_message_at TIMESTAMPTZ,
    message_count   BIGINT DEFAULT 0,
    metadata        JSONB DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_conversations_last_message ON conversations(last_message_at DESC);

CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at       TIMESTAMPTZ DEFAULT now(),
    last_read_at    TIMESTAMPTZ,
    is_muted        BOOLEAN DEFAULT false,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_conv_participants_user ON conversation_participants(user_id);

CREATE TABLE IF NOT EXISTS groups (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id   UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    name              TEXT NOT NULL,
    description       TEXT DEFAULT '',
    avatar_url        TEXT DEFAULT '',
    created_by        UUID NOT NULL REFERENCES users(id),
    is_public         BOOLEAN DEFAULT false,
    member_limit      INTEGER DEFAULT 1000,
    invite_code       TEXT UNIQUE,
    message_retention TEXT DEFAULT 'off' CHECK (message_retention IN ('off', '30d', '90d', '1yr')),
    disappearing_msg  TEXT DEFAULT 'off' CHECK (disappearing_msg IN ('off', '5s', '30s', '5m', '1h', '24h')),
    created_at        TIMESTAMPTZ DEFAULT now(),
    updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code) WHERE invite_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS group_members (
    group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    joined_at   TIMESTAMPTZ DEFAULT now(),
    invited_by  UUID REFERENCES users(id),
    muted_until TIMESTAMPTZ,
    left_at     TIMESTAMPTZ,
    PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);

CREATE TABLE IF NOT EXISTS pinned_messages (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    message_id  TEXT NOT NULL,
    pinned_by   UUID NOT NULL REFERENCES users(id),
    pinned_at   TIMESTAMPTZ DEFAULT now(),
    unpinned_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pinned_messages_group ON pinned_messages(group_id) WHERE unpinned_at IS NULL;

CREATE TABLE IF NOT EXISTS group_settings (
    group_id            UUID PRIMARY KEY REFERENCES groups(id) ON DELETE CASCADE,
    message_retention   TEXT DEFAULT 'off' CHECK (message_retention IN ('off', '30d', '90d', '1yr')),
    disappearing_msg    TEXT DEFAULT 'off' CHECK (disappearing_msg IN ('off', '5s', '30s', '5m', '1h', '24h')),
    updated_at          TIMESTAMPTZ DEFAULT now()
);
