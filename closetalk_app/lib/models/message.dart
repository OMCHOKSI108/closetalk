class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String? senderUsername;
  final String content;
  final String contentType;
  final String? mediaUrl;
  final String? mediaId;
  final String? replyToId;
  final String? forwardedFrom;
  final String status;
  final String? moderationStatus;
  final bool isDeleted;
  final List<Reaction> reactions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? disappearedAt;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderUsername,
    required this.content,
    this.contentType = 'text',
    this.mediaUrl,
    this.mediaId,
    this.replyToId,
    this.forwardedFrom,
    this.status = 'sending',
    this.moderationStatus,
    this.isDeleted = false,
    this.reactions = const [],
    required this.createdAt,
    this.editedAt,
    this.disappearedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      senderId: json['sender_id'] as String,
      senderUsername: json['sender_username'] as String?,
      content: json['content'] as String,
      contentType: json['content_type'] as String? ?? 'text',
      mediaUrl: json['media_url'] as String?,
      mediaId: json['media_id'] as String?,
      replyToId: json['reply_to_id'] as String?,
      forwardedFrom: json['forwarded_from'] as String?,
      status: json['status'] as String? ?? 'sent',
      moderationStatus: json['moderation_status'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => Reaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : null,
      disappearedAt: json['disappeared_at'] != null
          ? DateTime.parse(json['disappeared_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_id': chatId,
        'sender_id': senderId,
        'sender_username': senderUsername,
        'content': content,
        'content_type': contentType,
        'media_url': mediaUrl,
        'media_id': mediaId,
        'reply_to_id': replyToId,
        'forwarded_from': forwardedFrom,
        'status': status,
        'moderation_status': moderationStatus,
        'is_deleted': isDeleted,
        'reactions': reactions.map((r) => r.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'edited_at': editedAt?.toIso8601String(),
        'disappeared_at': disappearedAt?.toIso8601String(),
      };

  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderUsername,
    String? content,
    String? contentType,
    String? mediaUrl,
    String? mediaId,
    String? replyToId,
    String? forwardedFrom,
    String? status,
    String? moderationStatus,
    bool? isDeleted,
    List<Reaction>? reactions,
    DateTime? createdAt,
    DateTime? editedAt,
    DateTime? disappearedAt,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderUsername: senderUsername ?? this.senderUsername,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaId: mediaId ?? this.mediaId,
      replyToId: replyToId ?? this.replyToId,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      status: status ?? this.status,
      moderationStatus: moderationStatus ?? this.moderationStatus,
      isDeleted: isDeleted ?? this.isDeleted,
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      disappearedAt: disappearedAt ?? this.disappearedAt,
    );
  }
}

class Reaction {
  final String userId;
  final String emoji;
  final DateTime createdAt;

  Reaction({
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: json['user_id'] as String,
      emoji: json['emoji'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'emoji': emoji,
        'created_at': createdAt.toIso8601String(),
      };
}

class SearchResult {
  final String messageId;
  final String chatId;
  final String senderId;
  final String senderName;
  final String content;
  final String contentType;
  final String snippet;
  final DateTime createdAt;

  SearchResult({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.contentType,
    required this.snippet,
    required this.createdAt,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      messageId: json['message_id'] as String,
      chatId: json['chat_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String? ?? '',
      content: json['content'] as String,
      contentType: json['content_type'] as String? ?? 'text',
      snippet: json['snippet'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SearchMessagesResponse {
  final List<SearchResult> results;
  final String? nextCursor;
  final bool hasMore;

  SearchMessagesResponse({
    required this.results,
    this.nextCursor,
    this.hasMore = false,
  });

  factory SearchMessagesResponse.fromJson(Map<String, dynamic> json) {
    return SearchMessagesResponse(
      results: (json['results'] as List<dynamic>?)
              ?.map((e) => SearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class PaginatedMessages {
  final List<Message> messages;
  final String? nextCursor;
  final bool hasMore;

  PaginatedMessages({
    required this.messages,
    this.nextCursor,
    this.hasMore = false,
  });

  factory PaginatedMessages.fromJson(Map<String, dynamic> json) {
    return PaginatedMessages(
      messages: (json['messages'] as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
