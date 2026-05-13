package media

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/google/uuid"
)

var client *s3.Client
var bucket string
var publicURL string
var enabled bool

func Init() {
	bucket = os.Getenv("S3_BUCKET")
	if bucket == "" {
		log.Println("[media] S3_BUCKET not set, media pipeline disabled")
		return
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}

	publicBase := os.Getenv("S3_PUBLIC_URL")
	if publicBase == "" {
		publicBase = fmt.Sprintf("https://%s.s3.%s.amazonaws.com", bucket, region)
	}
	publicURL = strings.TrimRight(publicBase, "/")

	opts := []func(*config.LoadOptions) error{
		config.WithRegion(region),
	}
	if key := os.Getenv("AWS_ACCESS_KEY_ID"); key != "" {
		secret := os.Getenv("AWS_SECRET_ACCESS_KEY")
		opts = append(opts, config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(key, secret, "")))
	}

	cfg, err := config.LoadDefaultConfig(context.Background(), opts...)
	if err != nil {
		log.Printf("[media] config error: %v", err)
		return
	}

	client = s3.NewFromConfig(cfg)
	enabled = true
	log.Printf("[media] S3 initialized (bucket: %s, region: %s)", bucket, region)
}

func IsEnabled() bool { return enabled }

func GenerateUploadURL(ctx context.Context, fileName string, contentType string) (string, string, error) {
	if !enabled {
		return "", "", fmt.Errorf("media pipeline not configured")
	}

	ext := filepath.Ext(fileName)
	objectKey := fmt.Sprintf("uploads/%s%s", uuid.New().String(), ext)

	if contentType == "" {
		contentType = mime.TypeByExtension(ext)
		if contentType == "" {
			contentType = "application/octet-stream"
		}
	}

	// Short-lived pre-signed URL (15 minutes)
	presignClient := s3.NewPresignClient(client, func(opts *s3.PresignOptions) {
		opts.Expires = 15 * time.Minute
	})

	req, err := presignClient.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(objectKey),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", "", fmt.Errorf("presign put: %w", err)
	}

	mediaURL := publicURL + "/" + objectKey
	return req.URL, mediaURL, nil
}

func GenerateUploadURLWithFolder(ctx context.Context, folder, fileName, contentType string) (string, string, error) {
	if !enabled {
		return "", "", fmt.Errorf("media pipeline not configured")
	}

	ext := filepath.Ext(fileName)
	objectKey := fmt.Sprintf("%s/%s%s", folder, uuid.New().String(), ext)

	if contentType == "" {
		contentType = mime.TypeByExtension(ext)
		if contentType == "" {
			contentType = "application/octet-stream"
		}
	}

	presignClient := s3.NewPresignClient(client, func(opts *s3.PresignOptions) {
		opts.Expires = 15 * time.Minute
	})

	req, err := presignClient.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(objectKey),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", "", fmt.Errorf("presign put: %w", err)
	}

	mediaURL := publicURL + "/" + objectKey
	return req.URL, mediaURL, nil
}

func PutObject(ctx context.Context, objectKey string, data []byte, contentType string) (string, error) {
	if !enabled {
		return "", fmt.Errorf("media pipeline not configured")
	}
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(objectKey),
		Body:        bytes.NewReader(data),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", fmt.Errorf("s3 put object: %w", err)
	}
	mediaURL := publicURL + "/" + objectKey
	return mediaURL, nil
}

func DeleteObject(ctx context.Context, objectKey string) error {
	if !enabled {
		return nil
	}

	_, err := client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(objectKey),
	})
	return err
}
