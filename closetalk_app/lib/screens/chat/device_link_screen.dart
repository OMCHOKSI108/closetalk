import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/auth_service.dart';

class DeviceLinkScreen extends StatefulWidget {
  final AuthService authService;

  const DeviceLinkScreen({super.key, required this.authService});

  @override
  State<DeviceLinkScreen> createState() => _DeviceLinkScreenState();
}

class _DeviceLinkScreenState extends State<DeviceLinkScreen> {
  final _deviceNameController = TextEditingController();
  final _deviceTypeController = TextEditingController();
  final _platformController = TextEditingController();
  bool _isLoading = false;
  LinkDeviceResponse? _response;

  @override
  void dispose() {
    _deviceNameController.dispose();
    _deviceTypeController.dispose();
    _platformController.dispose();
    super.dispose();
  }

  Future<void> _linkDevice() async {
    if (_deviceNameController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final resp = await widget.authService.linkDevice(
        deviceName: _deviceNameController.text.trim(),
        deviceType: _deviceTypeController.text.trim().isEmpty
            ? 'desktop'
            : _deviceTypeController.text.trim(),
        platform: _platformController.text.trim().isEmpty
            ? 'web'
            : _platformController.text.trim(),
      );
      setState(() => _response = resp);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to link device: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link New Device')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.qr_code_scanner, size: 80),
            const SizedBox(height: 16),
            const Text(
              'Link a new device to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(
                labelText: 'Device name',
                hintText: "e.g. Alice's MacBook Pro",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceTypeController,
              decoration: const InputDecoration(
                labelText: 'Device type (optional)',
                hintText: 'phone, tablet, desktop, web',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _platformController,
              decoration: const InputDecoration(
                labelText: 'Platform (optional)',
                hintText: 'android, ios, windows, macos, linux, web',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _linkDevice,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Link Device'),
            ),
            if (_response != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Device linked successfully!',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Device ID: ${_response!.deviceId}'),
                      Text('Token: ${_response!.deviceToken}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
