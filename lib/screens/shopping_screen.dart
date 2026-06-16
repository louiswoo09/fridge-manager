import 'dart:async';
import 'package:flutter/material.dart';
import 'shopping_detail_screen.dart';
import '../services/cart_service.dart';
import 'cart_screen.dart';
import '../services/product_name_formatter.dart';
import '../services/kamis_cache_service.dart';
import '../models/recipe_mode.dart';
import '../services/fridge_service.dart';

typedef OnRequestRecipe = void Function(RecipeMode mode);

class ShoppingScreen extends StatefulWidget {
  final OnRequestRecipe? onRequestRecipe;

  const ShoppingScreen({super.key, this.onRequestRecipe});

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
  final FridgeService _fridgeService = FridgeService();
  Map<String, int> _cartQuantities = {};
  StreamSubscription<Map<String, int>>? _cartQuantitySub;
  StreamSubscription<String?>? _activeFridgeIdSub;
  final Map<String, int> _pendingQuantities = {};

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

    // 활성 냉장고 변화 감지 → Stream 재구독
    _activeFridgeIdSub = _fridgeService.watchActiveFridgeId().listen((id) {
      if (id == null || !mounted) return;
      _resubscribeCart();
    });
  }

  void _resubscribeCart() async {
    // 기존 구독 해제
    await _cartQuantitySub?.cancel();

    // 캐시 무효화 (이미 IngredientListScreen에서 했을 수 있지만 안전 차원)
    _cartService.invalidateCache();

    // 수량 리셋 + 새 구독
    if (!mounted) return;
    setState(() {
      _cartQuantities = {};
      _pendingQuantities.clear();
    });

    _cartQuantitySub = _cartService.watchQuantities().listen((quantities) {
      if (!mounted) return;
      setState(() => _cartQuantities = quantities);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _cartQuantitySub?.cancel();
    _activeFridgeIdSub?.cancel();
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

  String _scaledUnit(String unit, int multiplier) {
    if (unit.isEmpty) return '';

    // 정규식: 시작의 숫자(정수/소수) 추출
    final match = RegExp(r'^(\d+\.?\d*)(.*)$').firstMatch(unit);
    if (match == null) {
      // 숫자 없으면 "N개" 형태로 그냥 곱한 수량 표시
      return '$multiplier$unit';
    }

    final number = double.tryParse(match.group(1)!) ?? 1.0;
    final suffix = match.group(2)!.trim();
    final scaled = number * multiplier;

    // 정수면 정수로, 소수면 소수로
    final scaledText = scaled == scaled.truncate()
        ? scaled.toInt().toString()
        : scaled.toString();

    return '$scaledText$suffix';
  }

  String _formatScaledPrice(String priceStr, int multiplier) {
    final cleaned = priceStr.replaceAll(',', '');
    final price = double.tryParse(cleaned);
    if (price == null) return priceStr;

    final scaled = (price * multiplier).round();
    // 천 단위 콤마
    return scaled.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
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

  void _adjustPending(String key, int delta) {
    setState(() {
      final current = _pendingQuantities[key] ?? 1;
      final next = (current + delta).clamp(1, 99);
      _pendingQuantities[key] = next;
    });
  }

  Future<void> _addToCart(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;

    final key = _cartService.keyFor(productNo, productName);
    final quantity = _pendingQuantities[key] ?? 1;
    final displayName = ProductNameFormatter.format(item);

    await _cartService.addQuantity(
      productNo: productNo,
      productName: productName,
      displayName: displayName,
      quantity: quantity,
    );
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
        title: const Text('가격 동향'),
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
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: '담아놓기',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CartScreen(onRequestRecipe: widget.onRequestRecipe),
                ),
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
                          final key = _cartService.keyFor(
                            productNo,
                            productName,
                          );
                          final pendingQty = _pendingQuantities[key] ?? 1;
                          final cartQty = _cartQuantities[key] ?? 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: InkWell(
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
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  12,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 1줄: 이름 + 할인율 + 담김 수량
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  displayName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                        ),
                                        if (cartQty > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '$cartQty개 담김',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color:
                                                    Colors.deepPurple.shade700,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),

                                    // 가격 (2줄) + 수량 + 담기 (한 Row)
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        // 왼쪽: 가격 두 줄
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '현재: ${_formatScaledPrice(item['dpr1']?.toString() ?? '0', pendingQty)}원',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_comparisonOptions[_comparisonBase]}: ${_formatScaledPrice(basePrice?.toString() ?? '0', pendingQty)}원',
                                                style: const TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // 할인율
                                        SizedBox(
                                          width: 70,
                                          child: Center(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: discountColor.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                discount > 0
                                                    ? '-${discount.toStringAsFixed(1)}%'
                                                    : '+${discount.abs().toStringAsFixed(1)}%',
                                                style: TextStyle(
                                                  color: discountColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        // 수량 조절
                                        SizedBox(
                                          width: 95,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              InkWell(
                                                onTap: () =>
                                                    _adjustPending(key, -1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(2),
                                                  child: Icon(
                                                    Icons.remove_circle_outline,
                                                    size: 22,
                                                    color: Colors.deepPurple,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  _scaledUnit(
                                                    item['unit']?.toString() ??
                                                        '',
                                                    pendingQty,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () =>
                                                    _adjustPending(key, 1),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(2),
                                                  child: Icon(
                                                    Icons.add_circle_outline,
                                                    size: 22,
                                                    color: Colors.deepPurple,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // 담기 버튼
                                        ElevatedButton(
                                          onPressed: () => _addToCart(item),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.deepPurple,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            minimumSize: const Size(0, 32),
                                            textStyle: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                          child: const Text('담기'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
