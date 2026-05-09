-- 001: Create users table
-- Run: psql -U closetalk -d closetalk -f 000001_create_users.up.sql

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           TEXT UNIQUE,
    phone           TEXT UNIQUE,
    phone_hash      TEXT UNIQUE,
    display_name    TEXT NOT NULL,
    bio             TEXT DEFAULT '',
    avatar_url      TEXT DEFAULT '',
    password_hash   TEXT,
    oauth_provider  TEXT,
    oauth_id        TEXT,
    is_active       BOOLEAN DEFAULT true,
    is_admin        BOOLEAN DEFAULT false,
    e2ee_enabled    BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    last_seen       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE INDEX idx_users_phone_hash ON users(phone_hash) WHERE phone_hash IS NOT NULL;
