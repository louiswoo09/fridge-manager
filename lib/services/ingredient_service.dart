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

  /// 지금 활성 냉장고의 식재료 위치 (다른 함수들이 전부 이걸 씀)
  Future<CollectionReference<Map<String, dynamic>>> _ingredientsCol() async {
    final fridgeId = await _getActiveFridgeId();
    return _db.collection('fridges').doc(fridgeId).collection('ingredients');
  }

  Future<List<Ingredient>> _activeIngredients(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final snap = await col.where('is_deleted', isEqualTo: false).get();
    return snap.docs.map((d) => Ingredient.fromMap(d.data(), d.id)).toList();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 이름·카테고리·단위·보관·소비기한이 모두 같으면 같은 재료로 봄
  bool _isSameLot(Ingredient a, Ingredient b) =>
      a.name.trim() == b.name.trim() &&
      a.category == b.category &&
      a.unit == b.unit &&
      a.storage == b.storage &&
      _sameDay(a.expirationDate, b.expirationDate);

  Stream<List<Ingredient>> getIngredients({
    bool sortByExpiration = true,
  }) async* {
    final col = await _ingredientsCol();

    Query<Map<String, dynamic>> query = col.where(
      'is_deleted',
      isEqualTo: false,
    );

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
    final col = await _ingredientsCol();

    final snapshot = await col.where('is_deleted', isEqualTo: true).get();

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

  /// 식재료 수정
  Future<void> updateIngredient(String id, Ingredient ingredient) async {
    final col = await _ingredientsCol();
    await col.doc(id).update(ingredient.toMap(isCreate: false));
  }

  /// 여러 재료 추가. 똑같은 재료가 이미 있으면 수량만 늘림.
  /// 반환값: 기존 재료에 합쳐진 개수
  Future<int> addMany(List<Ingredient> ingredients) async {
    if (ingredients.isEmpty) return 0;
    final col = await _ingredientsCol();
    final existing = await _activeIngredients(col);

    final newQuantities = <String, int>{}; // 기존 문서 id → 합친 뒤 수량
    final toAdd = <Ingredient>[]; // 새로 만들 것 (이번에 같은 것끼리도 합침)
    var merged = 0;

    for (final ing in ingredients) {
      final match = existing.where((e) => _isSameLot(e, ing)).firstOrNull;
      if (match != null) {
        newQuantities[match.id] =
            (newQuantities[match.id] ?? match.quantity) + ing.quantity;
        merged++;
        continue;
      }
      final i = toAdd.indexWhere((p) => _isSameLot(p, ing));
      if (i >= 0) {
        toAdd[i] = toAdd[i].copyWith(
          quantity: toAdd[i].quantity + ing.quantity,
        );
        merged++;
      } else {
        toAdd.add(ing);
      }
    }

    final batch = _db.batch();
    newQuantities.forEach((id, qty) {
      final e = existing.firstWhere((x) => x.id == id);
      batch.update(
        col.doc(id),
        e.copyWith(quantity: qty).toMap(isCreate: false),
      );
    });
    for (final ing in toAdd) {
      batch.set(col.doc(), ing.toMap());
    }
    await batch.commit();
    return merged;
  }

  /// 재료 하나 추가. 같은 재료가 있으면 수량 합치기
  Future<bool> addIngredient(Ingredient ingredient) async {
    return await addMany([ingredient]) > 0;
  }

  /// 나누기: 원래 재료는 remainingQuantity로 줄이고, 떼어낸 부분을 새로 저장
  /// (보관·소비기한·단위 제한 없음, 자동 합치기 없음)
  Future<void> splitIngredient(
    Ingredient original, {
    required int remainingQuantity,
    required String remainingUnit,
    required int quantity,
    required String unit,
    required String storage,
    required DateTime expirationDate,
  }) async {
    if (quantity <= 0 || remainingQuantity <= 0) {
      throw ArgumentError('수량은 1 이상이어야 합니다');
    }
    final col = await _ingredientsCol();
    final batch = _db.batch();
    batch.update(
      col.doc(original.id),
      original
          .copyWith(quantity: remainingQuantity, unit: remainingUnit)
          .toMap(isCreate: false),
    );
    batch.set(
      col.doc(),
      original
          .copyWith(
            quantity: quantity,
            unit: unit,
            storage: storage,
            expirationDate: expirationDate,
          )
          .toMap(),
    );
    await batch.commit();
  }

  /// 합치기: target을 사용자가 정한 결과로 바꾸고 나머지는 없앰
  Future<void> mergeIngredients(
    Ingredient target,
    List<Ingredient> others,
    Ingredient result,
  ) async {
    final col = await _ingredientsCol();
    final batch = _db.batch();
    batch.update(col.doc(target.id), result.toMap(isCreate: false));
    for (final o in others) {
      batch.delete(col.doc(o.id)); // 합쳐진 거라 휴지통에 넣지 않음
    }
    await batch.commit();
  }

  /// 식재료 휴지통으로 (소프트 삭제)
  Future<void> softDeleteIngredient(String id) async {
    final col = await _ingredientsCol();
    await col.doc(id).update({
      'is_deleted': true,
      'deleted_at': Timestamp.now(),
    });
  }

  /// 여러 식재료 한 번에 휴지통으로 (배치)
  Future<void> softDeleteMany(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final col = await _ingredientsCol();
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(col.doc(id), {
        'is_deleted': true,
        'deleted_at': Timestamp.now(),
      });
    }
    await batch.commit();
  }

  /// 여러 건 복구 (휴지통 묶음 복구용)
  Future<void> restoreMany(Iterable<String> ids) async {
    final col = await _ingredientsCol();
    final batch = _db.batch();
    for (final id in ids) {
      batch.update(col.doc(id), {'is_deleted': false, 'deleted_at': null});
    }
    await batch.commit();
  }

  Future<void> restoreIngredient(String id) => restoreMany([id]);

  /// 영구 삭제
  Future<void> permanentlyDeleteIngredient(String id) async {
    final col = await _ingredientsCol();
    await col.doc(id).delete();
  }

  /// 여러 건 영구 삭제
  Future<void> permanentlyDeleteMany(Iterable<String> ids) async {
    final col = await _ingredientsCol();
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete(col.doc(id));
    }
    await batch.commit();
  }

  /// 휴지통의 모든 항목 영구 삭제
  Future<void> emptyTrash() async {
    final col = await _ingredientsCol();
    final snapshot = await col.where('is_deleted', isEqualTo: true).get();

    if (snapshot.docs.isEmpty) return;
    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// 휴지통의 식재료 Stream
  Stream<List<Ingredient>> getDeletedIngredients() async* {
    final col = await _ingredientsCol();
    yield* col
        .where('is_deleted', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Ingredient.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }
}
