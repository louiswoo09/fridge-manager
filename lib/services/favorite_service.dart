import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe_mode.dart';

class FavoriteService {
  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('로그인이 필요해요');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _favRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('favorites');

  
  String _makeKey({required String recipeId, String? aiResult}) {
    if (aiResult == null) {
      return 'original_$recipeId';
    }
    final hash = aiResult.hashCode.toString();
    return 'variant_${recipeId}_$hash';
  }

  /// 즐겨찾기 목록 Stream
  Stream<List<Map<String, dynamic>>> watchFavorites() {
    return _favRef
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) {
            final data = d.data();
            data['_docId'] = d.id;
            return data;
          }).toList(),
        );
  }

  /// 즐겨찾기 키 목록 (어떤 게 즐겨찾기 됐는지 체크용)
  Stream<Set<String>> watchFavoriteKeys() {
    return _favRef.snapshots().map(
      (snap) => snap.docs.map((d) => d.id).toSet(),
    );
  }

  /// 즐겨찾기 추가
  /// mode, fridgeFilter는 저장만 함 (상세 화면 복원용). 키 생성에는 안 씀.
  Future<void> add({
    required String recipeId,
    required String recipeName,
    required Map<String, dynamic> recipeData,
    String? aiResult,
    RecipeMode? mode,
    FridgeFilter? fridgeFilter,
  }) async {
    final key = _makeKey(recipeId: recipeId, aiResult: aiResult);

    await _favRef.doc(key).set({
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeData': recipeData,
      'aiResult': aiResult,
      'mode': mode?.name,
      'fridgeFilter': fridgeFilter?.name,
      'addedAt': Timestamp.now(),
    });
  }

  /// 즐겨찾기 제거
  Future<void> remove({required String recipeId, String? aiResult}) async {
    final key = _makeKey(recipeId: recipeId, aiResult: aiResult);
    await _favRef.doc(key).delete();
  }

  /// 변형 + 원본을 한 번에 추가 (Stream 깜빡임 방지)
  Future<void> addVariantWithOriginal({
    required String recipeId,
    required String recipeName,
    required Map<String, dynamic> recipeData,
    required String aiResult,
    RecipeMode? mode,
    FridgeFilter? fridgeFilter,
  }) async {
    final batch = FirebaseFirestore.instance.batch();

    // 원본
    final originalKey = _makeKey(recipeId: recipeId, aiResult: null);
    final originalRef = _favRef.doc(originalKey);
    batch.set(originalRef, {
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeData': recipeData,
      'aiResult': null,
      'mode': null,
      'fridgeFilter': null,
      'addedAt': Timestamp.now(),
    });

    // 변형
    final variantKey = _makeKey(recipeId: recipeId, aiResult: aiResult);
    final variantRef = _favRef.doc(variantKey);
    batch.set(variantRef, {
      'recipeId': recipeId,
      'recipeName': recipeName,
      'recipeData': recipeData,
      'aiResult': aiResult,
      'mode': mode?.name,
      'fridgeFilter': fridgeFilter?.name,
      'addedAt': Timestamp.now(),
    });

    await batch.commit();
  }

  /// 특정 레시피가 즐겨찾기에 있는지
  bool contains(
    Set<String> keys, {
    required String recipeId,
    String? aiResult,
  }) {
    final key = _makeKey(recipeId: recipeId, aiResult: aiResult);
    return keys.contains(key);
  }
}
