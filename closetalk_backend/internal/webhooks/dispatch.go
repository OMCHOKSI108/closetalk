package webhooks

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/database"
)

const (
	EventMessageNew     = "message.new"
	EventMessageUpdated = "message.updated"
	EventMessageDeleted = "message.deleted"
)

type WebhookPayload struct {
	Event     string `json:"event"`
	Timestamp string `json:"timestamp"`
	Data      any    `json:"data"`
}

type ActiveWebhook struct {
	ID     string
	URL    string
	Secret string
}

func LoadActiveWebhooks(ctx context.Context, userID string) ([]ActiveWebhook, error) {
	if database.Pool == nil {
		return nil, nil
	}
	rows, err := database.Pool.Query(ctx,
		`SELECT id, url, secret FROM webhooks WHERE user_id = $1 AND is_active = true`,
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("load webhooks: %w", err)
	}
	defer rows.Close()

	var hooks []ActiveWebhook
	for rows.Next() {
		var h ActiveWebhook
		if err := rows.Scan(&h.ID, &h.URL, &h.Secret); err != nil {
			continue
		}
		hooks = append(hooks, h)
	}
	if hooks == nil {
		hooks = []ActiveWebhook{}
	}
	return hooks, nil
}

func LoadEventWebhooks(ctx context.Context, event string) ([]ActiveWebhook, error) {
	if database.Pool == nil {
		return nil, nil
	}
	rows, err := database.Pool.Query(ctx,
		`SELECT id, url, secret FROM webhooks WHERE is_active = true AND $1 = ANY(events)`,
		event,
	)
	if err != nil {
		return nil, fmt.Errorf("load event webhooks: %w", err)
	}
	defer rows.Close()

	var hooks []ActiveWebhook
	for rows.Next() {
		var h ActiveWebhook
		if err := rows.Scan(&h.ID, &h.URL, &h.Secret); err != nil {
			continue
		}
		hooks = append(hooks, h)
	}
	if hooks == nil {
		hooks = []ActiveWebhook{}
	}
	return hooks, nil
}

func UpdateWebhookStatus(ctx context.Context, webhookID string, success bool, errMsg string) {
	if database.Pool == nil {
		return
	}
	if success {
		database.Pool.Exec(ctx,
			`UPDATE webhooks SET last_success_at = now(), failure_count = 0, updated_at = now() WHERE id = $1::uuid`,
			webhookID,
		)
	} else {
		database.Pool.Exec(ctx,
			`UPDATE webhooks SET last_failure_at = now(), failure_count = failure_count + 1, updated_at = now() WHERE id = $1::uuid`,
			webhookID,
		)
	}
}

func Deliver(ctx context.Context, webhookID, url, secret, event string, data any) bool {
	payload := WebhookPayload{
		Event:     event,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		Data:      data,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		log.Printf("[webhooks] marshal error: %v", err)
		return false
	}

	sig := signPayload(body, secret)

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(body))
	if err != nil {
		log.Printf("[webhooks] request error: %v", err)
		return false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Webhook-Signature", sig)
	req.Header.Set("X-Webhook-Event", event)
	req.Header.Set("User-Agent", "Closetalk-Webhook/1.0")

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[webhooks] delivery error to %s: %v", url, err)
		UpdateWebhookStatus(ctx, webhookID, false, err.Error())
		return false
	}
	defer resp.Body.Close()
	io.Copy(io.Discard, resp.Body)

	success := resp.StatusCode >= 200 && resp.StatusCode < 300
	UpdateWebhookStatus(ctx, webhookID, success, "")
	if !success {
		log.Printf("[webhooks] non-2xx response from %s: %d", url, resp.StatusCode)
	}
	return success
}

func DeliverWithRetry(ctx context.Context, webhookID, url, secret, event string, data any, maxRetries int) bool {
	baseDelay := 1 * time.Second
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			delay := baseDelay * (1 << (attempt - 1))
			log.Printf("[webhooks] retry %d/%d for %s after %v", attempt, maxRetries, url, delay)
			select {
			case <-ctx.Done():
				return false
			case <-time.After(delay):
			}
		}
		if Deliver(ctx, webhookID, url, secret, event, data) {
			return true
		}
	}
	return false
}

func signPayload(body []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}
