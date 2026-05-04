import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/cart_service.dart';
import 'shopping_detail_screen.dart';
import 'add_ingredient_screen.dart';

const String kKamisCertKey = String.fromEnvironment('KAMIS_CERT_KEY');
const String kKamisCertId = String.fromEnvironment('KAMIS_CERT_ID');

class ShoppingCartScreen extends StatefulWidget {
  const ShoppingCartScreen({super.key});

  @override
  State<ShoppingCartScreen> createState() => _ShoppingCartScreenState();
}

class _ShoppingCartScreenState extends State<ShoppingCartScreen> {
  final CartService _cartService = CartService();
  bool _isLoading = true;
  Set<String> _cartKeys = {};
  List<Map<String, dynamic>> _allItems = [];
  StreamSubscription<List<String>>? _cartSubscription;

  final Map<String, String> _nameOverride = {
    '풋고추/풋고추(녹광 등)': '풋고추',
    '고구마/밤': '밤고구마',
  };

  final List<String> _stripPrefix = ['풋고추'];

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

      final filtered = priceData.cast<Map<String, dynamic>>().where((item) {
        final clsCode = item['product_cls_code']?.toString() ?? '';
        return clsCode == '01';
      }).toList();

      if (!mounted) return;
      setState(() {
        _allItems = filtered;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('KAMIS API 오류: $e');
    }
  }

  Future<void> _removeFromCart(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;
    await _cartService.remove(productNo, productName);
    _showSnack('${_getDisplayName(item)} 장바구니에서 제거됨');
  }

  Future<void> _purchaseItem(Map<String, dynamic> item) async {
    final productNo = item['productno']?.toString() ?? '';
    final productName = item['productName']?.toString() ?? '';
    if (productNo.isEmpty) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddIngredientScreen(prefilledName: _getDisplayName(item)),
      ),
    );

    if (result == true && mounted) {
      await _cartService.remove(productNo, productName);
      _showSnack('${_getDisplayName(item)} 보유 식재료에 추가됨');
    }
  }

  String _getDisplayName(Map<String, dynamic> item) {
    final productNameRaw = item['productName']?.toString() ?? '';
    final categoryCode = item['category_code']?.toString() ?? '';

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

      if (_stripPrefix.contains(front)) return back;
      if (back.contains(front)) return back;

      if (categoryCode == '500') {
        return '$front $back';
      }

      if (back.contains('(')) {
        final cleaned = back.replaceFirst('(', ')(');
        return '$front($cleaned';
      }

      return '$front($back)';
    }
    return productNameRaw;
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
                final displayName = _getDisplayName(item);

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
