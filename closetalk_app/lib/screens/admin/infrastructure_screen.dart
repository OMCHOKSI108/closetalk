import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/infrastructure_provider.dart';

class InfrastructureScreen extends StatefulWidget {
  const InfrastructureScreen({super.key});

  @override
  State<InfrastructureScreen> createState() => _InfrastructureScreenState();
}

class _InfrastructureScreenState extends State<InfrastructureScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
  }

  void _loadAll() {
    final p = context.read<InfrastructureProvider>();
    p.loadStatus();
    p.loadMetrics();
    p.loadCosts();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'running':
        return Colors.green;
      case 'stopped':
      case 'inactive':
        return Colors.red;
      case 'degraded':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'ecs':
        return Icons.computer;
      case 'rds':
        return Icons.storage;
      case 's3':
        return Icons.cloud;
      case 'cloudfront':
        return Icons.public;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<InfrastructureProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS Infrastructure'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _loadAll(),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildOverallStatus(p),
            const SizedBox(height: 12),
            _buildResourcesGrid(p),
            const SizedBox(height: 12),
            _buildActionButtons(p),
            if (p.actionMessage != null) ...[
              const SizedBox(height: 8),
              _buildActionCard(p.actionMessage!),
            ],
            const SizedBox(height: 12),
            _buildSection('ECS Utilization', p.ecsMetrics, p.metricsLoading, '%'),
            const SizedBox(height: 12),
            _buildSection('RDS Metrics', p.rdsMetrics, p.metricsLoading, null),
            const SizedBox(height: 12),
            _buildSection('ALB Metrics', p.albMetrics, p.metricsLoading, null),
            const SizedBox(height: 12),
            _buildCostsSection(p),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallStatus(InfrastructureProvider p) {
    final color = p.overall == 'healthy'
        ? Colors.green
        : p.overall == 'stopped'
            ? Colors.red
            : Colors.orange;
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.circle, color: color, size: 16),
            const SizedBox(width: 8),
            Text('Overall: ${p.overall.toUpperCase()}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16)),
            const Spacer(),
            if (p.statusLoading)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesGrid(InfrastructureProvider p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Resources', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...p.resources.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(_typeIcon(r.type), size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name, style: const TextStyle(fontSize: 13)),
                            if (r.detail.isNotEmpty)
                              Text(r.detail,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(r.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(r.status,
                            style: TextStyle(
                                fontSize: 11,
                                color: _statusColor(r.status),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(InfrastructureProvider p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('START'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: p.actionLoading
                    ? null
                    : () => _onStart(p),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('STOP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: p.actionLoading
                    ? null
                    : () => _onStop(p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onStart(InfrastructureProvider p) async {
    final msg = await p.requestStartInit();
    if (!mounted) return;
    if (msg.contains('OTP sent') || msg.contains('otp')) {
      _showOtpDialog(p, 'Start', (email, otp) => p.confirmStart(email, otp));
    } else {
      _showResult(msg);
    }
  }

  void _onStop(InfrastructureProvider p) async {
    final msg = await p.requestStopInit();
    if (!mounted) return;
    if (msg.contains('OTP sent') || msg.contains('otp')) {
      _showOtpDialog(p, 'Stop', (email, otp) => p.confirmStop(email, otp));
    } else {
      _showResult(msg);
    }
  }

  void _showOtpDialog(
      InfrastructureProvider p, String action, Future<String> Function(String, String) confirm) {
    final emailCtl = TextEditingController();
    final otpCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm $action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtl,
              decoration: const InputDecoration(
                  labelText: 'Admin Email', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: otpCtl,
              decoration: const InputDecoration(
                  labelText: 'OTP Code', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await confirm(emailCtl.text.trim(), otpCtl.text.trim());
              if (mounted) {
                _showResult(result);
                p.loadStatus();
              }
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }

  void _showResult(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Result'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _buildActionCard(String message) {
    return Card(
      color: Colors.blueGrey[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<dynamic> series, bool loading, String? unitLabel) {
    if (loading && series.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(title, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }
    if (series.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('$title: No data available',
              style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: _buildMetricChart(series, unitLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChart(List<dynamic> seriesList, String? unitLabel) {
    final series = seriesList as List;
    if (series.isEmpty) return const Center(child: Text('No data'));
    final allPoints = <FlSpot>[];
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red];
    int maxX = 1;

    for (final s in series) {
      final ms = s as dynamic;
      for (final pt in ms.points) {
        final x = (pt.timestamp / 1000).toInt();
        final y = pt.value.toDouble();
        allPoints.add(FlSpot(x.toDouble(), y));
        if (x > maxX) maxX = x;
      }
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                unitLabel != null && unitLabel == '%'
                    ? '${value.toInt()}%'
                    : _formatMetricValue(value),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: max(1, (maxX - (maxX - 3600)) / 4).toDouble(),
              getTitlesWidget: (value, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
                return Text('${dt.hour}:${dt.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 9));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: (maxX - 3600).toDouble(),
        maxX: maxX.toDouble(),
        lineBarsData: series.asMap().entries.map((entry) {
          final s = entry.value as dynamic;
          final color = colors[entry.key % colors.length];
          return LineChartBarData(
            spots: (s.points as List).map((pt) {
              final x = ((pt.timestamp as int) / 1000).toInt();
              final y = (pt.value as num).toDouble();
              return FlSpot(x.toDouble(), y);
            }).toList(),
            isCurved: true,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
          );
        }).toList(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
              final idx = touchedSpots.indexOf(spot);
              final s = series[idx] as dynamic;
              return LineTooltipItem(
                '${s.name}: ${spot.y.toStringAsFixed(1)}${unitLabel ?? ""}',
                TextStyle(color: colors[idx % colors.length], fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _formatMetricValue(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  Widget _buildCostsSection(InfrastructureProvider p) {
    if (p.costsLoading && p.dailyCosts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Loading costs...'),
              ],
            ),
          ),
        ),
      );
    }
    if (p.dailyCosts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Cost data not available',
              style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('AWS Costs',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text('\$${p.totalCost.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green)),
              ],
            ),
            const SizedBox(height: 4),
            Text('This month (MTD)',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: _buildCostChart(p.dailyCosts),
            ),
            if (p.costByService.isNotEmpty) ...[
              const Divider(),
              const Text('By Service',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              ...p.costByService.take(6).map((cs) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(cs.service,
                                style: const TextStyle(fontSize: 12))),
                        Text('\$${cs.blended.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCostChart(List<CostPoint> points) {
    if (points.isEmpty) return const Center(child: Text('No cost data'));
    final maxBlended = points.map((p) => p.blended).reduce(max);
    final barColors = [
      Colors.blue,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.lightBlue,
      Colors.blueGrey,
    ];
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxBlended * 1.15,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${points[groupIndex].date}\n\$${rod.toY.toStringAsFixed(2)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                '\$${value.toInt()}',
                style: const TextStyle(fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox();
                final parts = points[idx].date.split('-');
                return Text('${parts[2]}/${parts[1]}',
                    style: const TextStyle(fontSize: 8));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxBlended > 0 ? maxBlended / 4 : 1,
        ),
        barGroups: points.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.blended,
                color: barColors[entry.key % barColors.length],
                width: 14,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4), topRight: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
