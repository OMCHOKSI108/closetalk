class Device {
  final String id;
  final String deviceName;
  final String deviceType;
  final String platform;
  final bool isActive;
  final DateTime linkedAt;
  final DateTime lastActive;

  Device({
    required this.id,
    required this.deviceName,
    required this.deviceType,
    required this.platform,
    required this.isActive,
    required this.linkedAt,
    required this.lastActive,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      deviceName: json['device_name'] as String,
      deviceType: json['device_type'] as String,
      platform: json['platform'] as String,
      isActive: json['is_active'] as bool? ?? true,
      linkedAt: DateTime.parse(json['linked_at'] as String),
      lastActive: DateTime.parse(json['last_active'] as String),
    );
  }
}

class LinkDeviceResponse {
  final String deviceToken;
  final String deviceId;

  LinkDeviceResponse({
    required this.deviceToken,
    required this.deviceId,
  });

  factory LinkDeviceResponse.fromJson(Map<String, dynamic> json) {
    return LinkDeviceResponse(
      deviceToken: json['device_token'] as String,
      deviceId: json['device_id'] as String,
    );
  }
}
