-- 002: Create user_devices, recovery_codes, user_settings tables

CREATE TABLE recovery_codes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash       TEXT NOT NULL,
    is_used         BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now(),
    used_at         TIMESTAMPTZ
);

CREATE INDEX idx_recovery_codes_user ON recovery_codes(user_id);

CREATE TABLE user_devices (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name     TEXT NOT NULL,
    device_type     TEXT NOT NULL CHECK (device_type IN ('phone', 'tablet', 'desktop', 'web')),
    platform        TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    public_key      TEXT,
    push_token      TEXT,
    app_version     TEXT,
    is_active       BOOLEAN DEFAULT true,
    linked_at       TIMESTAMPTZ DEFAULT now(),
    last_active     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);

CREATE TABLE user_settings (
    user_id                     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    last_seen_visibility        TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (last_seen_visibility IN ('nobody', 'everyone', 'contacts', 'contacts_except')),
    profile_photo_visibility    TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (profile_photo_visibility IN ('nobody', 'everyone', 'contacts')),
    read_receipts_global        BOOLEAN DEFAULT true,
    read_receipts_overrides     JSONB DEFAULT '{}',
    group_add_permission        TEXT NOT NULL DEFAULT 'everyone'
                                CHECK (group_add_permission IN ('everyone', 'contacts', 'contacts_except')),
    status_privacy              TEXT DEFAULT 'contacts',
    close_friends               UUID[] DEFAULT '{}',
    disappearing_msg_default    TEXT DEFAULT 'off',
    language                    TEXT DEFAULT 'en',
    updated_at                  TIMESTAMPTZ DEFAULT now()
);
