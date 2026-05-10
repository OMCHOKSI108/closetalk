import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(imageUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blue[100],
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.blue[800],
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
