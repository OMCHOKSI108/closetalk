class Contact {
  final String id;
  final String contactId;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final String status;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? conversationId;
  final DateTime createdAt;

  Contact({
    required this.id,
    required this.contactId,
    required this.username,
    required this.displayName,
    this.avatarUrl = '',
    this.bio = '',
    required this.status,
    this.isOnline = false,
    this.lastSeen,
    this.conversationId,
    required this.createdAt,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    final contactId =
        json['contact_id'] as String? ?? json['id'] as String? ?? '';
    return Contact(
      id: json['id'] as String? ?? contactId,
      contactId: contactId,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      conversationId: json['conversation_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  bool get isAccepted => status == 'accepted';
  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';
  bool get isBlocked => status == 'blocked';
}

class UserPublicProfile {
  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final bool isOnline;
  final DateTime? lastSeen;
  final String? contactStatus;
  final DateTime createdAt;

  UserPublicProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl = '',
    this.bio = '',
    this.isOnline = false,
    this.lastSeen,
    this.contactStatus,
    required this.createdAt,
  });

  factory UserPublicProfile.fromJson(Map<String, dynamic> json) {
    return UserPublicProfile(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      contactStatus: json['contact_status'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class DirectConversationResponse {
  final String chatId;

  DirectConversationResponse({required this.chatId});

  factory DirectConversationResponse.fromJson(Map<String, dynamic> json) {
    return DirectConversationResponse(
      chatId: json['chat_id'] as String,
    );
  }
}
