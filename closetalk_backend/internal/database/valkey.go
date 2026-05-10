package database

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

var Valkey *redis.Client

func ConnectValkey() error {
	addr := os.Getenv("VALKEY_ADDR")
	if addr == "" {
		addr = "localhost:6379"
	}

	password := os.Getenv("VALKEY_PASSWORD")

	client := redis.NewClient(&redis.Options{
		Addr:         addr,
		Password:     password,
		DB:           0,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
		PoolSize:     20,
		MinIdleConns: 5,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("connect valkey: %w", err)
	}

	Valkey = client
	log.Println("[valkey] connected")
	return nil
}

func CloseValkey() {
	if Valkey != nil {
		Valkey.Close()
		log.Println("[valkey] connection closed")
	}
}

// Session management helpers

func StoreSession(ctx context.Context, refreshToken string, userID string, deviceID string, ttl time.Duration) error {
	return Valkey.Set(ctx, "session:"+refreshToken, userID+":"+deviceID, ttl).Err()
}

func GetSession(ctx context.Context, refreshToken string) (string, error) {
	return Valkey.Get(ctx, "session:"+refreshToken).Result()
}

func DeleteSession(ctx context.Context, refreshToken string) error {
	return Valkey.Del(ctx, "session:"+refreshToken).Err()
}

func StoreUserSession(ctx context.Context, userID string, deviceID string, ttl time.Duration) error {
	if err := Valkey.SAdd(ctx, "user_sessions:"+userID, deviceID).Err(); err != nil {
		return err
	}
	return Valkey.Expire(ctx, "user_sessions:"+userID, ttl).Err()
}

func RemoveUserSession(ctx context.Context, userID string, deviceID string) error {
	return Valkey.SRem(ctx, "user_sessions:"+userID, deviceID).Err()
}

// Rate limiting helpers

func CheckRateLimit(ctx context.Context, key string, limit int, window time.Duration) (bool, error) {
	val, err := Valkey.Incr(ctx, key).Result()
	if err != nil {
		return false, err
	}
	if val == 1 {
		Valkey.Expire(ctx, key, window)
	}
	return val <= int64(limit), nil
}

// Recovery rate limit

func CheckRecoveryRateLimit(ctx context.Context, ip string) (int64, error) {
	key := "recover:attempts:ip:" + ip
	val, err := Valkey.Incr(ctx, key).Result()
	if err != nil {
		return 0, err
	}
	if val == 1 {
		Valkey.Expire(ctx, key, time.Hour)
	}
	return val, nil
}

func ResetRecoveryRateLimit(ctx context.Context, ip string) error {
	return Valkey.Del(ctx, "recover:attempts:ip:"+ip).Err()
}
