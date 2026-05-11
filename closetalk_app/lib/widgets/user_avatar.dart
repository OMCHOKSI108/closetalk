import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final bool isOnline;
  final bool hasStory;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 20,
    this.isOnline = false,
    this.hasStory = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: hasStory
                ? Border.all(color: Colors.brown[400]!, width: 2.5)
                : null,
          ),
          child: Padding(
            padding: hasStory ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
            child: CircleAvatar(
              radius: hasStory ? radius - 2.5 : radius,
              backgroundImage: imageUrl != null && imageUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(imageUrl!)
                  : null,
              backgroundColor: Colors.blue[100],
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                        fontSize: radius * 0.8,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: radius * 0.5,
            height: radius * 0.5,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
