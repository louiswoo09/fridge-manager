import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cart_service.dart';
import 'shopping_detail_screen.dart';
import 'add_ingredient_screen.dart';
import '../services/product_name_formatter.dart';
import '../services/kamis_cache_service.dart';

class ShoppingCartScreen extends StatefulWidget {
  const ShoppingCartScreen({super.key});

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  final CartService _cartService = CartService();
  final KamisCacheService _kamisCache = KamisCacheService();
  bool _isLoading = true;
  Set<String> _cartKeys = {};
  List<Map<String, dynamic>> _allItems = [];
  StreamSubscription<List<String>>? _cartSubscription;

  @override
  void initState() {
    super.initState();
    _cartSubscription = _cartService.watchKeys().listen((keys) {
      if (!mounted) return;
      setState(() => _cartKeys = keys.toSet());
    });
    _fetchData();
  }

  @override
  void dispose() {
    _cartSubscription?.cancel();
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

  Future<void> _removeFromCart(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;
    await _cartService.remove(productNo, productName);
    _showSnack('${ProductNameFormatter.format(item)} 장바구니에서 제거됨');
  }

  Future<void> _purchaseItem(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddIngredientScreen(
          prefilledName: ProductNameFormatter.format(item),
        ),
      ),
    );

    if (result == true && mounted) {
      await _cartService.remove(productNo, productName);
      _showSnack('${ProductNameFormatter.format(item)} 보유 식재료에 추가됨');
    }
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
      appBar: AppBar(title: Text('장바구니 (${cartItems.length})')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : cartItems.isEmpty
          ? const Center(child: Text('장바구니가 비어있어요.'))
          : ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final item = cartItems[index];
                final displayName = ProductNameFormatter.format(item);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    title: Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('${item['dpr1']}원 / ${item['unit']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.shopping_bag_outlined,
                            color: Colors.deepPurple,
                          ),
                          tooltip: '구매',
                          onPressed: () => _purchaseItem(item),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () => _removeFromCart(item),
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
            ),
    );
  }
}
