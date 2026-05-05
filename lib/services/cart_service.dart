import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CartService {
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요해요');
    }
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

  Stream<List<String>> watchKeys() {
    return _cartRef.snapshots().map(
      (snap) => snap.docs.map((doc) => doc.id).toList(),
    );
  }

  /// 장바구니에 담긴 표시용/검색용 정제된 이름 리스트
  /// (담을 때 ProductNameFormatter.format 적용한 결과를 같이 저장)
  Stream<List<String>> watchDisplayNames() {
    return _cartRef.snapshots().map(
      (snap) => snap.docs
          .map((doc) {
            final data = doc.data();
            // displayName 우선, 없으면 productName fallback (이전 데이터 호환)
            return data['displayName']?.toString() ??
                data['productName']?.toString() ??
                '';
          })
          .where((name) => name.isNotEmpty)
          .toList(),
    );
  }

  Future<void> add({
    required String productNo,
    required String productName,
    required String displayName,
  }) async {
    final key = _makeKey(productNo, productName);
    await _cartRef.doc(key).set({
      'productno': productNo,
      'productName': productName,
      'displayName': displayName,
      'addedAt': Timestamp.now(),
    });
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