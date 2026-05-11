import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerSheet extends StatefulWidget {
  final void Function(double lat, double lng) onSelected;

  const LocationPickerSheet({super.key, required this.onSelected});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  bool _loading = false;
  Position? _position;
  String? _error;
  bool _serviceDisabled = false;
  bool _permissionDeniedForever = false;

  Future<void> _getLocation() async {
    setState(() {
      _loading = true;
      _error = null;
      _serviceDisabled = false;
      _permissionDeniedForever = false;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _serviceDisabled = true;
          _error = 'Location services are turned off.';
          _loading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            _error = 'Location permission is needed to share your current place.';
            _loading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _permissionDeniedForever = true;
          _error = 'Location permission is blocked. Enable it from app settings.';
          _loading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) setState(() => _position = pos);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not fetch location. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (!_loading && _error == null && _position == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location,
                          size: 56, color: Colors.blue),
                      const SizedBox(height: 12),
                      const Text(
                        'CloseTalk needs location permission only when you share your live place in chat.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _getLocation,
                        icon: const Icon(Icons.location_searching),
                        label: const Text('Allow Location'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      if (_serviceDisabled)
                        TextButton(
                          onPressed: Geolocator.openLocationSettings,
                          child: const Text('Open Location Settings'),
                        )
                      else if (_permissionDeniedForever)
                        TextButton(
                          onPressed: Geolocator.openAppSettings,
                          child: const Text('Open App Settings'),
                        )
                      else
                        TextButton(
                          onPressed: _getLocation,
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ),
            if (_position != null)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, size: 64, color: Colors.red),
                    const SizedBox(height: 8),
                    Text(
                      '${_position!.latitude.toStringAsFixed(4)}, ${_position!.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => widget.onSelected(
                        _position!.latitude,
                        _position!.longitude,
                      ),
                      icon: const Icon(Icons.send),
                      label: const Text('Send Location'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
