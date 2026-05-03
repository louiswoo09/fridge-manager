import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'shopping_detail_screen.dart';

const String kKamisCertKey = String.fromEnvironment('KAMIS_CERT_KEY');
const String kKamisCertId = String.fromEnvironment('KAMIS_CERT_ID');

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  String _sortMode = 'discount';
  String _comparisonBase = 'dpr3';
  List<Map<String, dynamic>> _allItems = [];

  final TextEditingController _searchController = TextEditingController();

  final List<Map<String, String>> _categories = [
    {'code': 'all', 'name': '전체'},
    {'code': '100', 'name': '식량작물'},
    {'code': '200', 'name': '채소류'},
    {'code': '300', 'name': '특용작물'},
    {'code': '400', 'name': '과일류'},
    {'code': '500', 'name': '축산물'},
    {'code': '600', 'name': '수산물'},
  ];

  final Map<String, String> _comparisonOptions = {
    'dpr2': '1일전',
    'dpr3': '1개월전',
    'dpr4': '1년전',
  };

  final Map<String, String> _sortOptions = {
    'discount': '할인율 큰 순',
    'price': '가격 저렴한 순',
    'name': '가나다순',
  };

  final Map<String, String> _nameOverride = {
    '풋고추/풋고추(녹광 등)': '풋고추',
    '고구마/밤': '밤고구마',
  };

  final List<String> _stripPrefix = ['풋고추'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetchData() async {
    if (kKamisCertKey.isEmpty || kKamisCertId.isEmpty) {
      _showSnack('KAMIS API 키가 설정되지 않았습니다');
      return;
    }

    setState(() {
      _isLoading = true;
      _allItems = [];
    });

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=dailySalesList'
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
      final priceData = data['price'];

      if (priceData == null || priceData is! List) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final filtered = priceData
          .cast<Map<String, dynamic>>()
          .where((item) {
            final clsCode = item['product_cls_code']?.toString() ?? '';
            return clsCode == '01';
          })
          .where((item) {
            final dpr1 = item['dpr1']?.toString().replaceAll(',', '');
            return dpr1 != null && dpr1 != '-' && dpr1.isNotEmpty;
          })
          .toList();

      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final item in filtered) {
        final displayName = _getDisplayName(item);
        if (!seen.contains(displayName)) {
          seen.add(displayName);
          unique.add(item);
        }
      }

      if (!mounted) return;
      setState(() {
        _allItems = unique;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('KAMIS API 오류: $e');
    }
  }

  double _calcDiscount(Map<String, dynamic> item) {
    final current = double.tryParse(
      item['dpr1'].toString().replaceAll(',', ''),
    );
    final base = double.tryParse(
      item[_comparisonBase].toString().replaceAll(',', ''),
    );
    if (current == null || base == null || base == 0) return 0;
    return ((base - current) / base) * 100;
  }

  List<Map<String, dynamic>> _getSortedItems(String categoryCode) {
    List<Map<String, dynamic>> items;

    if (categoryCode == 'all') {
      items = List<Map<String, dynamic>>.from(_allItems);
    } else {
      items = _allItems
          .where((item) => item['category_code']?.toString() == categoryCode)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      items = items.where((item) {
        final displayName = _getDisplayName(item).toLowerCase();
        return displayName.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    items = items.where((item) {
      final base = item[_comparisonBase]?.toString().replaceAll(',', '');
      return base != null && base != '-' && base.isNotEmpty;
    }).toList();

    if (_sortMode == 'discount') {
      items.sort((a, b) => _calcDiscount(b).compareTo(_calcDiscount(a)));
    } else if (_sortMode == 'price') {
      items.sort((a, b) {
        final priceA = double.tryParse(
          a['dpr1'].toString().replaceAll(',', ''),
        );
        final priceB = double.tryParse(
          b['dpr1'].toString().replaceAll(',', ''),
        );
        return (priceA ?? 0).compareTo(priceB ?? 0);
      });
    } else {
      items.sort((a, b) {
        final nameA = a['item_name']?.toString() ?? '';
        final nameB = b['item_name']?.toString() ?? '';
        return nameA.compareTo(nameB);
      });
    }

    return items;
  }

  String _getDisplayName(Map<String, dynamic> item) {
    final productNameRaw = item['productName']?.toString() ?? '';
    final categoryCode = item['category_code']?.toString() ?? '';
    // 매핑 테이블 우선
    if (_nameOverride.containsKey(productNameRaw)) {
      return _nameOverride[productNameRaw]!;
    }
    if (productNameRaw.isEmpty) {
      return item['item_name']?.toString() ?? '';
    }

    final parts = productNameRaw.split('/');
    if (parts.length == 2) {
      final front = parts[0].trim();
      final back = parts[1].trim();
      // 앞 단어 제거 대상이면 뒤만
      if (_stripPrefix.contains(front)) return back;
      // 뒤에 앞이 포함되면 뒤만 콩/흰 콩(국산) → 흰 콩(국산)
      if (back.contains(front)) return back;
      // 축산물(500)은 슬래시를 공백으로
      if (categoryCode == '500') {
        return '$front $back';
      }
      // 백색(국산) → 백색)(국산 으로 변환해서 참깨(백색)(국산) 형태로
      if (back.contains('(')) {
        final cleaned = back.replaceFirst('(', ')(');
        return '$front($cleaned';
      }
      // 그 외는 슬래시를 괄호로 감싸기 (참깨/백색(국산) → 참깨(백색(국산))
      return '$front($back)';
    }
    return productNameRaw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('장보기'),
        bottom: _isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(110),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '재료명 검색',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: const Color.fromARGB(15, 158, 158, 158),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabs: _categories
                          .map((c) => Tab(text: c['name']))
                          .toList(),
                    ),
                  ],
                ),
              )
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: _categories.map((c) => Tab(text: c['name'])).toList(),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '검색 닫기' : '검색',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.compare_arrows),
            tooltip: '비교 기준',
            onSelected: (value) => setState(() => _comparisonBase = value),
            itemBuilder: (_) => _comparisonOptions.entries
                .map(
                  (e) => CheckedPopupMenuItem(
                    value: e.key,
                    checked: _comparisonBase == e.key,
                    child: Text('${e.value} 비교'),
                  ),
                )
                .toList(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '정렬',
            onSelected: (value) => setState(() => _sortMode = value),
            itemBuilder: (_) => _sortOptions.entries
                .map(
                  (e) => CheckedPopupMenuItem(
                    value: e.key,
                    checked: _sortMode == e.key,
                    child: Text(e.value),
                  ),
                )
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _isLoading ? null : _fetchData,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.grey[200],
            child: Text(
              '${_comparisonOptions[_comparisonBase]} 대비 가격 변동',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: _categories.map((category) {
                      final items = _getSortedItems(category['code']!);
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? '검색 결과가 없어요.'
                                : '가격 정보가 없습니다',
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final discount = _calcDiscount(item);
                          final discountColor = discount > 0
                              ? Colors.red
                              : discount < 0
                              ? Colors.blue
                              : Colors.grey;

                          final displayName = _getDisplayName(item);
                          final basePrice = item[_comparisonBase];

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              title: Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '현재: ${item['dpr1']}원 / ${item['unit']}',
                                  ),
                                  Text(
                                    '${_comparisonOptions[_comparisonBase]}: $basePrice원',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                discount > 0
                                    ? '-${discount.toStringAsFixed(1)}%'
                                    : '+${discount.abs().toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: discountColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ShoppingDetailScreen(
                                      item: item,
                                      displayName: displayName,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
