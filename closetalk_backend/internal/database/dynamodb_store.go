package database

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/OMCHOKSI108/closetalk/internal/model"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/google/uuid"
)

var Dynamo *dynamodb.Client

func ConnectDynamoDB() error {
	ctx := context.Background()

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	endpoint := os.Getenv("DYNAMODB_ENDPOINT")

	var cfg aws.Config
	var err error

	if endpoint != "" {
		cfg, err = config.LoadDefaultConfig(ctx,
			config.WithRegion(region),
			config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider("dummy", "dummy", "")),
		)
	} else {
		cfg, err = config.LoadDefaultConfig(ctx, config.WithRegion(region))
	}
	if err != nil {
		return fmt.Errorf("dynamodb config: %w", err)
	}

	Dynamo = dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
		}
	})

	// Verify connection
	if _, err := Dynamo.ListTables(ctx, &dynamodb.ListTablesInput{}); err != nil {
		return fmt.Errorf("dynamodb ping: %w", err)
	}

	log.Println("[dynamodb] connected")
	return nil
}

func InitDynamoDBSchema() error {
	ctx := context.Background()

	tables := []struct {
		Name    string
		PK      string
		SK      string
		GSIs    []types.GlobalSecondaryIndex
		AttrDef []types.AttributeDefinition
	}{
		{
			Name: "closetalk-messages",
			PK:   "chat_id",
			SK:   "sort_key",
			AttrDef: []types.AttributeDefinition{
				{AttributeName: aws.String("chat_id"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("sort_key"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("message_id"), AttributeType: types.ScalarAttributeTypeS},
			},
			GSIs: []types.GlobalSecondaryIndex{
				{
					IndexName: aws.String("message_id-index"),
					KeySchema: []types.KeySchemaElement{
						{AttributeName: aws.String("message_id"), KeyType: types.KeyTypeHash},
					},
					Projection: &types.Projection{
						ProjectionType: types.ProjectionTypeAll,
					},
				},
			},
		},
		{
			Name: "closetalk-message-reactions",
			PK:   "message_id",
			SK:   "user_emoji",
			AttrDef: []types.AttributeDefinition{
				{AttributeName: aws.String("message_id"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("user_emoji"), AttributeType: types.ScalarAttributeTypeS},
			},
		},
		{
			Name: "closetalk-message-reads",
			PK:   "message_id",
			SK:   "user_id",
			AttrDef: []types.AttributeDefinition{
				{AttributeName: aws.String("message_id"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
			},
		},
		{
			Name: "closetalk-bookmarks",
			PK:   "user_id",
			SK:   "sort_key",
			AttrDef: []types.AttributeDefinition{
				{AttributeName: aws.String("user_id"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("sort_key"), AttributeType: types.ScalarAttributeTypeS},
				{AttributeName: aws.String("message_id"), AttributeType: types.ScalarAttributeTypeS},
			},
			GSIs: []types.GlobalSecondaryIndex{
				{
					IndexName: aws.String("message_id-index"),
					KeySchema: []types.KeySchemaElement{
						{AttributeName: aws.String("message_id"), KeyType: types.KeyTypeHash},
					},
					Projection: &types.Projection{
						ProjectionType: types.ProjectionTypeAll,
					},
				},
			},
		},
	}

	for _, t := range tables {
		existing, err := Dynamo.DescribeTable(ctx, &dynamodb.DescribeTableInput{
			TableName: aws.String(t.Name),
		})
		if err == nil {
			log.Printf("[dynamodb] table %s already exists (%d items)", t.Name, existing.Table.ItemCount)
			continue
		}

		keySchema := []types.KeySchemaElement{
			{AttributeName: aws.String(t.PK), KeyType: types.KeyTypeHash},
			{AttributeName: aws.String(t.SK), KeyType: types.KeyTypeRange},
		}

		input := &dynamodb.CreateTableInput{
			TableName:            aws.String(t.Name),
			KeySchema:            keySchema,
			AttributeDefinitions: t.AttrDef,
			BillingMode:          types.BillingModePayPerRequest,
		}

		if len(t.GSIs) > 0 {
			input.GlobalSecondaryIndexes = t.GSIs
		}

		if _, err := Dynamo.CreateTable(ctx, input); err != nil {
			return fmt.Errorf("create table %s: %w", t.Name, err)
		}

		log.Printf("[dynamodb] table %s created", t.Name)

		// Wait for table to become active
		waiter := dynamodb.NewTableExistsWaiter(Dynamo)
		if err := waiter.Wait(ctx, &dynamodb.DescribeTableInput{
			TableName: aws.String(t.Name),
		}, 30*time.Second); err != nil {
			return fmt.Errorf("wait for table %s: %w", t.Name, err)
		}
	}

	log.Println("[dynamodb] schema initialized")
	return nil
}

func CloseDynamoDB() {
	Dynamo = nil
	log.Println("[dynamodb] connection closed")
}

// ─── DynamoDB helpers ──────────────────────────────────────────────────────

func sortKeyFromTime(t time.Time, id uuid.UUID) string {
	return fmt.Sprintf("%s#%s", t.UTC().Format(time.RFC3339Nano), id.String())
}

func timeFromSortKey(sk string) (time.Time, error) {
	parts := split2(sk, "#")
	if len(parts) < 2 {
		return time.Time{}, fmt.Errorf("invalid sort_key: %s", sk)
	}
	return time.Parse(time.RFC3339Nano, parts[0])
}

func split2(s, sep string) []string {
	for i := 0; i < len(s)-len(sep); i++ {
		if s[i:i+len(sep)] == sep {
			return []string{s[:i], s[i+len(sep):]}
		}
	}
	return []string{s}
}

type dynamoMessage struct {
	ChatID           string   `dynamodbav:"chat_id"`
	SortKey          string   `dynamodbav:"sort_key"`
	MessageID        string   `dynamodbav:"message_id"`
	SenderID         string   `dynamodbav:"sender_id"`
	SenderDeviceID   string   `dynamodbav:"sender_device_id,omitempty"`
	RecipientIDs     []string `dynamodbav:"recipient_ids,omitempty"`
	Content          string   `dynamodbav:"content"`
	ContentType      string   `dynamodbav:"content_type"`
	MediaURL         string   `dynamodbav:"media_url,omitempty"`
	MediaID          string   `dynamodbav:"media_id,omitempty"`
	ReplyToID        string   `dynamodbav:"reply_to_id,omitempty"`
	Status           string   `dynamodbav:"status"`
	ModerationStatus string   `dynamodbav:"moderation_status,omitempty"`
	EditHistory      string   `dynamodbav:"edit_history,omitempty"`
	IsDeleted        bool     `dynamodbav:"is_deleted"`
	CreatedAt        string   `dynamodbav:"created_at"`
	EditedAt         string   `dynamodbav:"edited_at,omitempty"`
	DisappearedAt    string   `dynamodbav:"disappeared_at,omitempty"`
}

type dynamoReaction struct {
	MessageID string `dynamodbav:"message_id"`
	UserEmoji string `dynamodbav:"user_emoji"`
	UserID    string `dynamodbav:"user_id"`
	Emoji     string `dynamodbav:"emoji"`
	CreatedAt string `dynamodbav:"created_at"`
}

type dynamoRead struct {
	MessageID string `dynamodbav:"message_id"`
	UserID    string `dynamodbav:"user_id"`
	ReadAt    string `dynamodbav:"read_at"`
}

type dynamoBookmark struct {
	UserID         string `dynamodbav:"user_id"`
	SortKey        string `dynamodbav:"sort_key"`
	MessageID      string `dynamodbav:"message_id"`
	ChatID         string `dynamodbav:"chat_id"`
	ContentPreview string `dynamodbav:"content_preview"`
	CreatedAt      string `dynamodbav:"created_at"`
}

type DynamoDBStore struct{}

func NewDynamoDBStore() *DynamoDBStore {
	return &DynamoDBStore{}
}

func (s *DynamoDBStore) InsertMessage(ctx context.Context, msg *model.Message) error {
	editHistory := ""
	if len(msg.EditHistory) > 0 {
		b, _ := json.Marshal(msg.EditHistory)
		editHistory = string(b)
	}

	item := dynamoMessage{
		ChatID:           msg.ChatID,
		SortKey:          sortKeyFromTime(msg.CreatedAt, msg.ID),
		MessageID:        msg.ID.String(),
		SenderID:         msg.SenderID,
		SenderDeviceID:   msg.SenderDeviceID,
		RecipientIDs:     msg.RecipientIDs,
		Content:          msg.Content,
		ContentType:      msg.ContentType,
		MediaURL:         msg.MediaURL,
		MediaID:          msg.MediaID,
		ReplyToID:        replyToPtr(msg.ReplyToID),
		Status:           msg.Status,
		ModerationStatus: msg.ModerationStatus,
		EditHistory:      editHistory,
		IsDeleted:        msg.IsDeleted,
		CreatedAt:        msg.CreatedAt.UTC().Format(time.RFC3339Nano),
	}
	if msg.DisappearedAt != nil {
		item.DisappearedAt = msg.DisappearedAt.UTC().Format(time.RFC3339Nano)
	}

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		return fmt.Errorf("marshal message: %w", err)
	}

	_, err = Dynamo.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String("closetalk-messages"),
		Item:      av,
	})
	return err
}

func (s *DynamoDBStore) GetMessage(ctx context.Context, messageID uuid.UUID) (*model.Message, error) {
	result, err := Dynamo.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String("closetalk-messages"),
		IndexName:              aws.String("message_id-index"),
		KeyConditionExpression: aws.String("message_id = :mid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":mid": &types.AttributeValueMemberS{Value: messageID.String()},
		},
		Limit: aws.Int32(1),
	})
	if err != nil {
		return nil, fmt.Errorf("get message: %w", err)
	}
	if len(result.Items) == 0 {
		return nil, fmt.Errorf("message not found")
	}

	return unmarshalMessage(result.Items[0])
}

func (s *DynamoDBStore) GetMessages(ctx context.Context, chatID string, cursor time.Time, limit int) ([]*model.Message, bool, error) {
	cursorKey := sortKeyFromTime(cursor, uuid.Nil)

	expr := "chat_id = :cid AND sort_key < :cursor"
	attrVals := map[string]types.AttributeValue{
		":cid":    &types.AttributeValueMemberS{Value: chatID},
		":cursor": &types.AttributeValueMemberS{Value: cursorKey},
	}

	result, err := Dynamo.Query(ctx, &dynamodb.QueryInput{
		TableName:                 aws.String("closetalk-messages"),
		KeyConditionExpression:    aws.String(expr),
		ExpressionAttributeValues: attrVals,
		Limit:                     aws.Int32(int32(limit)),
		ScanIndexForward:          aws.Bool(false),
	})
	if err != nil {
		return nil, false, fmt.Errorf("get messages: %w", err)
	}

	hasMore := result.LastEvaluatedKey != nil

	messages := make([]*model.Message, 0, len(result.Items))
	now := time.Now()
	for _, item := range result.Items {
		msg, err := unmarshalMessage(item)
		if err != nil {
			continue
		}
		if msg.IsDeleted {
			continue
		}
		if msg.DisappearedAt != nil && msg.DisappearedAt.Before(now) {
			continue
		}
		messages = append(messages, msg)
	}

	return messages, hasMore, nil
}

func (s *DynamoDBStore) UpdateMessage(ctx context.Context, msg *model.Message) error {
	editHistory := ""
	if len(msg.EditHistory) > 0 {
		b, _ := json.Marshal(msg.EditHistory)
		editHistory = string(b)
	}

	var editedAt string
	if msg.EditedAt != nil {
		editedAt = msg.EditedAt.UTC().Format(time.RFC3339Nano)
	}

	_, err := Dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String("closetalk-messages"),
		Key: map[string]types.AttributeValue{
			"chat_id":  &types.AttributeValueMemberS{Value: msg.ChatID},
			"sort_key": &types.AttributeValueMemberS{Value: sortKeyFromTime(msg.CreatedAt, msg.ID)},
		},
		UpdateExpression: aws.String("SET content = :c, edit_history = :e, edited_at = :ea, #s = :st, moderation_status = :ms"),
		ExpressionAttributeNames: map[string]string{
			"#s": "status",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":c":  &types.AttributeValueMemberS{Value: msg.Content},
			":e":  &types.AttributeValueMemberS{Value: editHistory},
			":ea": &types.AttributeValueMemberS{Value: editedAt},
			":st": &types.AttributeValueMemberS{Value: msg.Status},
			":ms": &types.AttributeValueMemberS{Value: msg.ModerationStatus},
		},
	})
	return err
}

func (s *DynamoDBStore) DeleteMessage(ctx context.Context, messageID uuid.UUID) error {
	msg, err := s.GetMessage(ctx, messageID)
	if err != nil {
		return err
	}

	_, err = Dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String("closetalk-messages"),
		Key: map[string]types.AttributeValue{
			"chat_id":  &types.AttributeValueMemberS{Value: msg.ChatID},
			"sort_key": &types.AttributeValueMemberS{Value: sortKeyFromTime(msg.CreatedAt, msg.ID)},
		},
		UpdateExpression: aws.String("SET is_deleted = :d"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":d": &types.AttributeValueMemberBOOL{Value: true},
		},
	})
	return err
}

func (s *DynamoDBStore) AddReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	item := dynamoReaction{
		MessageID: messageID.String(),
		UserEmoji: userID + "#" + emoji,
		UserID:    userID,
		Emoji:     emoji,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		return err
	}

	_, err = Dynamo.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String("closetalk-message-reactions"),
		Item:      av,
	})
	return err
}

func (s *DynamoDBStore) RemoveReaction(ctx context.Context, messageID uuid.UUID, userID string, emoji string) error {
	_, err := Dynamo.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String("closetalk-message-reactions"),
		Key: map[string]types.AttributeValue{
			"message_id": &types.AttributeValueMemberS{Value: messageID.String()},
			"user_emoji": &types.AttributeValueMemberS{Value: userID + "#" + emoji},
		},
	})
	return err
}

func (s *DynamoDBStore) GetReactions(ctx context.Context, messageID uuid.UUID) ([]model.Reaction, error) {
	result, err := Dynamo.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String("closetalk-message-reactions"),
		KeyConditionExpression: aws.String("message_id = :mid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":mid": &types.AttributeValueMemberS{Value: messageID.String()},
		},
	})
	if err != nil {
		return nil, err
	}

	reactions := make([]model.Reaction, 0, len(result.Items))
	for _, item := range result.Items {
		var dr dynamoReaction
		if err := attributevalue.UnmarshalMap(item, &dr); err != nil {
			continue
		}
		createdAt, _ := time.Parse(time.RFC3339Nano, dr.CreatedAt)
		reactions = append(reactions, model.Reaction{
			UserID: dr.UserID, Emoji: dr.Emoji, CreatedAt: createdAt,
		})
	}

	if reactions == nil {
		return []model.Reaction{}, nil
	}
	return reactions, nil
}

func (s *DynamoDBStore) MarkDelivered(ctx context.Context, messageID uuid.UUID) error {
	msg, err := s.GetMessage(ctx, messageID)
	if err != nil {
		return err
	}
	_, err = Dynamo.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String("closetalk-messages"),
		Key: map[string]types.AttributeValue{
			"chat_id":  &types.AttributeValueMemberS{Value: msg.ChatID},
			"sort_key": &types.AttributeValueMemberS{Value: sortKeyFromTime(msg.CreatedAt, msg.ID)},
		},
		UpdateExpression: aws.String("SET #s = :st"),
		ExpressionAttributeNames: map[string]string{
			"#s": "status",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":st": &types.AttributeValueMemberS{Value: "delivered"},
		},
	})
	return err
}

func (s *DynamoDBStore) MarkRead(ctx context.Context, messageID uuid.UUID, userID string) error {
	item := dynamoRead{
		MessageID: messageID.String(),
		UserID:    userID,
		ReadAt:    time.Now().UTC().Format(time.RFC3339Nano),
	}

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		return err
	}

	_, err = Dynamo.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String("closetalk-message-reads"),
		Item:      av,
	})
	return err
}

func (s *DynamoDBStore) BookmarkMessage(ctx context.Context, userID string, messageID uuid.UUID, chatID string, preview string) error {
	now := time.Now()
	item := dynamoBookmark{
		UserID:         userID,
		SortKey:        sortKeyFromTime(now, messageID),
		MessageID:      messageID.String(),
		ChatID:         chatID,
		ContentPreview: preview,
		CreatedAt:      now.UTC().Format(time.RFC3339Nano),
	}

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		return err
	}

	_, err = Dynamo.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String("closetalk-bookmarks"),
		Item:      av,
	})
	return err
}

func (s *DynamoDBStore) RemoveBookmark(ctx context.Context, userID string, messageID uuid.UUID) error {
	result, err := Dynamo.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String("closetalk-bookmarks"),
		IndexName:              aws.String("message_id-index"),
		KeyConditionExpression: aws.String("message_id = :mid"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":mid": &types.AttributeValueMemberS{Value: messageID.String()},
		},
		Limit: aws.Int32(1),
	})
	if err != nil {
		return err
	}

	if len(result.Items) == 0 {
		return nil
	}

	var db dynamoBookmark
	if err := attributevalue.UnmarshalMap(result.Items[0], &db); err != nil {
		return err
	}

	_, err = Dynamo.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String("closetalk-bookmarks"),
		Key: map[string]types.AttributeValue{
			"user_id":  &types.AttributeValueMemberS{Value: db.UserID},
			"sort_key": &types.AttributeValueMemberS{Value: db.SortKey},
		},
	})
	return err
}

func (s *DynamoDBStore) ListBookmarks(ctx context.Context, userID string, cursor time.Time, limit int) ([]model.BookmarkResponse, bool, error) {
	cursorKey := sortKeyFromTime(cursor, uuid.Nil)

	queryInput := &dynamodb.QueryInput{
		TableName:              aws.String("closetalk-bookmarks"),
		KeyConditionExpression: aws.String("user_id = :uid AND sort_key < :cursor"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":uid":    &types.AttributeValueMemberS{Value: userID},
			":cursor": &types.AttributeValueMemberS{Value: cursorKey},
		},
		ScanIndexForward: aws.Bool(false),
		Limit:            aws.Int32(int32(limit)),
	}

	result, err := Dynamo.Query(ctx, queryInput)
	if err != nil {
		return nil, false, err
	}

	hasMore := result.LastEvaluatedKey != nil

	bookmarks := make([]model.BookmarkResponse, 0, len(result.Items))
	for _, item := range result.Items {
		var db dynamoBookmark
		if err := attributevalue.UnmarshalMap(item, &db); err != nil {
			continue
		}
		createdAt, _ := time.Parse(time.RFC3339Nano, db.CreatedAt)
		msgID, _ := uuid.Parse(db.MessageID)
		bookmarks = append(bookmarks, model.BookmarkResponse{
			MessageID: msgID.String(),
			ChatID:    db.ChatID,
			Preview:   db.ContentPreview,
			CreatedAt: createdAt,
		})
	}

	return bookmarks, hasMore, nil
}

// ─── Helpers ────────────────────────────────────────────────────────────────

func replyToPtr(id *uuid.UUID) string {
	if id == nil {
		return ""
	}
	return id.String()
}

func unmarshalMessage(item map[string]types.AttributeValue) (*model.Message, error) {
	var dm dynamoMessage
	if err := attributevalue.UnmarshalMap(item, &dm); err != nil {
		return nil, err
	}

	createdAt, err := time.Parse(time.RFC3339Nano, dm.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("parse created_at: %w", err)
	}

	msgID, err := uuid.Parse(dm.MessageID)
	if err != nil {
		return nil, fmt.Errorf("parse message_id: %w", err)
	}

	var replyToID *uuid.UUID
	if dm.ReplyToID != "" {
		if id, err := uuid.Parse(dm.ReplyToID); err == nil {
			replyToID = &id
		}
	}

	var editHistory []model.EditEntry
	if dm.EditHistory != "" {
		json.Unmarshal([]byte(dm.EditHistory), &editHistory)
	}
	if editHistory == nil {
		editHistory = []model.EditEntry{}
	}

	var editedAt *time.Time
	if dm.EditedAt != "" {
		if t, err := time.Parse(time.RFC3339Nano, dm.EditedAt); err == nil {
			editedAt = &t
		}
	}

	var disappearedAt *time.Time
	if dm.DisappearedAt != "" {
		if t, err := time.Parse(time.RFC3339Nano, dm.DisappearedAt); err == nil {
			disappearedAt = &t
		}
	}

	return &model.Message{
		ID:               msgID,
		ChatID:           dm.ChatID,
		SenderID:         dm.SenderID,
		SenderDeviceID:   dm.SenderDeviceID,
		RecipientIDs:     dm.RecipientIDs,
		Content:          dm.Content,
		ContentType:      dm.ContentType,
		MediaURL:         dm.MediaURL,
		MediaID:          dm.MediaID,
		ReplyToID:        replyToID,
		Status:           dm.Status,
		ModerationStatus: dm.ModerationStatus,
		EditHistory:      editHistory,
		IsDeleted:        dm.IsDeleted,
		CreatedAt:        createdAt,
		EditedAt:         editedAt,
		DisappearedAt:    disappearedAt,
	}, nil
}

func (s *DynamoDBStore) SearchMessages(ctx context.Context, chatID string, query string, cursor time.Time, limit int) ([]*model.Message, bool, error) {
	queryLower := strings.ToLower(query)

	cursorKey := sortKeyFromTime(cursor, uuid.Nil)

	result, err := Dynamo.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String("closetalk-messages"),
		KeyConditionExpression: aws.String("chat_id = :cid AND sort_key < :cursor"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":cid":    &types.AttributeValueMemberS{Value: chatID},
			":cursor": &types.AttributeValueMemberS{Value: cursorKey},
		},
		ScanIndexForward: aws.Bool(false),
		Limit:            aws.Int32(100),
	})
	if err != nil {
		return nil, false, fmt.Errorf("search messages: %w", err)
	}

	var matched []*model.Message
	now := time.Now()
	for _, item := range result.Items {
		msg, err := unmarshalMessage(item)
		if err != nil || msg.IsDeleted {
			continue
		}
		if msg.DisappearedAt != nil && msg.DisappearedAt.Before(now) {
			continue
		}
		if strings.Contains(strings.ToLower(msg.Content), queryLower) {
			matched = append(matched, msg)
		}
	}

	hasMore := result.LastEvaluatedKey != nil

	if len(matched) > limit {
		matched = matched[:limit]
	}

	return matched, hasMore, nil
}

func (s *DynamoDBStore) DeleteExpiredMessages(ctx context.Context) (int64, error) {
	return 0, nil
}

var _ MessageStore = (*DynamoDBStore)(nil)
