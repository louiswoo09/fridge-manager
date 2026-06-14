import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ingredient.dart';
import '../services/product_name_formatter.dart';

const String _kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String _kGeminiModel = 'gemini-3.1-flash-lite';

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
      imminentNames: (map['imminentNames'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      generatedAt: (map['generatedAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
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
    final future = _callGemini(ingredients, imminentIngredients).then((result) async {
      _memoryCache[fridgeId] = result;
      await _saveFirestoreCache(fridgeId, result);
      return result;
    }).whenComplete(() {
      _inflight.remove(fridgeId);
    });

    _inflight[fridgeId] = future;
    return future;
  }

  Future<FridgeAnalysis> _callGemini(
    List<Ingredient> all,
    List<Ingredient> imminent,
  ) async {
    // 기존 _callGemini 본문 그대로
    if (_kGeminiApiKey.isEmpty) {
      throw Exception('Gemini API 키가 설정되지 않았습니다');
    }

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

    final prompt = _buildPrompt(cleanedAll, cleanedImminent);

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_kGeminiModel:generateContent?key=$_kGeminiApiKey',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });

    const maxAttempts = 3;
    const delays = [Duration(seconds: 1), Duration(seconds: 3)];
    int? errorCode;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'];

          debugPrint('========= 분석 응답 =========');
          debugPrint(text?.toString() ?? '(null)');
          debugPrint('=============================');

          if (text == null || text.toString().trim().isEmpty) {
            throw Exception('빈 응답');
          }
          return _parseResponse(text.toString(), cleanedImminent);
        }

        errorCode = response.statusCode;
        debugPrint('분석 실패 (status=$errorCode, attempt=${attempt + 1})');

        final shouldRetry =
            (errorCode >= 500 || errorCode == 429) && attempt < maxAttempts - 1;
        if (!shouldRetry) break;
        await Future.delayed(delays[attempt]);
      } on TimeoutException {
        debugPrint('분석 timeout (attempt=${attempt + 1})');
        if (attempt < maxAttempts - 1) {
          await Future.delayed(delays[attempt]);
          continue;
        }
        break;
      }
    }

    throw Exception('분석 실패 (코드 ${errorCode ?? "?"})');
  }

  String _buildPrompt(List<String> all, List<String> imminent) {
    return '''
당신은 냉장고를 분석해 사용자의 편의성을 돕는 슈퍼 프로페셔널 인텔리전트 AI입니다. 
사용자의 냉장고 속 보유 식재료를 보고 간단히 분석해주세요.

[보유 식재료]
${all.join(', ')}

[임박 재료 (3일 이내)]
${imminent.isEmpty ? "없음" : imminent.join(', ')}

<규칙>
1. 설명, 인사말, 추가 텍스트는 절대 작성하지 마세요.
2. 각 줄은 18자 이내로 짧게 작성하세요.
3. 반드시 다음 형식으로만 응답하세요. 
'
재료 균형: <영양 균형이나 식재료 비중을 쉼표로 구분하여 작성하세요. 예: "단백질 부족, 채소 풍부">
추천 요리: <어떤 요리 유형이 적합한지 재료 이름을 붙이지 말고 반드시 요리 고유 명사로만 쉼표로 구분하여 작성하세요. 예: "닭볶음탕, 파스타, 부대찌개">
'
''';
  }

  FridgeAnalysis _parseResponse(String text, List<String> imminentNames) {
    String status = '';
    String suggestion = '';

    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('재료 균형:')) {
        status = trimmed.substring(6).trim();
      } else if (trimmed.startsWith('추천 요리:')) {
        suggestion = trimmed.substring(6).trim();
      }
    }

    debugPrint('파싱 결과 — status: "$status", suggestion: "$suggestion"');

    return FridgeAnalysis(
      status: status.isEmpty ? '분석 정보 없음' : status,
      suggestion: suggestion.isEmpty ? '추천 없음' : suggestion,
      imminentNames: imminentNames,
      generatedAt: DateTime.now(),
    );
  }
}