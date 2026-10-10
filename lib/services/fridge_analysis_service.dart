import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ingredient.dart';
import '../services/product_name_formatter.dart';
import '../config/api_config.dart';

class FridgeAnalysis {
  final String status;
  final String suggestion;
  final List<String> imminentNames;
  final DateTime generatedAt;

  FridgeAnalysis({
    required this.status,
    required this.suggestion,
    required this.imminentNames,
    required this.generatedAt,
  });

  bool isExpired() {
    return DateTime.now().difference(generatedAt) > const Duration(hours: 24);
  }

  Map<String, dynamic> toMap() => {
    'status': status,
    'suggestion': suggestion,
    'imminentNames': imminentNames,
    'generatedAt': Timestamp.fromDate(generatedAt),
  };

  factory FridgeAnalysis.fromMap(Map<String, dynamic> map) {
    return FridgeAnalysis(
      status: map['status']?.toString() ?? '',
      suggestion: map['suggestion']?.toString() ?? '',
      imminentNames:
          (map['imminentNames'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      generatedAt:
          (map['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class FridgeAnalysisService {
  static final FridgeAnalysisService _instance = FridgeAnalysisService._();
  factory FridgeAnalysisService() => _instance;
  FridgeAnalysisService._();

  // 메모리 캐시 (in-session 빠른 조회용)
  final Map<String, FridgeAnalysis> _memoryCache = {};
  final Map<String, Future<FridgeAnalysis>> _inflight = {};

  String? _cachedActiveFridgeId;

  Future<String> _getActiveFridgeId() async {
    if (_cachedActiveFridgeId != null) return _cachedActiveFridgeId!;
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final id = doc.data()?['activeFridgeId']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('활성 냉장고가 없습니다');
    }
    _cachedActiveFridgeId = id;
    return id;
  }

  void invalidateCache() {
    _cachedActiveFridgeId = null;
  }

  /// 현재 활성 냉장고의 캐시 (메모리만, 즉시 동기 반환)
  FridgeAnalysis? get cached {
    final id = _cachedActiveFridgeId;
    if (id == null) return null;
    final entry = _memoryCache[id];
    if (entry == null) return null;
    if (entry.isExpired()) {
      _memoryCache.remove(id);
      return null;
    }
    return entry;
  }

  void clear() {
    _memoryCache.clear();
  }

  /// 현재 활성 냉장고의 분석 캐시 삭제 (메모리 + Firestore)
  /// 분석할 재료가 없어졌을 때 호출 → 다음 분석은 새로 요청
  Future<void> clearCurrent() async {
    final fridgeId = await _getActiveFridgeId();
    _memoryCache.remove(fridgeId);
    try {
      await FirebaseFirestore.instance
          .collection('fridges')
          .doc(fridgeId)
          .update({'analysisCache': FieldValue.delete()});
    } catch (e) {
      debugPrint('분석 캐시 삭제 실패: $e');
    }
  }

  /// Firestore 캐시에서 로드 시도
  Future<FridgeAnalysis?> _loadFirestoreCache(String fridgeId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('fridges')
          .doc(fridgeId)
          .get();
      final cache = doc.data()?['analysisCache'] as Map<String, dynamic>?;
      if (cache == null) return null;

      final analysis = FridgeAnalysis.fromMap(cache);
      if (analysis.isExpired()) return null;
      return analysis;
    } catch (e) {
      debugPrint('Firestore 캐시 로드 실패: $e');
      return null;
    }
  }

  /// Firestore 캐시에 저장
  Future<void> _saveFirestoreCache(
    String fridgeId,
    FridgeAnalysis analysis,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('fridges')
          .doc(fridgeId)
          .update({'analysisCache': analysis.toMap()});
    } catch (e) {
      debugPrint('Firestore 캐시 저장 실패: $e');
    }
  }

  /// 분석 요청 (메모리 → Firestore → 새 호출 순)
  Future<FridgeAnalysis> analyze({
    required List<Ingredient> ingredients,
    required List<Ingredient> imminentIngredients,
    bool forceRefresh = false,
  }) async {
    final fridgeId = await _getActiveFridgeId();

    // 1. 메모리 캐시 확인
    if (!forceRefresh) {
      final mem = _memoryCache[fridgeId];
      if (mem != null && !mem.isExpired()) {
        return mem;
      }

      // 2. Firestore 캐시 확인
      final fs = await _loadFirestoreCache(fridgeId);
      if (fs != null) {
        _memoryCache[fridgeId] = fs; // 메모리에 캐시
        return fs;
      }
    }

    // 3. in-flight 요청 공유
    final existing = _inflight[fridgeId];
    if (existing != null) return existing;

    // 4. 새 호출
    final future = _callGemini(ingredients, imminentIngredients)
        .then((result) async {
          _memoryCache[fridgeId] = result;
          await _saveFirestoreCache(fridgeId, result);
          return result;
        })
        .whenComplete(() {
          _inflight.remove(fridgeId);
        });

    _inflight[fridgeId] = future;
    return future;
  }

  Future<FridgeAnalysis> _callGemini(
    List<Ingredient> all,
    List<Ingredient> imminent,
  ) async {
    final cleanedAll = all
        .map((i) => ProductNameFormatter.toSearchKeyword(i.name.trim()))
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    final cleanedImminent = imminent
        .map((i) => ProductNameFormatter.toSearchKeyword(i.name.trim()))
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();

    final response = await http
        .post(
          Uri.parse('$kApiBaseUrl/ai/fridge-analysis'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'ingredients': cleanedAll,
            'imminent': cleanedImminent,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('분석 실패 (코드 ${response.statusCode})');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    debugPrint('분석 결과: $data');

    return FridgeAnalysis(
      status: data['status']?.toString() ?? '분석 정보 없음',
      suggestion: data['suggestion']?.toString() ?? '추천 없음',
      imminentNames: cleanedImminent,
      generatedAt: DateTime.now(),
    );
  }
}
