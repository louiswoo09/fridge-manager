import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ingredient.dart';

class IngredientService {
  static final IngredientService _instance = IngredientService._();
  factory IngredientService() => _instance;
  IngredientService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _cachedActiveFridgeId;

  Future<String> _getActiveFridgeId() async {
    if (_cachedActiveFridgeId != null) return _cachedActiveFridgeId!;

    final uid = _auth.currentUser!.uid;
    final doc = await _db.collection('users').doc(uid).get();
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

  Stream<List<Ingredient>> getIngredients({
    bool sortByExpiration = true,
  }) async* {
    final fridgeId = await _getActiveFridgeId();

    Query<Map<String, dynamic>> query = _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: false);

    query = sortByExpiration
        ? query.orderBy('expiration_date', descending: false)
        : query.orderBy('added_at', descending: true);

    yield* query.snapshots().map(
      (snapshot) => snapshot.docs
          .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
          .toList(),
    );
  }

  Future<void> cleanOldDeletedItems() async {
    final fridgeId = await _getActiveFridgeId();

    final snapshot = await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .get();

    final batch = _db.batch();

    for (var doc in snapshot.docs) {
      final deletedAt = doc['deleted_at'];
      if (deletedAt == null) continue;

      final diff = DateTime.now().difference(deletedAt.toDate()).inDays;
      if (diff >= 7) {
        batch.delete(doc.reference);
      }
    }

    await batch.commit();
  }

  /// 식재료 추가
  Future<void> addIngredient(Ingredient ingredient) async {
    final fridgeId = await _getActiveFridgeId();
    await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .add(ingredient.toMap());
  }

  /// 식재료 수정
  Future<void> updateIngredient(String id, Ingredient ingredient) async {
    final fridgeId = await _getActiveFridgeId();
    await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .doc(id)
        .update(ingredient.toMap(isCreate: false));
  }

  /// 식재료 휴지통으로 (소프트 삭제)
  Future<void> softDeleteIngredient(String id) async {
    final fridgeId = await _getActiveFridgeId();
    await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .doc(id)
        .update({'is_deleted': true, 'deleted_at': Timestamp.now()});
  }

  /// 휴지통에서 복구
  Future<void> restoreIngredient(String id) async {
    final fridgeId = await _getActiveFridgeId();
    await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .doc(id)
        .update({'is_deleted': false, 'deleted_at': null});
  }

  /// 영구 삭제
  Future<void> permanentlyDeleteIngredient(String id) async {
    final fridgeId = await _getActiveFridgeId();
    await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .doc(id)
        .delete();
  }

  /// 여러 식재료 한 번에 휴지통으로 (배치)
  Future<void> softDeleteMany(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final fridgeId = await _getActiveFridgeId();
    final batch = _db.batch();
    for (final id in ids) {
      final ref = _db
          .collection('fridges')
          .doc(fridgeId)
          .collection('ingredients')
          .doc(id);
      batch.update(ref, {'is_deleted': true, 'deleted_at': Timestamp.now()});
    }
    await batch.commit();
  }

  /// 휴지통의 모든 항목 영구 삭제
  Future<void> emptyTrash() async {
    final fridgeId = await _getActiveFridgeId();
    final snapshot = await _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .get();

    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// 휴지통의 식재료 Stream
  Stream<List<Ingredient>> getDeletedIngredients() async* {
    final fridgeId = await _getActiveFridgeId();
    yield* _db
        .collection('fridges')
        .doc(fridgeId)
        .collection('ingredients')
        .where('is_deleted', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }
}
