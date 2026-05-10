class User {
  final String id;
  final String? email;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final bool isAdmin;
  final DateTime createdAt;

  User({
    required this.id,
    this.email,
    required this.displayName,
    this.avatarUrl = '',
    this.bio = '',
    this.isAdmin = false,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String,
      avatarUrl: json['avatar_url'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'bio': bio,
        'is_admin': isAdmin,
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
