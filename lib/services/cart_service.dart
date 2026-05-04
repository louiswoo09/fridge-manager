import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CartService {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

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

  Future<void> add(String productNo, String productName) async {
    final key = _makeKey(productNo, productName);
    await _cartRef.doc(key).set({
      'productno': productNo,
      'productName': productName,
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