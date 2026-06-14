import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CartService {
  static final CartService _instance = CartService._();
  factory CartService() => _instance;
  CartService._();

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요해요');
    return user.uid;
  }

  String? _cachedActiveFridgeId;

  Future<String> _getActiveFridgeId() async {
    if (_cachedActiveFridgeId != null) return _cachedActiveFridgeId!;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();
    final id = doc.data()?['activeFridgeId']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('활성 냉장고가 없습니다');
    }
    _cachedActiveFridgeId = id;
    return id;
  }

  /// 냉장고 전환 시 캐시 무효화
  void invalidateCache() {
    _cachedActiveFridgeId = null;
  }

  Future<CollectionReference<Map<String, dynamic>>> _cartRef() async {
    final fridgeId = await _getActiveFridgeId();
    return FirebaseFirestore.instance
        .collection('fridges')
        .doc(fridgeId)
        .collection('cart');
  }

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

  Stream<List<String>> watchKeys() async* {
    final ref = await _cartRef();
    yield* ref.snapshots().map(
      (snap) => snap.docs.map((doc) => doc.id).toList(),
    );
  }

  Stream<List<String>> watchDisplayNames() async* {
    final ref = await _cartRef();
    yield* ref.snapshots().map(
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
  Stream<Map<String, int>> watchQuantities() async* {
    final ref = await _cartRef();
    yield* ref.snapshots().map((snap) {
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
    final ref = await _cartRef();
    final key = _makeKey(productNo, productName);
    final docRef = ref.doc(key);

    final doc = await docRef.get();
    if (doc.exists) {
      final current = (doc.data()?['quantity'] as num?)?.toInt() ?? 1;
      await docRef.update({'quantity': current + 1});
    } else {
      await docRef.set({
        'productno': productNo,
        'productName': productName,
        'displayName': displayName,
        'quantity': 1,
        'addedAt': Timestamp.now(),
      });
    }
  }

  Future<void> addQuantity({
    required String productNo,
    required String productName,
    required String displayName,
    required int quantity,
  }) async {
    final ref = await _cartRef();
    final key = _makeKey(productNo, productName);
    final docRef = ref.doc(key);

    final doc = await docRef.get();
    if (doc.exists) {
      final current = (doc.data()?['quantity'] as num?)?.toInt() ?? 1;
      await docRef.update({'quantity': current + quantity});
    } else {
      await docRef.set({
        'productno': productNo,
        'productName': productName,
        'displayName': displayName,
        'quantity': quantity,
        'addedAt': Timestamp.now(),
      });
    }
  }

  /// 수량 감소 — 1이 최소, 더 줄이지 않음
  Future<void> decrement({
    required String productNo,
    required String productName,
  }) async {
    final ref = await _cartRef();
    final key = _makeKey(productNo, productName);
    final docRef = ref.doc(key);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final current = (doc.data()?['quantity'] as num?)?.toInt() ?? 1;
    if (current <= 1) return;

    await docRef.update({'quantity': current - 1});
  }

  Future<void> remove(String productNo, String productName) async {
    final ref = await _cartRef();
    final key = _makeKey(productNo, productName);
    await ref.doc(key).delete();
  }

  bool contains(Set<String> keys, String productNo, String productName) {
    final key = _makeKey(productNo, productName);
    return keys.contains(key);
  }
}
