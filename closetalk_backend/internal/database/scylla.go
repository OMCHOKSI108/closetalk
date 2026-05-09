package database

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/gocql/gocql"
)

var Scylla *gocql.Session

func ConnectScylla() error {
	hosts := os.Getenv("SCYLLA_HOSTS")
	if hosts == "" {
		hosts = "localhost:9042"
	}

	cluster := gocql.NewCluster(hosts)
	cluster.Keyspace = "closetalk"
	cluster.Consistency = gocql.LocalQuorum
	cluster.Timeout = 10 * time.Second
	cluster.ConnectTimeout = 10 * time.Second
	cluster.NumConns = 5
	cluster.SocketKeepalive = 30 * time.Second
	cluster.PoolConfig.HostSelectionPolicy = gocql.TokenAwareHostPolicy(gocql.RoundRobinHostPolicy())

	session, err := cluster.CreateSession()
	if err != nil {
		return fmt.Errorf("connect scylla: %w", err)
	}

	Scylla = session
	log.Println("[scylla] connected")
	return nil
}

func InitScyllaSchema() error {
	if Scylla == nil {
		return fmt.Errorf("scylla not connected")
	}

	stmts := []string{
		`CREATE KEYSPACE IF NOT EXISTS closetalk
		 WITH replication = {
			 'class': 'SimpleStrategy',
			 'replication_factor': 1
		 }`,

		`CREATE TABLE IF NOT EXISTS closetalk.messages (
			chat_id         TEXT,
			created_at      TIMESTAMP,
			message_id      UUID,
			sender_id       TEXT,
			sender_device_id TEXT,
			content         TEXT,
			content_type    TEXT,
			media_url       TEXT,
			media_id        TEXT,
			reply_to_id     UUID,
			status          TEXT,
			moderation_status TEXT,
			edit_history    TEXT,
			is_deleted      BOOLEAN DEFAULT false,
			disappeared_at  TIMESTAMP,
			ttl             INT DEFAULT 0,
			PRIMARY KEY (chat_id, created_at, message_id)
		) WITH CLUSTERING ORDER BY (created_at DESC, message_id ASC)
		 AND COMPACTION = { 'class': 'TimeWindowCompactionStrategy',
							'compaction_window_size': 1,
							'compaction_window_unit': 'DAYS' }`,

		`CREATE TABLE IF NOT EXISTS closetalk.message_reads (
			message_id      UUID,
			user_id         TEXT,
			read_at         TIMESTAMP,
			PRIMARY KEY (message_id, user_id)
		)`,

		`CREATE TABLE IF NOT EXISTS closetalk.message_reactions (
			message_id      UUID,
			user_id         TEXT,
			emoji           TEXT,
			created_at      TIMESTAMP,
			PRIMARY KEY (message_id, user_id, emoji)
		)`,

		`CREATE TABLE IF NOT EXISTS closetalk.bookmarks (
			user_id         TEXT,
			message_id      UUID,
			chat_id         TEXT,
			content_preview TEXT,
			created_at      TIMESTAMP,
			PRIMARY KEY (user_id, created_at, message_id)
		) WITH CLUSTERING ORDER BY (created_at DESC)`,
	}

	for _, stmt := range stmts {
		if err := Scylla.Query(stmt).Exec(); err != nil {
			log.Printf("[scylla] schema warning: %v", err)
		}
	}

	log.Println("[scylla] schema initialized")
	return nil
}

func CloseScylla() {
	if Scylla != nil {
		Scylla.Close()
		log.Println("[scylla] connection closed")
	}
}
