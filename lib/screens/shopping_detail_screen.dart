import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

const String kKamisCertKey = String.fromEnvironment('KAMIS_CERT_KEY');
const String kKamisCertId = String.fromEnvironment('KAMIS_CERT_ID');

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
  String? _itemCode;

  final Map<String, String> _trendOptions = {
    'daily': '최근 40일',
    'monthly': '월평균',
    'yearly': '연평균',
  };

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _fetchItemCode();
    await _fetchPriceHistory();
  }

  Future<void> _fetchItemCode() async {
    final categoryCode = widget.item['category_code']?.toString() ?? '';
    final itemName = widget.item['item_name']?.toString() ?? '';
    if (categoryCode.isEmpty || itemName.isEmpty) return;

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=productInfo'
      '&p_itemcategorycode=$categoryCode'
      '&p_cert_key=$kKamisCertKey'
      '&p_cert_id=$kKamisCertId'
      '&p_returntype=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final list = data['info'];

      if (list == null || list is! List) return;

      final cleanItemName = itemName.split('/').first.trim();
      for (final entry in list) {
        if (entry is! Map) continue;
        final entryName = entry['itemname']?.toString() ?? '';
        if (entryName == cleanItemName) {
          _itemCode = entry['itemcode']?.toString();
          break;
        }
      }

      debugPrint('찾은 itemcode: $_itemCode (item_name: $cleanItemName)');
    } catch (e) {
      debugPrint('코드표 조회 실패: $e');
    }
  }

  Future<void> _fetchPriceHistory() async {
    if (_trendCache.containsKey(_trendMode)) {
      setState(() => _isLoading = false);
      return;
    }

    final productNo = widget.item['productno']?.toString() ?? '';
    if (productNo.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    if (_trendMode == 'daily') {
      await _fetchDaily(productNo);
    } else if (_trendMode == 'monthly') {
      await _fetchMonthly();
    } else {
      await _fetchYearly();
    }
  }

  Future<void> _fetchDaily(String productNo) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=recentlyPriceTrendList'
      '&p_productno=$productNo'
      '&p_regday=$dateStr'
      '&p_cert_key=$kKamisCertKey'
      '&p_cert_id=$kKamisCertId'
      '&p_returntype=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final data = jsonDecode(response.body);
      final priceList = data['price'];

      if (priceList == null || priceList is! List) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _trendCache['daily'] = priceList.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('일별 조회 실패: $e');
    }
  }

  Future<void> _fetchMonthly() async {
    final categoryCode = widget.item['category_code']?.toString() ?? '';
    if (_itemCode == null || categoryCode.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    final currentYear = DateTime.now().year;

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=monthlySalesList'
      '&p_yyyy=$currentYear'
      '&p_period=4'
      '&p_itemcategorycode=$categoryCode'
      '&p_itemcode=$_itemCode'
      '&p_graderank=1'
      '&p_countycode=1101'
      '&p_convert_kg_yn=N'
      '&p_cert_key=$kKamisCertKey'
      '&p_cert_id=$kKamisCertId'
      '&p_returntype=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      debugPrint('월별 응답: ${response.body}');

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final data = jsonDecode(response.body);
      final priceData = data['price'];

      if (priceData == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final priceList = priceData is List ? priceData : [priceData];

      List<Map<String, dynamic>>? items;
      for (final entry in priceList) {
        if (entry is! Map) continue;
        if (entry['productclscode'] == '01') {
          final itemList = entry['item'];
          if (itemList is List) {
            items = itemList.cast<Map<String, dynamic>>();
            break;
          }
        }
      }

      if (items == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        _trendCache['monthly'] = items!;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('월별 조회 실패: $e');
    }
  }

  Future<void> _fetchYearly() async {
    final categoryCode = widget.item['category_code']?.toString() ?? '';
    if (_itemCode == null || categoryCode.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    final currentYear = DateTime.now().year;

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=yearlySalesList'
      '&p_yyyy=$currentYear'
      '&p_itemcategorycode=$categoryCode'
      '&p_itemcode=$_itemCode'
      '&p_graderank=1'
      '&p_countycode=1101'
      '&p_convert_kg_yn=N'
      '&p_cert_key=$kKamisCertKey'
      '&p_cert_id=$kKamisCertId'
      '&p_returntype=json',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      debugPrint('연별 응답: ${response.body}');

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final data = jsonDecode(response.body);
      final priceData = data['price'];

      if (priceData == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final priceList = priceData is List ? priceData : [priceData];

      List<Map<String, dynamic>>? items;
      for (final entry in priceList) {
        if (entry is! Map) continue;
        final itemList = entry['item'];
        if (itemList is List) {
          items = itemList.cast<Map<String, dynamic>>();
          break;
        }
      }

      if (items == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      // 평년 빼고 연도순 정렬
      final filtered = items.where((data) {
        final div = data['div']?.toString() ?? '';
        return div != '평년';
      }).toList();

      filtered.sort((a, b) {
        final yearA = int.tryParse(a['div']?.toString() ?? '') ?? 0;
        final yearB = int.tryParse(b['div']?.toString() ?? '') ?? 0;
        return yearA.compareTo(yearB);
      });

      if (!mounted) return;
      setState(() {
        _trendCache['yearly'] = filtered;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('연별 조회 실패: $e');
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
    return _trendList
        .map((data) {
          final year = data['yyyy']?.toString() ?? '';
          final spots = _getDailySpots(data);
          return LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _getDailyLineColor(year),
            barWidth: 3,
            dotData: const FlDotData(show: true),
          );
        })
        .where((bar) => bar.spots.isNotEmpty)
        .toList();
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

    final adjustedMin = ((minPrice - padding) / step).floor() * step;
    final adjustedMax = ((maxPrice + padding) / step).ceil() * step;

    return (adjustedMin.toDouble(), adjustedMax.toDouble(), step);
  }

  Widget _buildLegend() {
    if (_trendMode == 'daily') {
      return Wrap(
        spacing: 16,
        children: _trendList.map((data) {
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
    if (_trendMode == 'daily') {
      return _trendList[spot.barIndex]['yyyy']?.toString() ?? '';
    } else if (_trendMode == 'monthly') {
      if (spot.barIndex >= _trendList.length) return '';
      return '${_trendList[spot.barIndex]['yyyy']}년';
    } else {
      return '평균';
    }
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
            _buildLegend(),
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
