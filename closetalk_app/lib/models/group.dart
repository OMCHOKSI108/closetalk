class Group {
  final String id;
  final String name;
  final String description;
  final String avatarUrl;
  final String createdBy;
  final bool isPublic;
  final int memberLimit;
  final int memberCount;
  final String messageRetention;
  final String disappearingMsg;
  final String? inviteCode;
  final bool isMuted;
  final DateTime? mutedUntil;
  final String role;
  final List<GroupMember> members;
  final List<PinnedMessage> pinnedMessages;
  final DateTime createdAt;
  final DateTime updatedAt;

  Group({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarUrl = '',
    required this.createdBy,
    this.isPublic = false,
    this.memberLimit = 1000,
    this.memberCount = 0,
    this.messageRetention = 'off',
    this.disappearingMsg = 'off',
    this.inviteCode,
    this.isMuted = false,
    this.mutedUntil,
    this.role = 'member',
    this.members = const [],
    this.pinnedMessages = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      createdBy: json['created_by'] as String,
      isPublic: json['is_public'] as bool? ?? false,
      memberLimit: json['member_limit'] as int? ?? 1000,
      memberCount: json['member_count'] as int? ?? 0,
      messageRetention: json['message_retention'] as String? ?? 'off',
      disappearingMsg: json['disappearing_msg'] as String? ?? 'off',
      inviteCode: json['invite_code'] as String?,
      isMuted: json['is_muted'] as bool? ?? false,
      mutedUntil: DateTime.tryParse(json['muted_until'] as String? ?? ''),
      role: json['role'] as String? ?? 'member',
      members: (json['members'] as List<dynamic>?)
              ?.map((m) => GroupMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      pinnedMessages: (json['pinned_messages'] as List<dynamic>?)
              ?.map((p) => PinnedMessage.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'created_by': createdBy,
        'is_public': isPublic,
        'member_limit': memberLimit,
        'member_count': memberCount,
        'message_retention': messageRetention,
        'disappearing_msg': disappearingMsg,
        'invite_code': inviteCode,
        'is_muted': isMuted,
        'muted_until': mutedUntil?.toIso8601String(),
        'role': role,
        'members': members.map((m) => m.toJson()).toList(),
        'pinned_messages': pinnedMessages.map((p) => p.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class GroupMember {
  final String userId;
  final String displayName;
  final String avatarUrl;
  final String role;
  final DateTime joinedAt;

  GroupMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl = '',
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String? ?? '',
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'role': role,
        'joined_at': joinedAt.toIso8601String(),
      };
}

class PinnedMessage {
  final String messageId;
  final String pinnedBy;
  final DateTime pinnedAt;

  PinnedMessage({
    required this.messageId,
    required this.pinnedBy,
    required this.pinnedAt,
  });

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      messageId: json['message_id'] as String,
      pinnedBy: json['pinned_by'] as String,
      pinnedAt: DateTime.parse(json['pinned_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'pinned_by': pinnedBy,
        'pinned_at': pinnedAt.toIso8601String(),
      };
}

class GroupListItem {
  final String id;
  final String name;
  final String description;
  final String avatarUrl;
  final bool isPublic;
  final int memberLimit;
  final int memberCount;
  final String role;
  final bool isMuted;
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupListItem({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarUrl = '',
    this.isPublic = false,
    this.memberLimit = 1000,
    this.memberCount = 0,
    this.role = 'member',
    this.isMuted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupListItem.fromJson(Map<String, dynamic> json) {
    return GroupListItem(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      isPublic: json['is_public'] as bool? ?? false,
      memberLimit: json['member_limit'] as int? ?? 1000,
      memberCount: json['member_count'] as int? ?? 0,
      role: json['role'] as String? ?? 'member',
      isMuted: json['is_muted'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class CreateGroupRequest {
  final String name;
  final String? description;
  final String? avatarUrl;
  final List<String> memberIds;
  final bool isPublic;

  CreateGroupRequest({
    required this.name,
    this.description,
    this.avatarUrl,
    this.memberIds = const [],
    this.isPublic = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'avatar_url': avatarUrl,
        'member_ids': memberIds,
        'is_public': isPublic,
      };
}

class UpdateGroupSettingsRequest {
  final String? name;
  final String? description;
  final String? avatarUrl;
  final bool? isPublic;
  final int? memberLimit;
  final String? messageRetention;
  final String? disappearingMsg;

  UpdateGroupSettingsRequest({
    this.name,
    this.description,
    this.avatarUrl,
    this.isPublic,
    this.memberLimit,
    this.messageRetention,
    this.disappearingMsg,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (avatarUrl != null) map['avatar_url'] = avatarUrl;
    if (isPublic != null) map['is_public'] = isPublic;
    if (memberLimit != null) map['member_limit'] = memberLimit;
    if (messageRetention != null) map['message_retention'] = messageRetention;
    if (disappearingMsg != null) map['disappearing_msg'] = disappearingMsg;
    return map;
  }
}

class InviteResponse {
  final String code;
  final DateTime expiresAt;
  final String url;

  InviteResponse({
    required this.code,
    required this.expiresAt,
    required this.url,
  });

  factory InviteResponse.fromJson(Map<String, dynamic> json) {
    return InviteResponse(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      url: json['url'] as String,
    );
  }
}
