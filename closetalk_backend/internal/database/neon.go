package database

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var Pool *pgxpool.Pool

func IndexMessage(ctx context.Context, msgID, chatID, senderID, content, contentType string, createdAt time.Time) error {
	if Pool == nil {
		return nil
	}
	_, err := Pool.Exec(ctx,
		`INSERT INTO message_search (message_id, chat_id, sender_id, content, content_type, created_at)
		 VALUES ($1::uuid, $2, $3::uuid, $4, $5, $6)
		 ON CONFLICT (message_id) DO UPDATE SET content = $4, content_type = $5`,
		msgID, chatID, senderID, content, contentType, createdAt,
	)
	return err
}

type NeonSearchResult struct {
	MessageID   string    `json:"message_id"`
	ChatID      string    `json:"chat_id"`
	SenderID    string    `json:"sender_id"`
	Content     string    `json:"content"`
	ContentType string    `json:"content_type"`
	CreatedAt   time.Time `json:"created_at"`
}

func SearchMessagesNeon(ctx context.Context, chatID string, query string, cursor time.Time, limit int) ([]NeonSearchResult, bool, error) {
	if Pool == nil {
		return nil, false, nil
	}
	likePattern := "%" + query + "%"
	rows, err := Pool.Query(ctx,
		`SELECT message_id::text, chat_id, sender_id::text, content, content_type, created_at
		 FROM message_search
		 WHERE chat_id = $1 AND content ILIKE $2 AND created_at < $3
		 ORDER BY created_at DESC
		 LIMIT $4`,
		chatID, likePattern, cursor, limit,
	)
	if err != nil {
		return nil, false, fmt.Errorf("search neon: %w", err)
	}
	defer rows.Close()

	var results []NeonSearchResult
	for rows.Next() {
		var r NeonSearchResult
		if err := rows.Scan(&r.MessageID, &r.ChatID, &r.SenderID, &r.Content, &r.ContentType, &r.CreatedAt); err != nil {
			continue
		}
		results = append(results, r)
	}
	hasMore := len(results) == limit
	return results, hasMore, nil
}

func SearchMessagesNeonGlobal(ctx context.Context, userID string, query string, cursor time.Time, limit int) ([]NeonSearchResult, bool, error) {
	if Pool == nil {
		return nil, false, nil
	}
	likePattern := "%" + query + "%"
	rows, err := Pool.Query(ctx,
		`SELECT ms.message_id::text, ms.chat_id, ms.sender_id::text, ms.content, ms.content_type, ms.created_at
		 FROM message_search ms
		 JOIN conversation_participants cp ON cp.conversation_id = ms.chat_id
		 WHERE cp.user_id = $1::uuid AND ms.content ILIKE $2 AND ms.created_at < $3
		 ORDER BY ms.created_at DESC
		 LIMIT $4`,
		userID, likePattern, cursor, limit,
	)
	if err != nil {
		return nil, false, fmt.Errorf("search neon global: %w", err)
	}
	defer rows.Close()

	var results []NeonSearchResult
	for rows.Next() {
		var r NeonSearchResult
		if err := rows.Scan(&r.MessageID, &r.ChatID, &r.SenderID, &r.Content, &r.ContentType, &r.CreatedAt); err != nil {
			continue
		}
		results = append(results, r)
	}
	hasMore := len(results) == limit
	return results, hasMore, nil
}

func ConnectNeon() error {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://closetalk:closetalk@localhost:5432/closetalk?sslmode=disable"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	config, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("parse database config: %w", err)
	}

	config.MaxConns = 25
	config.MinConns = 2
	config.MaxConnLifetime = 30 * time.Minute
	config.HealthCheckPeriod = 1 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return fmt.Errorf("create connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("ping database: %w", err)
	}

	Pool = pool
	log.Println("[neon] connected to PostgreSQL")
	return nil
}

func CloseNeon() {
	if Pool != nil {
		Pool.Close()
		log.Println("[neon] connection closed")
	}
}

func RunMigrations() error {
	ctx := context.Background()

	migrations := []string{
		`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`,
		`CREATE EXTENSION IF NOT EXISTS "pgcrypto"`,
		`CREATE EXTENSION IF NOT EXISTS "pg_trgm"`,

		`CREATE TABLE IF NOT EXISTS users (
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
		)`,

		`CREATE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL`,
		`CREATE INDEX IF NOT EXISTS idx_users_phone_hash ON users(phone_hash) WHERE phone_hash IS NOT NULL`,

		`ALTER TABLE users ADD COLUMN IF NOT EXISTS username TEXT UNIQUE`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS username_changes INT DEFAULT 0`,
		`ALTER TABLE users ADD COLUMN IF NOT EXISTS username_changed_at TIMESTAMPTZ`,

		`CREATE INDEX IF NOT EXISTS idx_users_username ON users(username) WHERE username IS NOT NULL`,

		`INSERT INTO users (email, display_name, username, bio, oauth_provider, oauth_id)
		 VALUES
		 ('hitenkatariya@mock.closetalk.local', 'Hiten Katariya', 'hitenkatariya', 'Mock contact for development', 'mock', 'mock:hitenkatariya'),
		 ('omchoksi@mock.closetalk.local', 'Om Choksi', 'omchoksi', 'Mock contact for development', 'mock', 'mock:omchoksi'),
		 ('choksi108@mock.closetalk.local', 'Choksi108', 'Choksi108', 'Mock contact for development', 'mock', 'mock:Choksi108')
		 ON CONFLICT (username) DO UPDATE SET
		 	display_name = EXCLUDED.display_name,
		 	bio = EXCLUDED.bio,
		 	updated_at = now()`,

		`CREATE TABLE IF NOT EXISTS recovery_codes (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			code_hash       TEXT NOT NULL,
			is_used         BOOLEAN DEFAULT false,
			created_at      TIMESTAMPTZ DEFAULT now(),
			used_at         TIMESTAMPTZ
		)`,

		`CREATE INDEX IF NOT EXISTS idx_recovery_codes_user ON recovery_codes(user_id)`,

		`CREATE TABLE IF NOT EXISTS user_devices (
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
		)`,

		`CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id)`,

		`CREATE TABLE IF NOT EXISTS notification_tokens (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			token           TEXT NOT NULL UNIQUE,
			platform        TEXT NOT NULL CHECK (platform IN ('apns', 'fcm')),
			created_at      TIMESTAMPTZ DEFAULT now(),
			updated_at      TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE INDEX IF NOT EXISTS idx_notification_tokens_user ON notification_tokens(user_id)`,

		`CREATE TABLE IF NOT EXISTS conversations (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			type            TEXT NOT NULL CHECK (type IN ('direct', 'group')),
			created_at      TIMESTAMPTZ DEFAULT now(),
			last_message_at TIMESTAMPTZ,
			message_count   BIGINT DEFAULT 0,
			metadata        JSONB DEFAULT '{}'
		)`,

		`CREATE INDEX IF NOT EXISTS idx_conversations_last_message ON conversations(last_message_at DESC)`,

		`CREATE TABLE IF NOT EXISTS conversation_participants (
			conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			joined_at       TIMESTAMPTZ DEFAULT now(),
			last_read_at    TIMESTAMPTZ,
			is_muted        BOOLEAN DEFAULT false,
			PRIMARY KEY (conversation_id, user_id)
		)`,

		`CREATE INDEX IF NOT EXISTS idx_conv_participants_user ON conversation_participants(user_id)`,

		`CREATE TABLE IF NOT EXISTS groups (
			id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			conversation_id   UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
			name              TEXT NOT NULL,
			description       TEXT DEFAULT '',
			avatar_url        TEXT DEFAULT '',
			created_by        UUID NOT NULL REFERENCES users(id),
			is_public         BOOLEAN DEFAULT false,
			member_limit      INTEGER DEFAULT 1000,
			invite_code       TEXT UNIQUE,
			message_retention TEXT DEFAULT 'off' CHECK (message_retention IN ('off','30d','90d','1yr')),
			disappearing_msg  TEXT DEFAULT 'off' CHECK (disappearing_msg IN ('off','5s','30s','5m','1h','24h')),
			created_at        TIMESTAMPTZ DEFAULT now(),
			updated_at        TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE INDEX IF NOT EXISTS idx_groups_invite_code ON groups(invite_code) WHERE invite_code IS NOT NULL`,

		`CREATE TABLE IF NOT EXISTS group_members (
			group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role        TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
			joined_at   TIMESTAMPTZ DEFAULT now(),
			invited_by  UUID REFERENCES users(id),
			muted_until TIMESTAMPTZ,
			left_at     TIMESTAMPTZ,
			PRIMARY KEY (group_id, user_id)
		)`,

		`CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id)`,

		`CREATE TABLE IF NOT EXISTS group_blocks (
			group_id   UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			blocked_at TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (group_id, user_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_group_blocks_user ON group_blocks(user_id)`,

		`CREATE TABLE IF NOT EXISTS pinned_messages (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			message_id  TEXT NOT NULL,
			pinned_by   UUID NOT NULL REFERENCES users(id),
			pinned_at   TIMESTAMPTZ DEFAULT now(),
			unpinned_at TIMESTAMPTZ
		)`,

		`CREATE INDEX IF NOT EXISTS idx_pinned_messages_group ON pinned_messages(group_id) WHERE unpinned_at IS NULL`,

		`CREATE TABLE IF NOT EXISTS group_settings (
			group_id            UUID PRIMARY KEY REFERENCES groups(id) ON DELETE CASCADE,
			message_retention   TEXT DEFAULT 'off' CHECK (message_retention IN ('off','30d','90d','1yr')),
			disappearing_msg    TEXT DEFAULT 'off' CHECK (disappearing_msg IN ('off','5s','30s','5m','1h','24h')),
			updated_at          TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE TABLE IF NOT EXISTS user_settings (
			user_id                     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			last_seen_visibility        TEXT NOT NULL DEFAULT 'everyone'
			                            CHECK (last_seen_visibility IN ('nobody','everyone','contacts','contacts_except')),
			profile_photo_visibility    TEXT NOT NULL DEFAULT 'everyone'
			                            CHECK (profile_photo_visibility IN ('nobody','everyone','contacts')),
			read_receipts_global        BOOLEAN DEFAULT true,
			read_receipts_overrides     JSONB DEFAULT '{}',
			group_add_permission        TEXT NOT NULL DEFAULT 'everyone'
			                            CHECK (group_add_permission IN ('everyone','contacts','contacts_except')),
			status_privacy              TEXT NOT NULL DEFAULT 'contacts'
			                            CHECK (status_privacy IN ('contacts','close_friends','public')),
			close_friends               UUID[] DEFAULT '{}',
			disappearing_msg_default    TEXT DEFAULT 'off',
			language                    TEXT DEFAULT 'en',
			updated_at                  TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE TABLE IF NOT EXISTS contacts (
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			contact_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			status          TEXT NOT NULL DEFAULT 'pending'
			                CHECK (status IN ('pending','sent','accepted','blocked','rejected')),
			conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
			created_at      TIMESTAMPTZ DEFAULT now(),
			updated_at      TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (user_id, contact_id)
		)`,
		`ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_status_check`,
		`ALTER TABLE contacts ADD CONSTRAINT contacts_status_check
		 CHECK (status IN ('pending','sent','accepted','blocked','rejected'))`,

		`CREATE INDEX IF NOT EXISTS idx_contacts_user ON contacts(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_contacts_contact ON contacts(contact_id)`,

		`CREATE TABLE IF NOT EXISTS stories (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			content     TEXT NOT NULL DEFAULT '',
			media_url   TEXT DEFAULT '',
			media_type  TEXT DEFAULT 'text' CHECK (media_type IN ('text','image','video')),
			created_at  TIMESTAMPTZ DEFAULT now(),
			expires_at  TIMESTAMPTZ DEFAULT now() + interval '24 hours'
		)`,
		`CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_stories_expires ON stories(expires_at)`,

		`CREATE TABLE IF NOT EXISTS reports (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			reporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			reason          TEXT NOT NULL,
			created_at      TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE INDEX IF NOT EXISTS idx_reports_reported ON reports(reported_user_id)`,

		`CREATE TABLE IF NOT EXISTS e2ee_keys (
			user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
			public_key  TEXT NOT NULL,
			created_at  TIMESTAMPTZ DEFAULT now(),
			updated_at  TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE TABLE IF NOT EXISTS contact_hashes (
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			phone_hash  TEXT NOT NULL,
			created_at  TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (user_id, phone_hash)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_contact_hashes_hash ON contact_hashes(phone_hash)`,

		`CREATE TABLE IF NOT EXISTS story_views (
			story_id    UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
			viewer_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			viewed_at   TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (story_id, viewer_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_story_views_story ON story_views(story_id)`,

		`CREATE TABLE IF NOT EXISTS story_mutes (
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			muted_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			muted_at        TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (user_id, muted_user_id)
		)`,

		`CREATE TABLE IF NOT EXISTS broadcasts (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			name        TEXT NOT NULL,
			created_at  TIMESTAMPTZ DEFAULT now(),
			updated_at  TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_broadcasts_user ON broadcasts(user_id)`,

		`CREATE TABLE IF NOT EXISTS broadcast_members (
			broadcast_id UUID NOT NULL REFERENCES broadcasts(id) ON DELETE CASCADE,
			user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			added_at     TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (broadcast_id, user_id)
		)`,

		`CREATE TABLE IF NOT EXISTS channels (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			name            TEXT NOT NULL,
			description     TEXT DEFAULT '',
			avatar_url      TEXT DEFAULT '',
			created_by      UUID NOT NULL REFERENCES users(id),
			is_public       BOOLEAN DEFAULT true,
			subscriber_count BIGINT DEFAULT 0,
			created_at      TIMESTAMPTZ DEFAULT now(),
			updated_at      TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_channels_public ON channels(is_public, created_at DESC)`,

		`CREATE TABLE IF NOT EXISTS channel_subscribers (
			channel_id    UUID NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
			user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			role          TEXT NOT NULL DEFAULT 'subscriber' CHECK (role IN ('admin', 'subscriber')),
			subscribed_at TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (channel_id, user_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_channel_subs_user ON channel_subscribers(user_id)`,

		`CREATE TABLE IF NOT EXISTS scheduled_messages (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			chat_id         TEXT NOT NULL,
			sender_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			content         TEXT NOT NULL,
			content_type    TEXT DEFAULT 'text',
			media_url       TEXT DEFAULT '',
			reply_to_id     UUID,
			send_at         TIMESTAMPTZ NOT NULL,
			status          TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled')),
			created_at      TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_scheduled_send ON scheduled_messages(status, send_at) WHERE status = 'pending'`,

		`CREATE TABLE IF NOT EXISTS polls (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			chat_id         TEXT NOT NULL,
			creator_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			question        TEXT NOT NULL,
			options         JSONB NOT NULL DEFAULT '[]',
			multiple_choice BOOLEAN DEFAULT false,
			is_closed       BOOLEAN DEFAULT false,
			created_at      TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_polls_chat ON polls(chat_id)`,

		`CREATE TABLE IF NOT EXISTS poll_votes (
			poll_id       UUID NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
			user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			option_index  INT NOT NULL,
			voted_at      TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (poll_id, user_id)
		)`,

		`CREATE TABLE IF NOT EXISTS feature_flags (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			name            TEXT NOT NULL UNIQUE,
			description     TEXT DEFAULT '',
			enabled         BOOLEAN DEFAULT false,
			rollout_percent INT DEFAULT 100 CHECK (rollout_percent >= 0 AND rollout_percent <= 100),
			created_at      TIMESTAMPTZ DEFAULT now(),
			updated_at      TIMESTAMPTZ DEFAULT now()
		)`,

		`CREATE TABLE IF NOT EXISTS message_mentions (
			message_id  TEXT NOT NULL,
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			mentioned_at TIMESTAMPTZ DEFAULT now(),
			PRIMARY KEY (message_id, user_id)
		)`,
		`CREATE INDEX IF NOT EXISTS idx_mentions_user ON message_mentions(user_id)`,

		`CREATE TABLE IF NOT EXISTS webhooks (
			id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			url             TEXT NOT NULL,
			events          TEXT[] NOT NULL DEFAULT '{}',
			is_active       BOOLEAN DEFAULT true,
			secret          TEXT DEFAULT '',
			last_success_at TIMESTAMPTZ,
			last_failure_at TIMESTAMPTZ,
			failure_count   INTEGER DEFAULT 0,
			created_at      TIMESTAMPTZ DEFAULT now(),
			updated_at      TIMESTAMPTZ DEFAULT now()
		)`,
		`ALTER TABLE webhooks ADD COLUMN IF NOT EXISTS last_success_at TIMESTAMPTZ`,
		`ALTER TABLE webhooks ADD COLUMN IF NOT EXISTS last_failure_at TIMESTAMPTZ`,
		`ALTER TABLE webhooks ADD COLUMN IF NOT EXISTS failure_count INTEGER DEFAULT 0`,
		`CREATE INDEX IF NOT EXISTS idx_webhooks_user ON webhooks(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_webhooks_active ON webhooks(is_active) WHERE is_active = true`,

		`CREATE TABLE IF NOT EXISTS audit_log (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			admin_id    UUID NOT NULL REFERENCES users(id),
			action      TEXT NOT NULL,
			target_type TEXT NOT NULL,
			target_id   TEXT DEFAULT '',
			details     JSONB DEFAULT '{}',
			created_at  TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_log_admin ON audit_log(admin_id)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action)`,
		`CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log(created_at DESC)`,

		`CREATE TABLE IF NOT EXISTS message_search (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			message_id  UUID NOT NULL UNIQUE,
			chat_id     TEXT NOT NULL,
			sender_id   UUID NOT NULL,
			content     TEXT NOT NULL,
			content_type TEXT NOT NULL DEFAULT 'text',
			created_at  TIMESTAMPTZ NOT NULL
		)`,
		`CREATE INDEX IF NOT EXISTS idx_message_search_chat ON message_search(chat_id)`,
		`CREATE INDEX IF NOT EXISTS idx_message_search_content_gin ON message_search USING GIN(content gin_trgm_ops)`,
		`CREATE INDEX IF NOT EXISTS idx_message_search_created ON message_search(created_at DESC)`,

		`CREATE TABLE IF NOT EXISTS media (
			id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
			user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
			object_key  TEXT NOT NULL,
			file_name   TEXT NOT NULL,
			content_type TEXT NOT NULL,
			file_size   BIGINT DEFAULT 0,
			media_url   TEXT NOT NULL,
			created_at  TIMESTAMPTZ DEFAULT now()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_media_user ON media(user_id)`,
	}

	for _, m := range migrations {
		if _, err := Pool.Exec(ctx, m); err != nil {
			return fmt.Errorf("migration failed: %w\nSQL: %s", err, m)
		}
	}

	log.Println("[neon] migrations applied")
	return nil
}
