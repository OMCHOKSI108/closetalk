package notifications

import (
	"context"
	"log"
	"os"

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
