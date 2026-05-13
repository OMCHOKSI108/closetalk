import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class ResourceStatus {
  final String name;
  final String type;
  final String status;
  final String detail;

  ResourceStatus({
    required this.name,
    required this.type,
    required this.status,
    this.detail = '',
  });

  factory ResourceStatus.fromJson(Map<String, dynamic> json) {
    return ResourceStatus(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );
  }
}

class MetricPoint {
  final int timestamp;
  final double value;

  MetricPoint({required this.timestamp, required this.value});

  factory MetricPoint.fromJson(Map<String, dynamic> json) {
    return MetricPoint(
      timestamp: json['t'] as int? ?? 0,
      value: (json['v'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class MetricSeries {
  final String name;
  final String unit;
  final List<MetricPoint> points;

  MetricSeries({required this.name, this.unit = '', required this.points});

  factory MetricSeries.fromJson(Map<String, dynamic> json) {
    return MetricSeries(
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      points: (json['points'] as List<dynamic>?)
              ?.map((e) => MetricPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class CostPoint {
  final String date;
  final double blended;

  CostPoint({required this.date, required this.blended});

  factory CostPoint.fromJson(Map<String, dynamic> json) {
    return CostPoint(
      date: json['date'] as String? ?? '',
      blended: (json['blended'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class CostService {
  final String service;
  final double blended;

  CostService({required this.service, required this.blended});

  factory CostService.fromJson(Map<String, dynamic> json) {
    return CostService(
      service: json['service'] as String? ?? '',
      blended: (json['blended'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class InfrastructureProvider extends ChangeNotifier {
  List<ResourceStatus> _resources = [];
  String _overall = '';
  bool _statusLoading = false;

  List<MetricSeries> _ecsMetrics = [];
  List<MetricSeries> _rdsMetrics = [];
  List<MetricSeries> _albMetrics = [];
  bool _metricsLoading = false;

  List<CostPoint> _dailyCosts = [];
  List<CostService> _costByService = [];
  double _totalCost = 0;
  bool _costsLoading = false;

  String? _actionMessage;
  bool _actionLoading = false;

  List<ResourceStatus> get resources => _resources;
  String get overall => _overall;
  bool get statusLoading => _statusLoading;

  List<MetricSeries> get ecsMetrics => _ecsMetrics;
  List<MetricSeries> get rdsMetrics => _rdsMetrics;
  List<MetricSeries> get albMetrics => _albMetrics;
  bool get metricsLoading => _metricsLoading;

  List<CostPoint> get dailyCosts => _dailyCosts;
  List<CostService> get costByService => _costByService;
  double get totalCost => _totalCost;
  bool get costsLoading => _costsLoading;

  String? get actionMessage => _actionMessage;
  bool get actionLoading => _actionLoading;

  Future<void> loadStatus() async {
    _statusLoading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure'),
        headers: ApiConfig.headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _resources = (data['resources'] as List<dynamic>)
            .map((e) => ResourceStatus.fromJson(e as Map<String, dynamic>))
            .toList();
        _overall = data['overall'] as String? ?? '';
      }
    } catch (_) {}
    _statusLoading = false;
    notifyListeners();
  }

  Future<void> loadMetrics() async {
    _metricsLoading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/metrics'),
        headers: ApiConfig.headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _ecsMetrics = (data['ecs'] as List<dynamic>?)
                ?.map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _rdsMetrics = (data['rds'] as List<dynamic>?)
                ?.map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _albMetrics = (data['alb'] as List<dynamic>?)
                ?.map((e) => MetricSeries.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
      }
    } catch (_) {}
    _metricsLoading = false;
    notifyListeners();
  }

  Future<void> loadCosts() async {
    _costsLoading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/costs'),
        headers: ApiConfig.headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _dailyCosts = (data['daily'] as List<dynamic>?)
                ?.map((e) => CostPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _costByService = (data['by_service'] as List<dynamic>?)
                ?.map((e) => CostService.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _totalCost = (data['total'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}
    _costsLoading = false;
    notifyListeners();
  }

  Future<String> requestStopInit() async {
    _actionMessage = null;
    _actionLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/stop'),
        headers: ApiConfig.headers,
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = data['message'] as String? ?? 'Failed';
      _actionMessage = msg;
      return msg;
    } catch (e) {
      _actionMessage = 'Network error: $e';
      return _actionMessage!;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<String> confirmStop(String email, String otp) async {
    _actionMessage = null;
    _actionLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/stop/confirm'),
        headers: {...ApiConfig.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = data['message'] as String? ?? 'Failed';
      _actionMessage = msg;
      return msg;
    } catch (e) {
      _actionMessage = 'Network error: $e';
      return _actionMessage!;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<String> requestStartInit() async {
    _actionMessage = null;
    _actionLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/start'),
        headers: ApiConfig.headers,
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = data['message'] as String? ?? 'Failed';
      _actionMessage = msg;
      return msg;
    } catch (e) {
      _actionMessage = 'Network error: $e';
      return _actionMessage!;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  Future<String> confirmStart(String email, String otp) async {
    _actionMessage = null;
    _actionLoading = true;
    notifyListeners();
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/infrastructure/start/confirm'),
        headers: {...ApiConfig.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = data['message'] as String? ?? 'Failed';
      _actionMessage = msg;
      return msg;
    } catch (e) {
      _actionMessage = 'Network error: $e';
      return _actionMessage!;
    } finally {
      _actionLoading = false;
      notifyListeners();
    }
  }

  void clearActionMessage() {
    _actionMessage = null;
    notifyListeners();
  }
}
