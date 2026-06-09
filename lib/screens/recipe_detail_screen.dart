import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/recipe_mode.dart';
import '../services/gemini_cache_service.dart';
import '../services/product_name_formatter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/favorite_service.dart';
import '../models/variant_recipe.dart';

const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final List<String> ownedIngredients;
  final List<String> extraIngredients;
  final List<String> imminentIngredients;
  final RecipeMode mode;
  final FridgeFilter fridgeFilter;
  final String? initialAiResult;
  final bool fromFavorite;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.ownedIngredients,
    this.extraIngredients = const [],
    this.imminentIngredients = const [],
    this.mode = RecipeMode.fridge,
    this.fridgeFilter = FridgeFilter.all,
    this.initialAiResult,
    this.fromFavorite = false,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  static final Map<String, (RecipeMode, FridgeFilter)> _lastViewByRecipe = {};
  bool _isGeminiLoading = false;
  String? _geminiResult;
  VariantRecipe? _variantRecipe;
  final GeminiCacheService _geminiCache = GeminiCacheService();
  late RecipeMode _currentMode;
  late FridgeFilter _fridgeFilter;
  final FavoriteService _favoriteService = FavoriteService();
  Set<String> _favoriteKeys = {};
  StreamSubscription<Set<String>>? _favoriteSubscription;
  late final String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

    final recipeId =
        widget.recipe['RCP_SEQ']?.toString() ??
        widget.recipe['RCP_NM']?.toString() ??
        '';

    final last = _lastViewByRecipe[recipeId];
    if (last != null) {
      _currentMode = last.$1;
      _fridgeFilter = last.$2;
    } else {
      _currentMode = widget.mode;
      _fridgeFilter = widget.fridgeFilter;
    }

    _favoriteSubscription = _favoriteService.watchFavoriteKeys().listen((keys) {
      if (!mounted) return;
      setState(() => _favoriteKeys = keys);
    });

    if (widget.initialAiResult != null) {
      // 변형 즐겨찾기 진입 — 저장된 결과 표시
      _setGeminiResult(widget.initialAiResult);
      _geminiCache.put(_buildCacheKey(), widget.initialAiResult!);
    } else {
      // 일반 진입 — 캐시 복원
      _restoreCachedResult();
    }
  }

  @override
  void dispose() {
    _favoriteSubscription?.cancel();
    super.dispose();
  }

  void _restoreCachedResult() {
    final cached = _geminiCache.get(_buildCacheKey());
    _setGeminiResult(cached);
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

  void _onFilterChanged(FridgeFilter? filter) {
    if (filter == null || filter == _fridgeFilter) return;
    setState(() {
      _fridgeFilter = filter;
      _restoreCachedResult();
    });
    _saveCurrentView();
  }

  void setMode(RecipeMode mode) {
    if (mode == _currentMode) return;
    setState(() {
      _currentMode = mode;
      _restoreCachedResult();
    });
    _saveCurrentView();
  }

  void _saveCurrentView() {
    final recipeId =
        widget.recipe['RCP_SEQ']?.toString() ??
        widget.recipe['RCP_NM']?.toString() ??
        '';
    _lastViewByRecipe[recipeId] = (_currentMode, _fridgeFilter);
  }

  void _setGeminiResult(String? text) {
    _geminiResult = text;
    _variantRecipe = _parseVariantRecipe(text);
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

    final filterPart =
        (_currentMode == RecipeMode.fridge &&
            _fridgeFilter == FridgeFilter.imminent)
        ? '|imminent'
        : '';

    // 즐겨찾기 진입은 세션별 격리
    final favoritePart = widget.fromFavorite ? '|fav_$_sessionId' : '';

    return '${_currentMode.name}|$recipeId$filterPart$favoritePart';
  }

  String get _recipeId =>
      widget.recipe['RCP_SEQ']?.toString() ??
      widget.recipe['RCP_NM']?.toString() ??
      '';

  bool get _isOriginalFavorited {
    return _favoriteService.contains(_favoriteKeys, recipeId: _recipeId);
  }

  bool get _hasAnyVariantFavorited {
    return _favoriteKeys.any((key) => key.startsWith('variant_${_recipeId}_'));
  }

  bool get _isVariantFavorited {
    if (_geminiResult == null) return false;
    return _favoriteService.contains(
      _favoriteKeys,
      recipeId: _recipeId,
      aiResult: _geminiResult,
    );
  }

  Future<void> _toggleOriginalFavorite() async {
    final recipeName = widget.recipe['RCP_NM']?.toString() ?? '';
    if (_recipeId.isEmpty) return;

    if (_isOriginalFavorited) {
      await _favoriteService.remove(recipeId: _recipeId);
      _showSnack('$recipeName 즐겨찾기 해제');
    } else {
      await _favoriteService.add(
        recipeId: _recipeId,
        recipeName: recipeName,
        recipeData: widget.recipe,
      );
      _showSnack('$recipeName 즐겨찾기 추가');
    }
  }

  Future<void> _toggleVariantFavorite() async {
    if (_geminiResult == null) return;
    final recipeName = widget.recipe['RCP_NM']?.toString() ?? '';
    if (_recipeId.isEmpty) return;

    if (_isVariantFavorited) {
      await _favoriteService.remove(
        recipeId: _recipeId,
        aiResult: _geminiResult,
      );
      _showSnack('즐겨찾기 해제');
    } else {
      // 원본 + 변형 한 번에 추가
      await _favoriteService.addVariantWithOriginal(
        recipeId: _recipeId,
        recipeName: recipeName,
        recipeData: widget.recipe,
        aiResult: _geminiResult!,
        mode: _currentMode,
        fridgeFilter: _fridgeFilter,
      );
      _showSnack('즐겨찾기 추가');
    }
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

    final cleanedImminent = widget.imminentIngredients
        .map(ProductNameFormatter.toSearchKeyword)
        .where((name) => name.isNotEmpty)
        .toList();

    // 냉장고 섹션 — 비어있을 때 명시적으로 표시
    final ownedSection = cleanedOwned.isEmpty
        ? '[냉장고 속 재료]\n(없음)'
        : '''
[냉장고 속 재료]
${cleanedOwned.join(', ')}''';

    // 담아놓기 섹션 — shopping 모드 + 비어있지 않을 때만 추가
    final cartSection =
        (_currentMode == RecipeMode.shopping && cleanedExtra.isNotEmpty)
        ? '''

[담아놓기]
${cleanedExtra.join(', ')}

위 두 목록의 재료를 모두 사용 가능한 것으로 간주하되, [담아놓기] 재료는 사용자가 일부러 선택한 재료이므로 가능하면 적극적으로 활용해줘.'''
        : '';

    // 임박 재료 섹션 — imminent 모드 + 비어있지 않을 때만 추가
    final imminentSection =
        (_currentMode == RecipeMode.fridge &&
            _fridgeFilter == FridgeFilter.imminent &&
            cleanedImminent.isNotEmpty)
        ? '''

[임박 재료 - 반드시 사용]
${cleanedImminent.join(', ')}

위 재료들은 유통기한이 임박해서 반드시 우선 활용해야 해. 가능한 한 [임박 재료]를 메인 재료로 사용하고, 부족한 부분은 [냉장고 속 재료]에서 보충해줘. 
[임박 재료]에 해당하는 재료는 응답 JSON에서 imminent 필드를 true로 설정해줘.'''
        : '';

    return '''
너는 TV 예능 프로그램 '냉장고를 부탁해'에 출연한 요리 연구가 '젬 쉐프'야. 
이번 프로그램의 주제는 '[주어진 레시피]를 바탕으로 [냉장고 속 재료] 혹은 [담아놓기] 재료만으로 조리가 가능하도록 레시피를 변형시켜라!'야.
레시피에 사용하는 재료는 주어진 양념 외에는 반드시 [냉장고 속 재료] 혹은 [담아놓기]에 포함된 것만 사용해야해.
그러므로 [주어진 레시피]의 재료 중 [냉장고 속 재료]나 [담아놓기]에 없는 것은 제거하거나, [냉장고 속 재료] 혹은 [담아놓기] 내에서 재료의 종류와 역할이 유사한 경우에 대체해서 만들어야해. 소스나 양념류는 양념에서 대체해줘.
변형시킨 레시피가 [주어진 레시피]와 요리 유형(한식/중식/일식/양식 등), 형식(국/볶음/구이/샐러드 등), 메인 재료(고기/해산물/채소/과일/면 등)이 동일할 수록 높은 평가를 받을거야. 
물론 변형 레시피가 [주어진 레시피]와 다르더라도 재료 상황에 맞게 자연스럽게 변형하는게 더욱 중요해. 상식에서 벗어난 이상한 레시피는 매우 낮은 평가를 받을거라는걸 꼭 기억해줘.
조리법을 직관적이면서 먹음직스럽게 작성하면 더욱 좋은 평가를 받을지도 몰라.
출연진에게 최고로 높은 평가를 받을 수 있도록 노력하자! 

레시피 작성 조건: 
1. 한국어로 작성할 것. 
2. 요리 제목(title)은 사용 재료를 나열하지 않고 레시피에 사용할 주재료만 포함하여 자연스럽게 새로 작성할 것. 
3. 재료(ingredients)의 amount는 분수("1/2") 또는 정수/소수 형태로, unit은 "개", "g", "ml", "스푼", "캔" 등의 명확한 단위로 작성. "약간"같이 정량 어려운 경우만 amount="약간", unit=""로 작성할것.
4. 양념을 제외한 변형된 레시피의 재료 목록에 없는 재료는 요리 제목이나 조리법에 작성하지 말것.
5. 현실에 존재하지 않는 가상의 재료나 손질하는데 전문 자격이 필요한 위험한 재료(복어, 독버섯, 야생동물 고기 등)는 [냉장고 속 재료]나 [담아놓기]에 있더라도 절대 사용하지 말것.
6. 일부 재료(팽이버섯, 은행, 고사리 등)가 독성 또는 위해성을 가질 수 있는 경우, 안전하게 섭취할 수 있는 올바른 조리법을 반드시 포함해서 작성할것.
7. 조리법(steps)은 최대 8단계 이내로 작성. 각 단계는 다음을 포함할 것:
   - instruction: 구체적인 동작과 시간을 포함한 설명을 작성. 재료를 삶거나 끓이는 등 조리 시간을 정확히 지정해서 작성하는 경우에만 시간을 포함할 것. 예: "양파를 잘게 썬 후 중불에서 2분간 볶는다". 
   - ingredients_used: 그 단계에서 사용하는 재료명 리스트.
   - time_seconds: instruction에 명시한 시간을 초 단위로 (예: 2분 = 120). 시간 없으면 null을 작성할 것.
   instruction에는 화력(중불/약불/강불), 익힘 정도, 색깔 변화 등 구체적 정보를 가능한 포함해 작성할 것.
8. 양념(seasoning)은 다음 양념만 추가할것: 소금, 설탕, 간장, 식용유, 참기름, 후추, 고춧가루, 된장, 고추장, 식초, 다진마늘, 마요네즈, 케첩, 밥, 물, 김치.
9. 요리의 정체성을 유지하는 데 필요한 주재료(예: 고기, 해산물, 면 등)가 [냉장고 속 재료]에 존재하지 않는 경우, 역할이 유사한 대체 재료도 없다면 무리하게 레시피를 변형하지 말고 insufficient를 true로 설정하고 다른 필드는 비운채 tip 필드에 "OO 재료를 더해주시면 훌륭한 요리가 될 것 같아요!" 메시지를 적을것. 
10. [냉장고 속 재료]나 [담아놓기], 양념을 제외한 권장 재료는 tip 필드에 반드시 원본 레시피가 아닌 변형 레시피를 기준으로 팁을 작성할 것. 
11. servings는 기본 1인분 기준으로 작성.
12. 응답은 반드시 아래 스키마의 JSON으로만 작성. 마크다운 ```json 감싸지 말고 순수 JSON만 출력. 설명, 인사말, 결론 일체 작성하지 말 것.

JSON 스키마:
{
  "title": "string",
  "servings": "integer",
  "ingredients": {
    "fridge": [{"name": "string", "amount": "string", "unit": "string", "imminent": "boolean"}],
    "cart": [{"name": "string", "amount": "string", "unit": "string", "imminent": "boolean"}],
    "seasoning": [{"name": "string", "amount": "string", "unit": "string"}]
  },
  "tip": "string or null",
  "steps": [
    {"order": "integer", "instruction": "string", "ingredients_used": ["string"], "time_seconds": "integer or null"}
  ],
  "insufficient": "boolean"
}

[주어진 레시피 제목]
$recipeName
[주어진 레시피 재료]
$recipeIngredients
[주어진 레시피 조리법]
$manuals

$ownedSection$cartSection$imminentSection
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
      if (_fridgeFilter == FridgeFilter.imminent &&
          widget.imminentIngredients.isEmpty) {
        _showSnack('3일 이내 임박한 재료가 없어요');
        return;
      }
    } else if (_currentMode == RecipeMode.shopping) {
      final ownedEmpty = widget.ownedIngredients.isEmpty;
      final cartEmpty = widget.extraIngredients.isEmpty;

      if (ownedEmpty && cartEmpty) {
        _showSnack('냉장고와 담아놓기가 모두 비어있어요.');
        return;
      } else if (cartEmpty) {
        _showSnack('담아놓기가 비어있어요. 장보기에서 재료를 담아주세요.');
        return;
      }
    }
    // 캐시 확인 (forceRefresh이면 건너뜀)
    final cacheKey = _buildCacheKey();
    if (!forceRefresh) {
      final cached = _geminiCache.get(cacheKey);
      if (cached != null) {
        setState(() => _setGeminiResult(cached));
        debugPrint('Gemini 캐시 hit (size=${_geminiCache.size})');
        return;
      }
    }

    setState(() {
      _isGeminiLoading = true;
      _setGeminiResult(null);
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=$kGeminiApiKey',
    );

    final prompt = _buildPrompt();
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
      "generationConfig": {"responseMimeType": "application/json"},
    });

    try {
      int? errorCode;
      String? errorDetail;
      const maxAttempts = 3;
      const delays = [Duration(seconds: 1), Duration(seconds: 3)];

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          final response = await http
              .post(
                url,
                headers: {'Content-Type': 'application/json'},
                body: body,
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
              if (mounted) {
                setState(() {
                  _geminiResult = null;
                  _variantRecipe = null;
                });
                _showSnack('추천 결과가 없습니다');
              }
              return;
            }

            debugPrint('Gemini 응답:\n$text');

            // 파싱 테스트
            try {
              final json = jsonDecode(text);
              final recipe = VariantRecipe.fromJson(
                json as Map<String, dynamic>,
              );
              debugPrint(
                '파싱 성공: ${recipe.title}, 재료 ${recipe.fridgeIngredients.length}개',
              );
            } catch (e) {
              debugPrint('파싱 실패: $e');
            }

            if (!mounted) return;
            _geminiCache.put(cacheKey, text);
            setState(() => _setGeminiResult(text));
            return;
          }

          errorCode = response.statusCode;
          debugPrint(
            'Gemini 실패 (status=$errorCode, attempt=${attempt + 1}): ${response.body}',
          );

          // 5xx 또는 429만 재시도
          final shouldRetry =
              (errorCode >= 500 || errorCode == 429) &&
              attempt < maxAttempts - 1;
          if (!shouldRetry) break;
          await Future.delayed(delays[attempt]);
        } on TimeoutException {
          errorDetail = 'timeout';
          debugPrint('Gemini timeout (attempt=${attempt + 1})');
          if (attempt < maxAttempts - 1) {
            await Future.delayed(delays[attempt]);
            continue;
          }
          break;
        }
      }

      // 모든 시도 실패
      if (!mounted) return;
      final msg = errorDetail == 'timeout'
          ? '요청 시간이 초과되었습니다'
          : (errorCode != null
                ? 'AI 응답 오류 (코드 $errorCode)'
                : 'AI 응답 오류가 발생했습니다');
      _showSnack(msg);
    } catch (e) {
      if (!mounted) return;
      _showSnack('AI 응답 오류가 발생했습니다');
      debugPrint('Gemini 예외: $e');
    } finally {
      if (mounted) {
        setState(() => _isGeminiLoading = false);
      }
    }
  }

  String? _findAmountForName(String name) {
    final recipe = _variantRecipe;
    if (recipe == null) return null;

    final all = [
      ...recipe.fridgeIngredients,
      ...recipe.cartIngredients,
      ...recipe.seasoning,
    ];

    for (final ing in all) {
      if (ing.name == name) {
        return ing.unit.isEmpty ? ing.amount : '${ing.amount}${ing.unit}';
      }
    }
    return null;
  }

  VariantRecipe? _parseVariantRecipe(String? jsonText) {
    if (jsonText == null || jsonText.trim().isEmpty) return null;
    try {
      final json = jsonDecode(jsonText);
      return VariantRecipe.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      debugPrint('변형 레시피 파싱 실패: $e');
      return null;
    }
  }

  Widget _buildVariantCard() {
    final recipe = _variantRecipe;

    // 파싱 실패한 경우 fallback (옛 형식 + JSON 형식 실패 둘 다)
    if (recipe == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          _geminiResult ?? '',
          style: const TextStyle(height: 1.6),
        ),
      );
    }

    // 재료 부족
    if (recipe.insufficient) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                recipe.tip ?? '재료가 부족해 변형이 어려워요.',
                style: const TextStyle(height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Text(
            recipe.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${recipe.servings}인분 기준',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // 재료
          const Text(
            '재료',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (recipe.fridgeIngredients.isNotEmpty)
            _buildIngredientSection('냉장고 재료', recipe.fridgeIngredients),
          if (recipe.cartIngredients.isNotEmpty)
            _buildIngredientSection('장바구니 재료', recipe.cartIngredients),
          if (recipe.seasoning.isNotEmpty)
            _buildIngredientSection('양념', recipe.seasoning),

          // 팁
          if (recipe.tip != null && recipe.tip!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recipe.tip!,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // 조리법
          const Text(
            '조리법',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...recipe.steps.map(_buildStepCard),
        ],
      ),
    );
  }

  Widget _buildIngredientSection(String label, List<VariantIngredient> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade900,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map((ing) {
            final amountText = ing.unit.isEmpty
                ? ing.amount
                : '${ing.amount}${ing.unit}';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text(
                    '• ${ing.name}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: ing.imminent
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: ing.imminent
                          ? Colors.red.shade700
                          : Colors.black87,
                    ),
                  ),
                  if (ing.imminent) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '임박',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    amountText,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStepCard(VariantStep step) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 번호 + 시간
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.indigo,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${step.order}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (step.timeSeconds != null) ...[
                  const Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(step.timeSeconds!),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // 설명
            Text(
              step.instruction,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            // 사용 재료 칩
            if (step.ingredientsUsed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: step.ingredientsUsed.map((name) {
                  final amount = _findAmountForName(name);
                  final label = amount != null ? '$name $amount' : name;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.indigo.shade700,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds초';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (s == 0) return '$m분';
    return '$m분 $s초';
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
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (!_hasAnyVariantFavorited)
            IconButton(
              icon: Icon(
                _isOriginalFavorited ? Icons.star : Icons.star_border,
                color: _isOriginalFavorited ? Colors.amber : null,
              ),
              tooltip: _isOriginalFavorited ? '즐겨찾기 해제' : '즐겨찾기 추가',
              onPressed: _toggleOriginalFavorite,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.contain, // cover → contain
                  placeholder: (context, url) =>
                      Container(height: 250, color: Colors.grey.shade200),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
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
                  'AI 변형',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            // 변형 모드 토글
            SegmentedButton<RecipeMode>(
              segments: const [
                ButtonSegment(
                  value: RecipeMode.fridge,
                  label: Text('냉장고 재료만'),
                  icon: Icon(Icons.kitchen, size: 18),
                ),
                ButtonSegment(
                  value: RecipeMode.shopping,
                  label: Text('담아놓기 포함'),
                  icon: Icon(Icons.shopping_cart, size: 18),
                ),
              ],
              selected: {_currentMode},
              onSelectionChanged: _isGeminiLoading
                  ? null
                  : (set) => _onModeChanged(set.first),
            ),

            // 냉장고 모드일 때만 필터 드롭다운
            if (_currentMode == RecipeMode.fridge) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    '모드: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                      fontSize: 16,
                    ),
                  ),
                  DropdownButton<FridgeFilter>(
                    value: _fridgeFilter,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: FridgeFilter.all,
                        child: Text(
                          '냉장고 전체',
                          style: TextStyle(fontWeight: FontWeight.w300),
                        ),
                      ),
                      DropdownMenuItem(
                        value: FridgeFilter.imminent,
                        child: Text(
                          '임박 우선',
                          style: TextStyle(fontWeight: FontWeight.w300),
                        ),
                      ),
                    ],
                    onChanged: _isGeminiLoading ? null : _onFilterChanged,
                  ),
                ],
              ),
            ],
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
              Row(
                children: [
                  const Text(
                    'AI 맞춤 레시피',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _isVariantFavorited ? Icons.star : Icons.star_border,
                      color: _isVariantFavorited ? Colors.amber : null,
                    ),
                    tooltip: _isVariantFavorited ? '즐겨찾기 해제' : '즐겨찾기 추가',
                    visualDensity: VisualDensity.compact,
                    onPressed: _toggleVariantFavorite,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildVariantCard(),
            ],
          ],
        ),
      ),
    );
  }
}
