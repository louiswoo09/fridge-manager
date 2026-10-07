import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import '../config/api_config.dart';

class ShoppingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final String displayName;

  const ShoppingDetailScreen({
    super.key,
    required this.item,
    required this.displayName,
  });

  @override
  State<ShoppingDetailScreen> createState() => _ShoppingDetailScreenState();
}

class _ShoppingDetailScreenState extends State<ShoppingDetailScreen> {
  bool _isLoading = true;
  String _trendMode = 'daily';
  final Map<String, List<Map<String, dynamic>>> _trendCache = {};

  final List<String> _barLabels = [];

  final Map<String, String> _trendOptions = {
    'daily': '최근 40일',
    'monthly': '월평균',
    'yearly': '연평균',
  };

  @override
  void initState() {
    super.initState();
    _fetchPriceHistory();
  }

  Future<void> _fetchPriceHistory() async {
    if (_trendCache.containsKey(_trendMode)) {
      setState(() => _isLoading = false);
      return;
    }

    final mode = _trendMode; // 요청 중에 모드가 바뀌어도 꼬이지 않게 고정
    setState(() => _isLoading = true);

    final refPrice = double.tryParse(
      widget.item['dpr1']?.toString().replaceAll(',', '') ?? '',
    );

    final url = Uri.parse('$kApiBaseUrl/kamis/trend').replace(
      queryParameters: {
        'mode': mode,
        'product_no': widget.item['productno']?.toString() ?? '',
        'category_code': widget.item['category_code']?.toString() ?? '',
        'item_name': widget.item['item_name']?.toString() ?? '',
        if (refPrice != null && refPrice > 0) 'ref_price': refPrice.toString(),
      },
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('서버 응답 오류: ${response.statusCode}');
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final items = ((data['items'] as List?) ?? [])
          .cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _trendCache[mode] = items;
        if (_trendMode == mode) _isLoading = false;
      });
    } catch (e) {
      debugPrint('가격 추이 조회 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _trendList => _trendCache[_trendMode] ?? [];

  String _formatNumber(num value) {
    return value.toInt().toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  Color _getYearColor(int year) {
    final currentYear = DateTime.now().year;
    if (year == currentYear) return Colors.deepPurple;
    if (year == currentYear - 1) return Colors.blue.withValues(alpha: 0.6);
    if (year == currentYear - 2) return Colors.green.withValues(alpha: 0.5);
    if (year == currentYear - 3) return Colors.orange.withValues(alpha: 0.4);
    return Colors.grey.withValues(alpha: 0.3);
  }

  Color _getDailyLineColor(String label) {
    if (label == '평년') return Colors.grey;
    final currentYear = DateTime.now().year.toString();
    if (label == currentYear) return Colors.deepPurple;
    return Colors.blue;
  }

  List<FlSpot> _getDailySpots(Map<String, dynamic> data) {
    final spots = <FlSpot>[];
    const keys = ['d40', 'd30', 'd20', 'd10', 'd0'];

    for (int i = 0; i < keys.length; i++) {
      final value = data[keys[i]];
      if (value == null || value is List) continue;
      final priceStr = value.toString().replaceAll(',', '');
      final price = double.tryParse(priceStr);
      if (price != null && price > 0) {
        spots.add(FlSpot(i.toDouble(), price));
      }
    }

    final year = data['yyyy']?.toString() ?? '';
    final currentYear = DateTime.now().year.toString();
    if (year == currentYear && spots.isNotEmpty && spots.last.x < 4) {
      final dpr1Str = widget.item['dpr1']?.toString().replaceAll(',', '');
      final dpr1 = double.tryParse(dpr1Str ?? '');
      if (dpr1 != null && dpr1 > 0) {
        spots.add(FlSpot(4, dpr1));
      }
    }

    return spots;
  }

  List<LineChartBarData> _buildDailyBars() {
    final bars = <LineChartBarData>[];
    for (final data in _trendList) {
      final spots = _getDailySpots(data);
      if (spots.isEmpty) continue;
      final year = data['yyyy']?.toString() ?? '';
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _getDailyLineColor(year),
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      );
      _barLabels.add(year);
    }
    return bars;
  }

  List<LineChartBarData> _buildMonthlyBars() {
    final bars = <LineChartBarData>[];

    for (final data in _trendList) {
      final year = int.tryParse(data['yyyy']?.toString() ?? '');
      if (year == null) continue;

      final spots = <FlSpot>[];
      for (int month = 1; month <= 12; month++) {
        final value = data['m$month']?.toString().replaceAll(',', '');
        if (value == null || value == '-' || value.isEmpty) continue;
        final price = double.tryParse(value);
        if (price != null && price > 0) {
          spots.add(FlSpot(month.toDouble(), price));
        }
      }

      if (spots.isEmpty) continue;

      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: _getYearColor(year),
          barWidth: 3,
          dotData: const FlDotData(show: true),
        ),
      );
      _barLabels.add('$year년');
    }

    return bars;
  }

  List<LineChartBarData> _buildYearlyBars() {
    final spots = <FlSpot>[];

    for (int i = 0; i < _trendList.length; i++) {
      final avgStr = _trendList[i]['avg_data']?.toString().replaceAll(',', '');
      final avg = double.tryParse(avgStr ?? '');
      if (avg != null && avg > 0) {
        spots.add(FlSpot(i.toDouble(), avg));
      }
    }

    if (spots.isEmpty) return [];

    _barLabels.add('평균');

    return [
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: Colors.deepPurple,
        barWidth: 3,
        dotData: const FlDotData(show: true),
      ),
    ];
  }

  List<LineChartBarData> _buildBars() {
    _barLabels.clear(); // 그릴 때마다 새로 기록
    if (_trendMode == 'daily') return _buildDailyBars();
    if (_trendMode == 'monthly') return _buildMonthlyBars();
    return _buildYearlyBars();
  }

  String _getXLabel(int index) {
    if (_trendMode == 'daily') {
      final daysAgo = (4 - index) * 10;
      final date = DateTime.now().subtract(Duration(days: daysAgo));
      return '${date.month}/${date.day}';
    } else if (_trendMode == 'monthly') {
      if (index < 1 || index > 12) return '';
      return '$index월';
    } else {
      if (index >= _trendList.length) return '';
      return _trendList[index]['div']?.toString() ?? '';
    }
  }

  (double minX, double maxX, double xInterval) _getXRange() {
    if (_trendMode == 'daily') return (0, 4, 1);
    if (_trendMode == 'monthly') return (1, 12, 1);
    final maxX = (_trendList.length - 1).toDouble().clamp(0, double.infinity);
    return (0, maxX.toDouble(), 1);
  }

  (double minY, double maxY, double interval) _getYRange(
    List<LineChartBarData> bars,
  ) {
    double minPrice = double.infinity;
    double maxPrice = 0;

    for (final bar in bars) {
      for (final spot in bar.spots) {
        if (spot.y < minPrice) minPrice = spot.y;
        if (spot.y > maxPrice) maxPrice = spot.y;
      }
    }

    if (minPrice == double.infinity) return (0, 100, 20);

    final range = maxPrice - minPrice;
    final padding = range * 0.1;

    double step;
    if (maxPrice < 1000) {
      step = 100;
    } else if (maxPrice < 2500) {
      step = 200;
    } else if (maxPrice < 5000) {
      step = 500;
    } else if (maxPrice < 10000) {
      step = 1000;
    } else if (maxPrice < 25000) {
      step = 2000;
    } else if (maxPrice < 50000) {
      step = 5000;
    } else if (maxPrice < 100000) {
      step = 10000;
    } else if (maxPrice < 250000) {
      step = 20000;
    } else if (maxPrice < 500000) {
      step = 50000;
    } else if (maxPrice < 1000000) {
      step = 100000;
    } else {
      step = 200000;
    }

    final rawMin = ((minPrice - padding) / step).floor() * step;
    final adjustedMin = rawMin < 0 ? 0.0 : rawMin.toDouble();
    final adjustedMax = ((maxPrice + padding) / step).ceil() * step;

    return (adjustedMin, adjustedMax.toDouble(), step);
  }

  Widget _buildLegend() {
    if (_trendMode == 'daily') {
      final validList = _trendList.where((data) {
        const keys = ['d40', 'd30', 'd20', 'd10', 'd0'];
        for (final key in keys) {
          final value = data[key];
          if (value == null || value is List) continue;
          final priceStr = value.toString().replaceAll(',', '');
          final price = double.tryParse(priceStr);
          if (price != null && price > 0) return true;
        }
        return false;
      }).toList();

      return Wrap(
        spacing: 16,
        children: validList.map((data) {
          final year = data['yyyy']?.toString() ?? '';
          return _legendItem(_getDailyLineColor(year), year);
        }).toList(),
      );
    } else if (_trendMode == 'monthly') {
      final years =
          _trendList
              .map((data) => int.tryParse(data['yyyy']?.toString() ?? ''))
              .whereType<int>()
              .toList()
            ..sort((a, b) => b.compareTo(a));
      return Wrap(
        spacing: 16,
        children: years
            .map((y) => _legendItem(_getYearColor(y), '$y년'))
            .toList(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  String _getTooltipLabel(LineBarSpot spot) {
    if (spot.barIndex < 0 || spot.barIndex >= _barLabels.length) return '';
    return _barLabels[spot.barIndex];
  }

  Widget _priceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _priceRowWithDiff(String label, String value, String currentValue) {
    final current = double.tryParse(currentValue.replaceAll(',', ''));
    final base = double.tryParse(value.replaceAll(',', ''));
    String diffText = '';
    Color diffColor = Colors.grey;

    if (current != null && base != null && base > 0) {
      final diff = ((current - base) / base) * 100;
      diffText = diff > 0
          ? '+${diff.toStringAsFixed(1)}%'
          : '${diff.toStringAsFixed(1)}%';
      diffColor = diff > 0
          ? Colors.blue
          : (diff < 0 ? Colors.red : Colors.grey);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Row(
            children: [
              Text(
                '$value원',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (diffText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  diffText,
                  style: TextStyle(
                    color: diffColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineBars = _buildBars();
    final (minY, maxY, yInterval) = _getYRange(lineBars);
    final (minX, maxX, xInterval) = _getXRange();

    final dpr1 = widget.item['dpr1']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(title: Text(widget.displayName)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.item['unit']} 단위',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const Divider(height: 24),
                    _priceRow('현재 가격', '${widget.item['dpr1']}원'),
                    _priceRowWithDiff(
                      '1일전',
                      widget.item['dpr2']?.toString() ?? '',
                      dpr1,
                    ),
                    _priceRowWithDiff(
                      '1개월전',
                      widget.item['dpr3']?.toString() ?? '',
                      dpr1,
                    ),
                    _priceRowWithDiff(
                      '1년전',
                      widget.item['dpr4']?.toString() ?? '',
                      dpr1,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '가격 추이',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: _trendMode,
                  items: _trendOptions.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _trendMode = value);
                    _fetchPriceHistory();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_isLoading && _trendList.isNotEmpty) _buildLegend(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (lineBars.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('가격 추이 정보가 없습니다'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  height: 300,
                  child: LineChart(
                    LineChartData(
                      minY: minY,
                      maxY: maxY,
                      minX: minX,
                      maxX: maxX,
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 70,
                            interval: yInterval,
                            getTitlesWidget: (value, meta) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Text(
                                  _formatNumber(value),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: xInterval,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (value != i.toDouble()) {
                                return const SizedBox.shrink();
                              }
                              final label = _getXLabel(i);
                              if (label.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  label,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                      lineBarsData: lineBars,
                      lineTouchData: LineTouchData(
                        getTouchedSpotIndicator:
                            (LineChartBarData barData, List<int> spotIndexes) {
                              return spotIndexes.map((index) {
                                return TouchedSpotIndicatorData(
                                  const FlLine(color: Colors.transparent),
                                  FlDotData(
                                    getDotPainter:
                                        (spot, percent, barData, index) =>
                                            FlDotCirclePainter(
                                              radius: 5,
                                              color:
                                                  barData.color ??
                                                  Colors.deepPurple,
                                              strokeWidth: 2,
                                              strokeColor: Colors.white,
                                            ),
                                  ),
                                );
                              }).toList();
                            },
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => Colors.black87,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final label = _getTooltipLabel(spot);
                              return LineTooltipItem(
                                '$label ${_formatNumber(spot.y)}원',
                                const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
