package notifications

import (
	"context"
	"log"
	"os"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

var client *messaging.Client

func Init() {
	credPath := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	if credPath == "" {
		log.Println("[notifications] GOOGLE_APPLICATION_CREDENTIALS not set, push disabled")
		return
	}

	opt := option.WithCredentialsFile(credPath)
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		log.Printf("[notifications] init error: %v", err)
		return
	}

	client, err = app.Messaging(context.Background())
	if err != nil {
		log.Printf("[notifications] messaging init error: %v", err)
		return
	}

	log.Println("[notifications] Firebase initialized")
}

func Send(ctx context.Context, token, title, body string, data map[string]string) {
	if client == nil {
		return
	}

	msg := &messaging.Message{
		Token: token,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
	}

	_, err := client.Send(ctx, msg)
	if err != nil {
		log.Printf("[notifications] send error: %v", err)
	}
}

func SendWithRetry(ctx context.Context, token, title, body string, data map[string]string, maxRetries int) {
	if client == nil {
		return
	}

	baseDelay := 500 * time.Millisecond
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			delay := baseDelay * (1 << (attempt - 1))
			log.Printf("[notifications] retry %d/%d after %v", attempt, maxRetries, delay)
			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
		}
		msg := &messaging.Message{
			Token: token,
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
		}
		_, err := client.Send(ctx, msg)
		if err == nil {
			return
		}
		log.Printf("[notifications] attempt %d error: %v", attempt+1, err)
	}
}
