-- 006: Replace UNIQUE constraints with partial unique indexes
-- to allow re-registration with same email/username after account deletion.
-- Run: psql -U closetalk -d closetalk -f 000006_fix_unique_constraints_for_soft_delete.up.sql

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_username_key;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_key;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_hash_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_active ON users(email) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_active ON users(username) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_active ON users(phone) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_hash_active ON users(phone_hash) WHERE deleted_at IS NULL;
