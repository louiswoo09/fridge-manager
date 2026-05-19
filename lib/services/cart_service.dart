import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CartService {
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요해요');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _cartRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('cart');

  String _makeKey(String productNo, String productName) {
    final cleanName = productName
        .replaceAll('/', '_')
        .replaceAll(' ', '')
        .replaceAll('(', '')
        .replaceAll(')', '');
    return '${productNo}_$cleanName';
  }

  /// 외부에서 키 조회용
  String keyFor(String productNo, String productName) {
    return _makeKey(productNo, productName);
  }

  Stream<List<String>> watchKeys() {
    return _cartRef.snapshots().map(
      (snap) => snap.docs.map((doc) => doc.id).toList(),
    );
  }

  Stream<List<String>> watchDisplayNames() {
    return _cartRef.snapshots().map(
      (snap) => snap.docs
          .map((doc) {
            final data = doc.data();
            return data['displayName']?.toString() ??
                data['productName']?.toString() ??
                '';
          })
          .where((name) => name.isNotEmpty)
          .toList(),
    );
  }

  /// 키별 수량 맵 (UI에서 +/- 버튼 표시용)
  Stream<Map<String, int>> watchQuantities() {
    return _cartRef.snapshots().map((snap) {
      final result = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        result[doc.id] = (data['quantity'] as num?)?.toInt() ?? 1;
      }
      return result;
    });
  }

  Future<void> add({
    required String productNo,
    required String productName,
    required String displayName,
  }) async {
    final key = _makeKey(productNo, productName);
    final ref = _cartRef.doc(key);

    final doc = await ref.get();
    if (doc.exists) {
      final current = (doc.data()?['quantity'] as num?)?.toInt() ?? 1;
      await ref.update({'quantity': current + 1});
    } else {
      await ref.set({
        'productno': productNo,
        'productName': productName,
        'displayName': displayName,
        'quantity': 1,
        'addedAt': Timestamp.now(),
      });
    }
  }

  /// 수량 감소 — 1이 최소, 더 줄이지 않음
  Future<void> decrement({
    required String productNo,
    required String productName,
  }) async {
    final key = _makeKey(productNo, productName);
    final ref = _cartRef.doc(key);
    final doc = await ref.get();
    if (!doc.exists) return;

    final current = (doc.data()?['quantity'] as num?)?.toInt() ?? 1;
    if (current <= 1) return;

    await ref.update({'quantity': current - 1});
  }

  Future<void> remove(String productNo, String productName) async {
    final key = _makeKey(productNo, productName);
    await _cartRef.doc(key).delete();
  }

  bool contains(Set<String> keys, String productNo, String productName) {
    final key = _makeKey(productNo, productName);
    return keys.contains(key);
  }
}