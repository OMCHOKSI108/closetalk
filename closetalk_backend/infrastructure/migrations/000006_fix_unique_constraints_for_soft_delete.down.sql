-- 006: Revert - restore UNIQUE constraints, drop partial indexes

DROP INDEX IF EXISTS idx_users_email_active;
DROP INDEX IF EXISTS idx_users_username_active;
DROP INDEX IF EXISTS idx_users_phone_active;
DROP INDEX IF EXISTS idx_users_phone_hash_active;

ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT users_username_key UNIQUE (username);
ALTER TABLE users ADD CONSTRAINT users_phone_key UNIQUE (phone);
ALTER TABLE users ADD CONSTRAINT users_phone_hash_key UNIQUE (phone_hash);
