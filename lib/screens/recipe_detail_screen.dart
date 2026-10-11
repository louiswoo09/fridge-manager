import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/recipe_mode.dart';
import '../services/gemini_cache_service.dart';
import '../services/product_name_formatter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/favorite_service.dart';
import '../models/variant_recipe.dart';
import '../services/api_client.dart';

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
    _currentMode = _normalizeMode(last?.$1 ?? widget.mode);
    _fridgeFilter = last?.$2 ?? widget.fridgeFilter;

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
    _saveCurrentView(); // 추가: 토글 버튼으로 바꾼 모드도 기억
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

  /// 상세 화면은 냉장고/담아놓기 두 모드만 있음 → 그 외(검색 등)는 냉장고로
  RecipeMode _normalizeMode(RecipeMode mode) =>
      mode == RecipeMode.shopping ? RecipeMode.shopping : RecipeMode.fridge;

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

  Future<void> _callGemini({bool forceRefresh = false}) async {
    if (_isGeminiLoading) return;

    // 모드별 재료 체크 (기존 그대로)
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

    // 캐시 확인 (기존 그대로)
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

    List<String> clean(List<String> names) => names
        .map(ProductNameFormatter.toSearchKeyword)
        .where((n) => n.isNotEmpty)
        .toList();

    final body = jsonEncode({
      'recipe_name': widget.recipe['RCP_NM']?.toString() ?? '',
      'recipe_ingredients': widget.recipe['RCP_PARTS_DTLS']?.toString() ?? '',
      'manuals': _getManuals(),
      'owned': clean(widget.ownedIngredients),
      'cart': clean(widget.extraIngredients),
      'imminent': clean(widget.imminentIngredients),
      'mode': _currentMode == RecipeMode.shopping ? 'shopping' : 'fridge',
      'imminent_only':
          _currentMode == RecipeMode.fridge &&
          _fridgeFilter == FridgeFilter.imminent,
    });

    try {
      final response = await ApiClient.post(
        '/ai/recipe-variant',
        body,
        timeout: const Duration(seconds: 90),
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        _showSnack(
          response.statusCode == 504
              ? '요청 시간이 초과되었습니다'
              : 'AI 응답 오류 (코드 ${response.statusCode})',
        );
        return;
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final text = (data['text'] as String?) ?? '';

      if (text.trim().isEmpty) {
        setState(() => _setGeminiResult(null));
        _showSnack('추천 결과가 없습니다');
        return;
      }

      debugPrint('Gemini 응답:\n$text');
      _geminiCache.put(cacheKey, text);
      setState(() => _setGeminiResult(text));
    } catch (e) {
      _showSnack(friendlyError(e, fallback: 'AI 응답 오류가 발생했습니다'));
      debugPrint('레시피 변형 실패: $e');
    } finally {
      if (mounted) setState(() => _isGeminiLoading = false);
    }
  }

  /// 실제 소비기한 기준 임박 재료 (검색용 이름으로 정리)
  late final Set<String> _imminentNames = widget.imminentIngredients
      .map(ProductNameFormatter.toSearchKeyword)
      .where((n) => n.isNotEmpty)
      .toSet();

  /// AI가 정한 값이 아니라 실제 임박 목록으로 판단
  bool _isImminent(VariantIngredient ing) {
    return _imminentNames.any((n) => ing.name == n || ing.name.contains(n));
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
          // 레시피 주의점
          if (recipe.caution != null && recipe.caution!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildNoteLines(
                      recipe.caution!,
                      Colors.red.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 레시피 팁
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
                    child: _buildNoteLines(recipe.tip!, Colors.amber.shade700),
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
                      fontWeight: _isImminent(ing)
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _isImminent(ing)
                          ? Colors.red.shade700
                          : Colors.black87,
                    ),
                  ),
                  if (_isImminent(ing)) ...[
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

  /// 줄바꿈으로 나뉜 안내문을 번호 동그라미와 함께 표시
  /// 한 줄이면 번호 없이, AI가 혹시 붙인 "1." "-" "•" 등은 지우고 다시 매김
  Widget _buildNoteLines(String text, Color accent) {
    final lines = text
        .split('\n')
        .map(
          (l) => l.replaceFirst(RegExp(r'^\s*(\d+[.)]|[•\-])\s*'), '').trim(),
        )
        .where((l) => l.isNotEmpty)
        .toList();

    const style = TextStyle(fontSize: 13, height: 1.4);

    if (lines.length <= 1) {
      return Text(lines.isEmpty ? text : lines.first, style: style);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < lines.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 13,
                  child: Text(
                    '${i + 1}.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(lines[i], style: style)),
              ],
            ),
          ),
      ],
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
