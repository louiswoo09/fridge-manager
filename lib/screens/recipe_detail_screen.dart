import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/recipe_mode.dart';
import '../services/gemini_cache_service.dart';
import '../services/product_name_formatter.dart';

const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final List<String> ownedIngredients;
  final List<String> extraIngredients;
  final RecipeMode mode;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.ownedIngredients,
    this.extraIngredients = const [],
    this.mode = RecipeMode.fridge,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isGeminiLoading = false;
  String? _geminiResult;
  final GeminiCacheService _geminiCache = GeminiCacheService();
  late RecipeMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    _restoreCachedResult();
  }

  void _restoreCachedResult() {
    final cached = _geminiCache.get(_buildCacheKey());
    _geminiResult = cached; // 없으면 null
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onModeChanged(RecipeMode? mode) {
    if (mode == null || mode == _currentMode) return;
    setState(() {
      _currentMode = mode;
      _restoreCachedResult();
    });
  }

  List<String> _getManuals() {
    final manuals = <String>[];
    for (int i = 1; i <= 20; i++) {
      final key = 'MANUAL${i.toString().padLeft(2, '0')}';
      final val = widget.recipe[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        manuals.add(val.toString().trim());
      }
    }
    return manuals;
  }

  String _buildCacheKey() {
    final recipeId =
        widget.recipe['RCP_SEQ']?.toString() ??
        widget.recipe['RCP_NM']?.toString() ??
        '';
    return '${_currentMode.name}|$recipeId';
  }

  String _buildPrompt() {
    final recipeName = widget.recipe['RCP_NM'] ?? '';
    final recipeIngredients = widget.recipe['RCP_PARTS_DTLS'] ?? '';
    final manuals = _getManuals().join('\n');

    // 검색용 키워드로 정제 (괄호/공백 제거)
    final cleanedOwned = widget.ownedIngredients
        .map(ProductNameFormatter.toSearchKeyword)
        .where((name) => name.isNotEmpty)
        .toList();

    final cleanedExtra = widget.extraIngredients
        .map(ProductNameFormatter.toSearchKeyword)
        .where((name) => name.isNotEmpty)
        .toList();

    // 냉장고 섹션 — 비어있을 때 명시적으로 표시
    final ownedSection = cleanedOwned.isEmpty
        ? '[냉장고 속 재료]\n(없음)'
        : '''
[냉장고 속 재료]
${cleanedOwned.join(', ')}''';

    // 장바구니 섹션 — shopping 모드 + 비어있지 않을 때만 추가
    final cartSection =
        (_currentMode == RecipeMode.shopping && cleanedExtra.isNotEmpty)
        ? '''

[장바구니]
${cleanedExtra.join(', ')}

위 두 목록의 재료를 모두 사용 가능한 것으로 간주하되, [장바구니] 재료는 사용자가 일부러 선택한 재료이므로 가능하면 적극적으로 활용해줘.'''
        : '';

    return '''
너는 TV 예능 프로그램 '냉장고를 부탁해'에 출연한 요리 연구가 '젬 쉐프'야. 
이번 프로그램의 주제는 '[주어진 레시피]를 바탕으로 [냉장고 속 재료] 혹은 [장바구니] 재료만으로 조리가 가능하도록 레시피를 변형시켜라!'야.
레시피에 사용하는 재료는 주어진 양념 외에는 반드시 [냉장고 속 재료] 혹은 [장바구니]에 포함된 것만 사용해야해.
그러므로 [주어진 레시피]의 재료 중 [냉장고 속 재료]나 [장바구니]에 없는 것은 제거하거나, [냉장고 속 재료] 혹은 [장바구니] 내에서 재료의 종류와 역할이 유사한 경우에 대체해서 만들어야해. 소스나 양념류는 양념에서 대체해줘.
변형시킨 레시피가 [주어진 레시피]와 요리 유형(한식/중식/일식/양식 등), 형식(국/볶음/구이/샐러드 등), 메인 재료(고기/해산물/채소/과일/면 등)이 동일할 수록 높은 평가를 받을거야. 
물론 변형 레시피가 [주어진 레시피]와 다르더라도 재료 상황에 맞게 자연스럽게 변형하는게 더욱 중요해. 상식에서 벗어난 이상한 레시피는 매우 낮은 평가를 받을거라는걸 꼭 기억해줘.
조리법을 간결하면서도 먹음직스럽게 작성하면 더욱 좋은 평가를 받을지도 몰라.
출연진에게 최고로 높은 평가를 받을 수 있도록 노력하자! 

레시피 작성 조건: 
1. 한국어로 작성할 것. 
2. 요리 제목은 사용 재료를 나열하지 않고 레시피에 사용할 주재료만 포함하여 자연스럽게 새로 작성할 것. 
3. 재료 목록에는 각 재료의 대략적인 양(예: 1캔, 1/2개, 100g, 1스푼 등)을 포함 할것.
4. 양념을 제외한 변형된 레시피의 재료 목록에 없는 재료는 요리 제목이나 조리법에 작성하지 말것.
5. 현실에 존재하지 않는 가상의 재료나 손질하는데 전문 자격이 필요한 위험한 재료(복어, 독버섯, 야생동물 고기 등)는 [냉장고 속 재료]나 [장바구니]에 있더라도 절대 사용하지 말것.
6. 일부 재료(팽이버섯, 은행, 고사리 등)가 독성 또는 위해성을 가질 수 있는 경우, 안전하게 섭취할 수 있는 올바른 조리법을 반드시 포함해서 작성할것.
7. 조리법은 번호(1., 2., ...)로 작성하고 최대 8단계 이내로 간결하게 작성할 것. 
8. 양념은 (소금, 설탕, 간장, 식용유, 참기름, 후추, 고춧가루, 된장, 고추장, 식초, 다진마늘, 마요네즈, 케첩, 밥, 물, 김치)만 추가할 것. 
9. 요리의 정체성을 유지하는 데 필요한 주재료(예: 고기, 해산물, 면 등)가 [냉장고 속 재료]에 존재하지 않는 경우, 역할이 유사한 대체 재료도 없다면 무리하게 레시피를 변형하지 말고 조건 12번을 따를 것. 
10. [냉장고 속 재료]나 [장바구니], 양념을 제외한 권장 재료는 재료와 조리법 사이에 '💡 OO를 추가하면 더욱 좋아요.' 형식으로 반드시 변형 레시피를 기준으로 팁 한 줄만 추가할 것. 
11. 레시피 형식은 반드시 설명, 인사말, 결론을 작성하지 않고 다음과 같이 작성할 것:
장바구니 재료는 [장바구니]에서 재료를 사용할때만, 보유 식재료에는 [냉장고 속 재료]에서 식재료를 사용할 때만 작성할것.
'
제목

재료
  [냉장고 재료]
  -
  -
  [장바구니 재료]
  -
  -
  [양념]
  -
  -
(팁)

조리법
'
12. [냉장고 속 재료]나 [장바구니] 재료가 너무 부족해 요리 성립이 어렵다고 판단되면 기존 레시피 형식을 무시하고 아래 형식으로만 답변할 것:
'현재 재료로는 레시피 변형이 어려워요. 
OO 재료를 더해주시면 훌륭한 요리가 될 것 같아요!'

[주어진 레시피 제목]
$recipeName
[주어진 레시피 재료]
$recipeIngredients
[주어진 레시피 조리법]
$manuals

$ownedSection$cartSection
''';
  }

  Future<void> _callGemini({bool forceRefresh = false}) async {
    if (_isGeminiLoading) return;
    if (kGeminiApiKey.isEmpty) {
      _showSnack('Gemini API 키가 설정되지 않았습니다');
      return;
    }

    // 모드별 재료 체크
    if (_currentMode == RecipeMode.fridge) {
      if (widget.ownedIngredients.isEmpty) {
        _showSnack('냉장고가 비어있어요. 먼저 식재료를 등록해주세요.');
        return;
      }
    } else if (_currentMode == RecipeMode.shopping) {
      final ownedEmpty = widget.ownedIngredients.isEmpty;
      final cartEmpty = widget.extraIngredients.isEmpty;

      if (ownedEmpty && cartEmpty) {
        _showSnack('냉장고와 장바구니가 모두 비어있어요.');
        return;
      } else if (cartEmpty) {
        _showSnack('장바구니가 비어있어요. 장보기에서 재료를 담아주세요.');
        return;
      }
    }
    // 캐시 확인 (forceRefresh이면 건너뜀)
    final cacheKey = _buildCacheKey();
    if (!forceRefresh) {
      final cached = _geminiCache.get(cacheKey);
      if (cached != null) {
        setState(() => _geminiResult = cached);
        debugPrint('Gemini 캐시 hit (size=${_geminiCache.size})');
        return;
      }
    }

    setState(() {
      _isGeminiLoading = true;
      _geminiResult = null;
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$kGeminiApiKey',
    );

    final prompt = _buildPrompt();

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'];
        if (candidates == null || candidates.isEmpty) {
          throw Exception('응답 없음');
        }
        final parts = candidates[0]['content']?['parts'];
        if (parts == null || parts.isEmpty) {
          throw Exception('parts 없음');
        }
        final text = parts[0]['text'];
        if (text == null || text.trim().isEmpty) {
          setState(() => _geminiResult = '추천 결과가 없습니다.');
          return;
        }
        if (!mounted) return;

        // 캐시 저장
        _geminiCache.put(cacheKey, text);
        setState(() => _geminiResult = text);
      } else {
        debugPrint('Gemini 실패: ${response.body}');
        _showSnack('AI 응답 오류가 발생했습니다');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showSnack('요청 시간이 초과되었습니다');
    } catch (e) {
      if (!mounted) return;
      _showSnack('AI 응답 오류가 발생했습니다');
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isGeminiLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.recipe['RCP_NM'] ?? '';
    final ingredients = widget.recipe['RCP_PARTS_DTLS'] ?? '';
    final imageUrl =
        (widget.recipe['ATT_FILE_NO_MAIN'] ??
                widget.recipe['MANUAL_IMG01'] ??
                '')
            .toString();
    final manuals = _getManuals();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              '출처: ${widget.recipe['source'] ?? ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '재료',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(ingredients, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 16),
            if (manuals.isNotEmpty) ...[
              const Text(
                '조리법',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...manuals.map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    step.replaceAll('\n', ' '),
                    style: const TextStyle(height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const SizedBox(height: 16),
            // 모드 토글 추가
            Row(
              children: [
                const Icon(Icons.tune, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  '변형 모드',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<RecipeMode>(
              segments: const [
                ButtonSegment(
                  value: RecipeMode.fridge,
                  label: Text('냉장고 재료만'),
                  icon: Icon(Icons.kitchen, size: 18),
                ),
                ButtonSegment(
                  value: RecipeMode.shopping,
                  label: Text('장바구니 포함'),
                  icon: Icon(Icons.shopping_cart, size: 18),
                ),
              ],
              selected: {_currentMode},
              onSelectionChanged: _isGeminiLoading
                  ? null
                  : (set) => _onModeChanged(set.first),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGeminiLoading
                    ? null
                    : () => _callGemini(forceRefresh: _geminiResult != null),
                icon: _isGeminiLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _geminiResult != null
                            ? Icons.refresh
                            : Icons.auto_awesome,
                      ),
                label: Text(
                  _isGeminiLoading
                      ? 'AI 변형 중...'
                      : (_geminiResult != null ? '다시 변형하기' : 'AI 맞춤 변형'),
                ),
              ),
            ),
            if (_geminiResult != null) ...[
              const SizedBox(height: 16),
              const Text(
                'AI 맞춤 레시피',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _geminiResult!,
                  style: const TextStyle(height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
