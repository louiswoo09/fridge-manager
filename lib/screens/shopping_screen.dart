import 'dart:async';
import 'package:flutter/material.dart';
import 'shopping_detail_screen.dart';
import '../services/cart_service.dart';
import 'cart_screen.dart';
import '../services/product_name_formatter.dart';
import '../services/kamis_cache_service.dart';

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

  final KamisCacheService _kamisCache = KamisCacheService();

  final TextEditingController _searchController = TextEditingController();

  final CartService _cartService = CartService();
  Set<String> _cartKeys = {};
  StreamSubscription<List<String>>? _cartSubscription;

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
    'discount': '할인율순',
    'price': '가격순',
    'name': '이름순',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _fetchData();
    _cartSubscription = _cartService.watchKeys().listen((keys) {
      if (!mounted) return;
      setState(() => _cartKeys = keys.toSet());
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _cartSubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetchData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      if (forceRefresh) _allItems = [];
    });

    try {
      final items = await _kamisCache.getDailyItems(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _allItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('KAMIS API 오류: $e');
      _showSnack('가격 정보를 불러오지 못했어요');
    }
  }

  double _calcDiscount(Map<String, dynamic> item) {
    final dpr1Str = item['dpr1']?.toString().replaceAll(',', '') ?? '';
    final baseStr = item[_comparisonBase]?.toString().replaceAll(',', '') ?? '';
    final current = double.tryParse(dpr1Str);
    final base = double.tryParse(baseStr);
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
        final displayName = ProductNameFormatter.format(item).toLowerCase();
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

  Future<void> _toggleCart(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;

    if (_cartService.contains(_cartKeys, productNo, productName)) {
      await _cartService.remove(productNo, productName);
      _showSnack('${ProductNameFormatter.format(item)} 장바구니에서 제거됨');
    } else {
      await _cartService.add(productNo, productName);
      _showSnack('${ProductNameFormatter.format(item)} 장바구니에 담김');
    }
  }

  void _showFilterSheet() {
    String tempComparison = _comparisonBase;
    String tempSort = _sortMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '필터',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _comparisonBase = 'dpr3';
                            _sortMode = 'discount';
                          });
                          setSheetState(() {});
                        },
                        child: const Text('초기화'),
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text(
                    '비교 기준',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _comparisonOptions.entries
                        .map(
                          (e) => FilterChip(
                            label: Text(e.value),
                            selected: _comparisonBase == e.key,
                            onSelected: (_) {
                              setState(() => _comparisonBase = e.key);
                              setSheetState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '정렬',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _sortOptions.entries
                        .map(
                          (e) => FilterChip(
                            label: Text(e.value),
                            selected: _sortMode == e.key,
                            onSelected: (_) {
                              setState(() => _sortMode = e.key);
                              setSheetState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _comparisonBase = tempComparison;
                            _sortMode = tempSort;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '필터',
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            tooltip: '장바구니',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShoppingCartScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _isLoading ? null : () => _fetchData(forceRefresh: true),
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

                          final displayName = ProductNameFormatter.format(item);
                          final basePrice = item[_comparisonBase];

                          final productNo = item['productno']?.toString() ?? '';
                          final productName =
                              item['productName']?.toString() ?? '';
                          final inCart = _cartService.contains(
                            _cartKeys,
                            productNo,
                            productName,
                          );

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                6,
                                8,
                                6,
                              ),
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
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    discount > 0
                                        ? '-${discount.toStringAsFixed(1)}%'
                                        : '+${discount.abs().toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: discountColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: Icon(
                                      inCart
                                          ? Icons.check_circle
                                          : Icons.add_circle_outline,
                                      color: inCart
                                          ? Colors.deepPurple
                                          : Colors.grey,
                                    ),
                                    onPressed: () => _toggleCart(item),
                                  ),
                                ],
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
