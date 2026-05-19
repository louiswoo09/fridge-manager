import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ingredient.dart';
import '../services/product_name_formatter.dart';

const String _kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String _kGeminiModel = 'gemini-3.1-flash-lite-preview';

class FridgeAnalysis {
  final String status; // "단백질 부족, 채소 풍부"
  final String suggestion; // "볶음, 국물 요리"
  final List<String> imminentNames; // ["두부", "양상추"]
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
}

class FridgeAnalysisService {
  static final FridgeAnalysisService _instance = FridgeAnalysisService._();
  factory FridgeAnalysisService() => _instance;
  FridgeAnalysisService._();

  FridgeAnalysis? _cached;
  Future<FridgeAnalysis>? _inflight;

  FridgeAnalysis? get cached =>
      (_cached != null && !_cached!.isExpired()) ? _cached : null;

  void clear() {
    _cached = null;
  }

  /// 분석 요청 (캐시 우선, 만료/forceRefresh 시 새로 호출)
  Future<FridgeAnalysis> analyze({
    required List<Ingredient> ingredients,
    required List<Ingredient> imminentIngredients,
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && cached != null) {
      return Future.value(cached);
    }
    if (_inflight != null) return _inflight!;

    _inflight = _callGemini(ingredients, imminentIngredients)
        .then((result) {
          _cached = result;
          return result;
        })
        .whenComplete(() {
          _inflight = null;
        });
    return _inflight!;
  }

  Future<FridgeAnalysis> _callGemini(
    List<Ingredient> all,
    List<Ingredient> imminent,
  ) async {
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

    // 재시도 로직
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
