class User {
  final String id;
  final String? email;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final bool isAdmin;
  final int usernameChanges;
  final DateTime? usernameChangedAt;
  final DateTime createdAt;

  User({
    required this.id,
    this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl = '',
    this.bio = '',
    this.isAdmin = false,
    this.usernameChanges = 0,
    this.usernameChangedAt,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String?,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
      usernameChanges: json['username_changes'] as int? ?? 0,
      usernameChangedAt: json['username_changed_at'] != null
          ? DateTime.parse(json['username_changed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'bio': bio,
        'is_admin': isAdmin,
        'username_changes': usernameChanges,
        'username_changed_at': usernameChangedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final User user;
  final List<String>? recoveryCodes;

  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
    this.recoveryCodes,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      recoveryCodes: (json['recovery_codes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}
