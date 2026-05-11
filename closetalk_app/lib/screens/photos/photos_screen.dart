import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'photo_viewer_screen.dart';

class PhotosScreen extends StatefulWidget {
  const PhotosScreen({super.key});

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  static const int _pageSize = 60;

  final List<AssetEntity> _assets = [];
  AssetPathEntity? _album;
  int _page = 0;
  bool _loading = true;
  bool _hasMore = true;
  PermissionState? _perm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    setState(() => _perm = perm);

    if (!perm.isAuth && !perm.hasAccess) {
      setState(() => _loading = false);
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _album = albums.first;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_album == null || !_hasMore) return;
    final batch = await _album!.getAssetListPaged(page: _page, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets.addAll(batch);
      _page += 1;
      _hasMore = batch.length == _pageSize;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_perm != null && !_perm!.isAuth && !_perm!.hasAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Photos permission is required to browse your gallery.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _openSettings,
                child: const Text('Open Settings'),
              ),
              TextButton(onPressed: _init, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_assets.isEmpty) {
      return const Center(child: Text('No photos on this device'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _assets.length) {
          _loadMore();
          return const Center(
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final asset = _assets[i];
        return _PhotoTile(
          asset: asset,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PhotoViewerScreen(asset: asset),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _PhotoTile({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder(
        future: asset.thumbnailDataWithSize(
          const ThumbnailSize.square(240),
        ),
        builder: (_, snap) {
          if (!snap.hasData || snap.data == null) {
            return Container(color: Colors.grey[300]);
          }
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }
}
