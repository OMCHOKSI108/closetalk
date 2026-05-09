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
	}

	for _, m := range migrations {
		if _, err := Pool.Exec(ctx, m); err != nil {
			return fmt.Errorf("migration failed: %w\nSQL: %s", err, m)
		}
	}

	log.Println("[neon] migrations applied")
	return nil
}
