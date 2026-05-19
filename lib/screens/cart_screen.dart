import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import 'shopping_detail_screen.dart';
import 'add_ingredient_screen.dart';
import '../services/product_name_formatter.dart';
import '../services/kamis_cache_service.dart';
import '../models/recipe_mode.dart';

typedef OnRequestRecipe = void Function(RecipeMode mode);

class CartScreen extends StatefulWidget {
  final OnRequestRecipe? onRequestRecipe;

  const CartScreen({super.key, this.onRequestRecipe});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cartService = CartService();
  final KamisCacheService _kamisCache = KamisCacheService();
  bool _isLoading = true;
  Set<String> _cartKeys = {};
  Map<String, int> _quantities = {};
  bool _isMoveMode = false;
  final Set<String> _selectedIds = {};
  List<Map<String, dynamic>> _allItems = [];
  StreamSubscription<List<String>>? _cartSubscription;
  StreamSubscription<Map<String, int>>? _quantitySubscription;

  @override
  void initState() {
    super.initState();
    _cartSubscription = _cartService.watchKeys().listen((keys) {
      if (!mounted) return;
      setState(() => _cartKeys = keys.toSet());
    });
    _quantitySubscription = _cartService.watchQuantities().listen((map) {
      if (!mounted) return;
      setState(() => _quantities = map);
    });
    _fetchData();
  }

  @override
  void dispose() {
    _cartSubscription?.cancel();
    _quantitySubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    try {
      final items = await _kamisCache.getDailyItems();
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

  int _quantityOf(Map<String, dynamic> item) {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    final key = _cartService.keyFor(productNo, productName);
    return _quantities[key] ?? 1;
  }

  String _formatNumber(int value) {
    return value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  Future<void> _incrementItem(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    final displayName = ProductNameFormatter.format(item);
    if (productNo.isEmpty) return;
    await _cartService.add(
      productNo: productNo,
      productName: productName,
      displayName: displayName,
    );
  }

  Future<void> _decrementItem(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;
    await _cartService.decrement(
      productNo: productNo,
      productName: productName,
    );
  }

  Future<void> _removeFromCart(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;
    await _cartService.remove(productNo, productName);
    _showSnack('${ProductNameFormatter.format(item)} 담아놓기에서 제거됨');
  }

  Future<void> _moveSelectedToFridge() async {
    if (_selectedIds.isEmpty) return;

    // 선택된 항목들 차례로 AddIngredientScreen 띄우기
    final selectedItems = _cartItems.where((item) {
      final productNo = item['productno']?.toString() ?? '';
      final productName = item['productName']?.toString() ?? '';
      final key = _cartService.keyFor(productNo, productName);
      return _selectedIds.contains(key);
    }).toList();

    for (final item in selectedItems) {
      if (!mounted) return;

      final productNo = item['productno']?.toString() ?? '';
      final productName = item['productName']?.toString() ?? '';
      final cleanName = ProductNameFormatter.toSearchKeyword(
        ProductNameFormatter.format(item),
      );

      final savedName = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => AddIngredientScreen(prefilledName: cleanName),
        ),
      );

      if (savedName != null && savedName.isNotEmpty && mounted) {
        await _cartService.remove(productNo, productName);
      }
    }

    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _isMoveMode = false;
    });
  }

  void _goToRecipeRecommendation() {
    if (_cartItems.isEmpty) {
      _showSnack('담아놓기가 비어있어요');
      return;
    }

    Navigator.pop(context);
    widget.onRequestRecipe?.call(RecipeMode.shopping);
  }

  List<Map<String, dynamic>> get _cartItems {
    return _allItems.where((item) {
      final productNo = item['productno']?.toString() ?? '';
      final productName = item['productName']?.toString() ?? '';
      return _cartService.contains(_cartKeys, productNo, productName);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = _cartItems;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isMoveMode
              ? '${_selectedIds.length}개 선택됨'
              : '담아놓기 (${cartItems.length})',
        ),
        actions: _isMoveMode
            ? [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIds.clear();
                      _isMoveMode = false;
                    });
                  },
                  child: const Text('취소', style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : _moveSelectedToFridge,
                  child: const Text('이동'),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.kitchen),
                  tooltip: '냉장고로 이동',
                  onPressed: cartItems.isEmpty
                      ? null
                      : () => setState(() => _isMoveMode = true),
                ),
                IconButton(
                  icon: const Icon(Icons.restaurant_menu),
                  tooltip: '이 담아놓기로 레시피 추천',
                  onPressed: cartItems.isEmpty
                      ? null
                      : _goToRecipeRecommendation,
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : cartItems.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '담아놓기 화면이 비어있어요.\n\n가격 동향에서 + 버튼으로 담아보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ),
            )
          : ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final item = cartItems[index];
                return _buildCartItem(item);
              },
            ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item) {
    final displayName = ProductNameFormatter.format(item);
    final quantity = _quantityOf(item);
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    final key = _cartService.keyFor(productNo, productName);

    final unitPrice =
        int.tryParse(item['dpr1']?.toString().replaceAll(',', '') ?? '') ?? 0;
    final totalPrice = unitPrice * quantity;

    final isSelected = _selectedIds.contains(key);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _isMoveMode && isSelected ? Colors.deepPurple.shade50 : null,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 40, 16),
            child: Row(
              children: [
                if (_isMoveMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.deepPurple : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_isMoveMode) {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(key);
                          } else {
                            _selectedIds.add(key);
                          }
                        });
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShoppingDetailScreen(
                              item: item,
                              displayName: displayName,
                            ),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item['dpr1']}원 / ${item['unit']}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${_formatNumber(totalPrice)}원',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.deepPurple,
                              ),
                            ),
                            const SizedBox(width: 2),
                            if (_isMoveMode) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '$quantity개',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isMoveMode) ...[
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: quantity <= 1
                        ? null
                        : () => _decrementItem(item),
                  ),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '$quantity',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _incrementItem(item),
                  ),
                ],
              ],
            ),
          ),
          if (!_isMoveMode)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: Colors.grey,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                tooltip: '제거',
                onPressed: () => _removeFromCart(item),
              ),
            ),
        ],
      ),
    );
  }
}
