import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/ingredient.dart';
import '../models/recipe_mode.dart';
import '../services/ingredient_service.dart';
import '../services/cart_service.dart';
import '../services/recipe_list_cache_service.dart';
import 'recipe_detail_screen.dart';
import '../services/product_name_formatter.dart';
import 'package:cached_network_image/cached_network_image.dart';

const String kFoodApiKey = String.fromEnvironment('FOOD_API_KEY');

class RecipeScreen extends StatefulWidget {
  final RecipeMode initialMode;

  const RecipeScreen({super.key, this.initialMode = RecipeMode.fridge});

  @override
  State<RecipeScreen> createState() => RecipeScreenState();
}

class RecipeScreenState extends State<RecipeScreen> {
  final IngredientService _service = IngredientService();
  final CartService _cartService = CartService();
  final RecipeListCacheService _listCache = RecipeListCacheService();

  static const int _imminentDaysThreshold = 3;
  Set<String> _selectedIngredientNames = {}; // 선택된 재료 이름
  bool _isRandomSelected = false;
  bool _isSelectionExpanded = true; // 재료 선택 영역 펼침/접기
  static const int _maxSelection = 3;
  static const int _maxSequentialSearches = 2;

  SearchType _searchType = SearchType.ingredient;
  String _searchKeyword = '';
  final TextEditingController _searchController = TextEditingController();

  late StreamSubscription<List<Ingredient>> _ingredientSub;
  StreamSubscription<List<String>>? _cartSub;

  late RecipeMode _currentMode;
  FridgeFilter _fridgeFilter = FridgeFilter.all;
  List<Ingredient> _items = [];
  List<String> _cartIngredientNames = [];

  List<Map<String, dynamic>> _recipes = [];
  bool _isLoading = true;
  bool _isFetching = false;
  bool _hasSearched = false;
  String _searchedKeywords = '';
  String? _resultFilterKeyword; // null = 전체 표시

  bool _isIgnored(String name) {
    const ignore = {'소금', '설탕', '후추', '기름', '간장'};
    return ignore.any((e) => name.contains(e));
  }

  /// 요리 스타일 키워드에서 노이즈 단어 제거
  /// 예: "국물 요리" → "국물", "한식 음식" → "한식"
  String _normalizeStyleKeyword(String raw) {
    var cleaned = raw.trim();
    const suffixes = ['요리', '음식', '레시피', '메뉴'];
    for (final suffix in suffixes) {
      if (cleaned.endsWith(' $suffix')) {
        cleaned = cleaned
            .substring(0, cleaned.length - suffix.length - 1)
            .trim();
      } else if (cleaned.endsWith(suffix) && cleaned.length > suffix.length) {
        cleaned = cleaned.substring(0, cleaned.length - suffix.length).trim();
      }
    }
    return cleaned;
  }

  /// D-3 이내 + 만료 안 된 재료 (가까운 순)
  List<Ingredient> get _imminentIngredients {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final threshold = today.add(const Duration(days: _imminentDaysThreshold));

    return _items.where((item) {
      if (_isIgnored(item.name.trim())) return false;
      final exp = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return !exp.isBefore(today) && !exp.isAfter(threshold);
    }).toList()..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
  }

  List<String> get _displayedIngredientNames {
    switch (_currentMode) {
      case RecipeMode.shopping:
        return _cartIngredientNames;
      case RecipeMode.fridge:
        final source = _fridgeFilter == FridgeFilter.imminent
            ? _imminentIngredients
            : _notExpiredItems;
        return source.map((e) => e.name).toList();
      case RecipeMode.search:
      case RecipeMode.free:
        return const [];
    }
  }

  int get _totalSelectedCount =>
      _selectedIngredientNames.length + (_isRandomSelected ? 1 : 0);

  void _toggleIngredient(String name) {
    setState(() {
      if (_selectedIngredientNames.contains(name)) {
        _selectedIngredientNames.remove(name);
      } else {
        // 2개 제한
        if (_totalSelectedCount >= _maxSelection) return;
        _selectedIngredientNames.add(name);
      }
    });
  }

  void _toggleRandom() {
    setState(() {
      if (_isRandomSelected) {
        _isRandomSelected = false;
      } else {
        if (_totalSelectedCount >= _maxSelection) return;
        _isRandomSelected = true;
      }
    });
  }

  void _syncSelection() {
    final displayed = _displayedIngredientNames.toSet();
    // 표시 안 되는 거 제거
    _selectedIngredientNames = _selectedIngredientNames.intersection(displayed);
    // 자동 선택 X (사용자가 명시적으로 선택해야 함)
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;

    _restoreCachedResult();

    _ingredientSub = _service.getIngredients().listen((items) {
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
        _syncSelection();
      });
    });

    _cartSub = _cartService.watchDisplayNames().listen((names) {
      if (!mounted) return;
      setState(() => _cartIngredientNames = names);
      _syncSelection();
    });
  }

  void _restoreCachedResult() {
    _resultFilterKeyword = null;
    if (_listCache.hasResult(_currentMode, _fridgeFilter)) {
      _recipes = _listCache.recipes(_currentMode, _fridgeFilter);
      _searchedKeywords = _listCache.searchedKeywords(
        _currentMode,
        _fridgeFilter,
      );
      _hasSearched = true;

      // 검색 모드면 키워드를 입력 필드에 복원
      if (_currentMode == RecipeMode.search) {
        _searchKeyword = _searchedKeywords;
        _searchController.text = _searchedKeywords;
      }
    } else {
      _recipes = [];
      _searchedKeywords = '';
      _hasSearched = false;

      if (_currentMode == RecipeMode.search) {
        _searchKeyword = '';
        _searchController.clear();
      }
    }
  }

  @override
  void dispose() {
    _ingredientSub.cancel();
    _cartSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onModeChanged(RecipeMode? mode) {
    if (mode == null) return;
    setMode(mode);
  }

  // 모드 바뀔 때 명시적으로 초기화
  void setMode(RecipeMode mode) {
    if (mode == _currentMode) return;
    setState(() {
      _currentMode = mode;
      _resultFilterKeyword = null;
      _syncSelection(); // 표시 안 되는 재료는 선택에서 빼기
      _restoreCachedResult();
    });
  }

  void _onFilterChanged(FridgeFilter? filter) {
    if (filter == null || filter == _fridgeFilter) return;
    setState(() {
      _fridgeFilter = filter;
      _resultFilterKeyword = null;
      _syncSelection();
      _restoreCachedResult();
    });
  }

  /// 재료명 기반 검색
  Future<List<Map<String, dynamic>>> _search(String keyword) async {
    final url = Uri.parse(
      'https://openapi.foodsafetykorea.go.kr/api/$kFoodApiKey/COOKRCP01/json/1/20/RCP_PARTS_DTLS=${Uri.encodeComponent(keyword)}',
    );

    debugPrint('검색 키워드: $keyword');

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final cook = data['COOKRCP01'];
    if (cook == null) return [];

    final rows = (cook['row'] as List?)?.cast<Map<String, dynamic>>();
    if (rows == null || rows.isEmpty) return [];

    return rows
        .map(
          (r) => {
            ...r,
            'source': '식품의약품안전처',
            'searched_keywords': [keyword],
          },
        )
        .toList();
  }

  /// 요리명 기반 검색 (RCP_NM)
  Future<List<Map<String, dynamic>>> _searchByName(String keyword) async {
    final url = Uri.parse(
      'https://openapi.foodsafetykorea.go.kr/api/$kFoodApiKey/COOKRCP01/json/1/20/RCP_NM=${Uri.encodeComponent(keyword)}',
    );

    debugPrint('요리명 검색: $keyword');

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final cook = data['COOKRCP01'];
    if (cook == null) return [];

    final rows = (cook['row'] as List?)?.cast<Map<String, dynamic>>();
    if (rows == null || rows.isEmpty) return [];

    return rows
        .map(
          (r) => {
            ...r,
            'source': '식품의약품안전처',
            'searched_keywords': [keyword],
          },
        )
        .toList();
  }

  void _addToUnique(
    Map<String, Map<String, dynamic>> unique,
    List<Map<String, dynamic>> results,
  ) {
    for (var r in results) {
      final name = r['RCP_NM'];
      if (name == null) continue;

      if (unique.containsKey(name)) {
        final existing = List<String>.from(
          unique[name]!['searched_keywords'] ?? [],
        );
        final newKeywords = List<String>.from(r['searched_keywords'] ?? []);
        for (final k in newKeywords) {
          if (!existing.contains(k)) existing.add(k);
        }
        unique[name] = {...unique[name]!, 'searched_keywords': existing};
      } else {
        unique[name] = r;
      }
    }
  }

  Future<void> _fetchSearchRecipes() async {
    if (_isFetching) return;

    if (kFoodApiKey.isEmpty) {
      _showSnack('API 키가 설정되지 않았습니다');
      return;
    }

    final raw = _searchKeyword.trim();
    if (raw.isEmpty) {
      _showSnack('검색어를 입력하세요');
      return;
    }

    // 쉼표로 분리 (있으면 다중 검색, 없으면 단일)
    final keywords = raw
        .split(',')
        .map((k) => _normalizeStyleKeyword(k))
        .where((k) => k.isNotEmpty)
        .toList();

    setState(() {
      _isFetching = true;
      _recipes = [];
      _hasSearched = false;
      _searchedKeywords = '';
    });

    try {
      final unique = <String, Map<String, dynamic>>{};

      // 각 키워드별 검색 (검색 타입에 따라 분기)
      for (final keyword in keywords) {
        final results = _searchType == SearchType.ingredient
            ? await _search(keyword)
            : await _searchByName(keyword);
        _addToUnique(unique, results);
      }

      if (!mounted) return;

      final finalRecipes = unique.values.toList();
      final finalKeywords = keywords.join(', ');

      _listCache.save(
        mode: _currentMode,
        filter: _fridgeFilter,
        searchType: _searchType,
        recipes: finalRecipes,
        searchedKeywords: finalKeywords,
      );

      setState(() {
        _recipes = finalRecipes;
        _hasSearched = true;
        _searchedKeywords = finalKeywords;
        _resultFilterKeyword = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('요청 시간이 초과되었습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('네트워크 오류가 발생했습니다');
      debugPrint('검색 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> _fetchRecipes() async {
    if (_isFetching) return;

    if (_currentMode == RecipeMode.search) {
      return _fetchSearchRecipes();
    }

    if (kFoodApiKey.isEmpty) {
      _showSnack('API 키가 설정되지 않았습니다');
      return;
    }

    // 후보 풀: 모드/필터에 따른 전체 재료 (랜덤 칩 채울 때 사용)
    final List<String> candidatePool;
    switch (_currentMode) {
      case RecipeMode.shopping:
        candidatePool = _cartIngredientNames
            .map((e) => ProductNameFormatter.toSearchKeyword(e.trim()))
            .where((name) => name.isNotEmpty && !_isIgnored(name))
            .toSet()
            .toList();
        break;
      case RecipeMode.fridge:
        final source = _fridgeFilter == FridgeFilter.imminent
            ? _imminentIngredients
            : _notExpiredItems;
        candidatePool = source
            .map((e) => ProductNameFormatter.toSearchKeyword(e.name.trim()))
            .where((name) => name.isNotEmpty && !_isIgnored(name))
            .toSet()
            .toList();
        break;
      case RecipeMode.search:
      case RecipeMode.free:
        candidatePool = [];
        break;
    }

    // 사용자가 명시적으로 선택한 키워드
    final explicitKeywords = _selectedIngredientNames
        .map((name) => ProductNameFormatter.toSearchKeyword(name.trim()))
        .where((k) => k.isNotEmpty && !_isIgnored(k))
        .toSet()
        .toList();

    // 빈 체크 — 명시 선택도 랜덤도 없으면 막음
    if (explicitKeywords.isEmpty && !_isRandomSelected) {
      _showSnack(
        _currentMode == RecipeMode.shopping ? '장바구니 재료를 선택하세요' : '재료를 선택하세요',
      );
      return;
    }

    // 최종 검색 키워드 결정
    List<String> ordered;
    if (_isRandomSelected) {
      // 랜덤 칩 선택됨: explicit + 랜덤으로 채움 (최대 _maxSelection 개)
      final fillCount = _maxSelection - explicitKeywords.length;

      if (_currentMode == RecipeMode.fridge &&
          _fridgeFilter == FridgeFilter.imminent) {
        // 임박 모드: 그룹핑 방식으로 채움
        final imminentOrdered = _orderImminentByDateGroups(candidatePool);
        final fill = imminentOrdered
            .where((k) => !explicitKeywords.contains(k))
            .take(fillCount)
            .toList();
        ordered = [...explicitKeywords, ...fill];
      } else {
        // 일반: 셔플로 채움
        final remaining =
            candidatePool.where((k) => !explicitKeywords.contains(k)).toList()
              ..shuffle();
        final fill = remaining.take(fillCount).toList();
        ordered = [...explicitKeywords, ...fill];
      }
    } else {
      // 랜덤 없음: 명시 선택만 사용
      ordered = List<String>.from(explicitKeywords);
    }

    if (ordered.isEmpty) {
      _showSnack('재료를 선택하세요');
      return;
    }

    final selected = ordered.take(min(_maxSelection, ordered.length)).toList();

    setState(() {
      _isFetching = true;
      _recipes = [];
      _hasSearched = false;
      _searchedKeywords = '';
    });

    try {
      final unique = <String, Map<String, dynamic>>{};
      final usedKeywords = <String>[];

      // 단일 검색
      for (final keyword in selected) {
        final results = await _search(keyword);
        _addToUnique(unique, results);
        if (results.isNotEmpty && !usedKeywords.contains(keyword)) {
          usedKeywords.add(keyword);
        }
      }

      // 순차 검색 — 시도한 키워드 추적
      final List<String> sequentialTried = [];
      if (_isRandomSelected && unique.length < 20) {
        final remaining =
            candidatePool.where((k) => !selected.contains(k)).toList()
              ..shuffle();

        int sequentialCount = 0;
        for (final keyword in remaining) {
          if (unique.length >= 30) break;
          if (sequentialCount >= _maxSequentialSearches) break;
          sequentialCount++;
          sequentialTried.add(keyword);
          final results = await _search(keyword);
          _addToUnique(unique, results);
          if (results.isNotEmpty && !usedKeywords.contains(keyword)) {
            usedKeywords.add(keyword);
          }
        }
      }

      // 최종 키워드 = selected + 순차 시도된 키워드
      final allTried = [...selected, ...sequentialTried];
      final finalKeywords = allTried.join(', ');

      if (!mounted) return;

      final allRecipes = unique.values.toList();
      allRecipes.shuffle();

      final finalRecipes = allRecipes.take(60).toList();

      _listCache.save(
        mode: _currentMode,
        filter: _fridgeFilter,
        recipes: finalRecipes,
        searchedKeywords: finalKeywords,
      );

      setState(() {
        _recipes = finalRecipes;
        _hasSearched = true;
        _searchedKeywords = finalKeywords;
        _resultFilterKeyword = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('요청 시간이 초과되었습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('네트워크 오류가 발생했습니다');
      debugPrint('레시피 불러오기 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  Future<void> searchByMultipleKeywords(List<String> keywords) async {
    final cleaned = keywords
        .map((k) => _normalizeStyleKeyword(k))
        .where((k) => k.isNotEmpty)
        .toList();

    if (cleaned.isEmpty) return;

    final keywordString = cleaned.join(', ');

    setState(() {
      _currentMode = RecipeMode.search;
      _searchType = SearchType.recipeName;
      _searchKeyword = keywordString;
      _searchController.text = keywordString;
    });

    await _fetchSearchRecipes();
  }

  List<Map<String, dynamic>> get _filteredRecipes {
    if (_resultFilterKeyword == null) return _recipes;
    return _recipes.where((r) {
      final keywords = (r['searched_keywords'] as List?)?.cast<String>() ?? [];
      return keywords.contains(_resultFilterKeyword);
    }).toList();
  }

  List<String> get _resultKeywords {
    // _searchedKeywords를 콤마로 분리
    return _searchedKeywords
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  bool get _showResultFilterChips {
    // 검색 완료 + 키워드 2개 이상이면 칩 표시
    return _hasSearched && _resultKeywords.length > 1 && _recipes.isNotEmpty;
  }

  bool get _canFetch {
    switch (_currentMode) {
      case RecipeMode.shopping:
      case RecipeMode.fridge:
        // 명시 선택 또는 랜덤 중 하나라도 있고, 후보 풀에 재료가 있어야 함
        final hasSelection =
            _selectedIngredientNames.isNotEmpty || _isRandomSelected;
        final hasIngredients = _displayedIngredientNames.isNotEmpty;
        return hasSelection && hasIngredients;
      case RecipeMode.search:
        return _searchKeyword.trim().isNotEmpty;
      case RecipeMode.free:
        return _notExpiredItems.isNotEmpty;
    }
  }

  bool get _showChipSection {
    if (_currentMode == RecipeMode.shopping) {
      return _cartIngredientNames.isNotEmpty; // 추가
    }
    if (_currentMode == RecipeMode.fridge) {
      // 전체 필터인데 보유 재료 없으면 숨김
      if (_fridgeFilter == FridgeFilter.all && _notExpiredItems.isEmpty) {
        return false;
      }
      // 임박 필터인데 임박 재료 없으면 숨김
      if (_fridgeFilter == FridgeFilter.imminent &&
          _imminentIngredients.isEmpty) {
        return false;
      }
      return true;
    }
    return false;
  }

  String get _emptyMessage {
    if (_hasSearched) {
      // 필터 켜서 0개면 다른 안내
      if (_resultFilterKeyword != null) {
        return '$_resultFilterKeyword 결과가 없습니다';
      }
      return '추천할 레시피가 없습니다';
    }
    // 빈 상태별 안내
    if (_currentMode == RecipeMode.shopping && _cartIngredientNames.isEmpty) {
      return '장바구니에 재료가 없어요';
    }
    if (_currentMode == RecipeMode.fridge) {
      if (_fridgeFilter == FridgeFilter.all && _notExpiredItems.isEmpty) {
        return '냉장고에 재료가 없어요';
      }
      if (_fridgeFilter == FridgeFilter.imminent &&
          _imminentIngredients.isEmpty) {
        return '$_imminentDaysThreshold일 이내 임박한 재료가 없어요';
      }
    }
    if (_currentMode == RecipeMode.search) {
      return '검색어를 입력해 레시피를 추천받으세요';
    }
    // 기본 — 검색 안 함 + 재료 있는 상태
    return '식재료를 선택해 레시피를 추천받으세요';
  }

  /// 임박 모드에서 같은 D-day끼리 그룹핑 + 그룹 내 셔플
  List<String> _orderImminentByDateGroups(List<String> candidatePool) {
    final groups = <DateTime, List<String>>{};
    for (final item in _imminentIngredients) {
      final keyword = ProductNameFormatter.toSearchKeyword(item.name.trim());
      if (keyword.isEmpty || _isIgnored(keyword)) continue;
      if (!candidatePool.contains(keyword)) continue;
      final dateKey = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      groups.putIfAbsent(dateKey, () => []).add(keyword);
    }
    final sortedDates = groups.keys.toList()..sort();
    final expanded = <String>[];
    for (final date in sortedDates) {
      final shuffledGroup = List<String>.from(groups[date]!)..shuffle();
      expanded.addAll(shuffledGroup);
    }
    final seen = <String>{};
    expanded.retainWhere((k) => seen.add(k));
    return expanded;
  }

  List<Ingredient> get _notExpiredItems {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _items.where((item) {
      final exp = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return !exp.isBefore(today);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_currentMode) {
          RecipeMode.shopping => '장바구니 레시피 추천',
          RecipeMode.search => '레시피 검색',
          RecipeMode.fridge =>
            _fridgeFilter == FridgeFilter.imminent ? '레시피 추천 (임박)' : '레시피 추천',
          _ => '레시피 추천',
        }),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 모드 선택 토글
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SegmentedButton<RecipeMode>(
                    segments: const [
                      ButtonSegment(
                        value: RecipeMode.fridge,
                        label: Text('냉장고'),
                        icon: Icon(Icons.kitchen),
                      ),
                      ButtonSegment(
                        value: RecipeMode.shopping,
                        label: Text('장바구니'),
                        icon: Icon(Icons.shopping_cart),
                      ),
                      ButtonSegment(
                        value: RecipeMode.search,
                        label: Text('검색'),
                        icon: Icon(Icons.search),
                      ),
                    ],
                    selected: {_currentMode},
                    onSelectionChanged: (set) => _onModeChanged(set.first),
                  ),
                ),
                if (_currentMode == RecipeMode.fridge)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
                    child: Row(
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
                          onChanged: _onFilterChanged,
                        ),
                      ],
                    ),
                  ),
                // 칩 리스트 (냉장고/장바구니 모드만)
                if (_showChipSection) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 헤더: 클릭하면 펼침/접힘
                        InkWell(
                          onTap: () => setState(
                            () => _isSelectionExpanded = !_isSelectionExpanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  '재료 선택 ($_totalSelectedCount/$_maxSelection)',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _isSelectionExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                                const Spacer(),
                                if (_totalSelectedCount > 0)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _selectedIngredientNames.clear();
                                      _isRandomSelected = false;
                                    }),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(0, 28),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    child: const Text(
                                      '해제',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // 펼쳤을 때만 칩 표시
                        if (_isSelectionExpanded) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              // 랜덤 칩 (맨 앞)
                              FilterChip(
                                label: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shuffle, size: 14),
                                    SizedBox(width: 4),
                                    Text('랜덤', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                                selected: _isRandomSelected,
                                onSelected: (_) => _toggleRandom(),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              // 일반 재료 칩
                              ..._displayedIngredientNames.map((name) {
                                final selected = _selectedIngredientNames
                                    .contains(name);
                                return FilterChip(
                                  label: Text(
                                    name,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  selected: selected,
                                  onSelected: (_) => _toggleIngredient(name),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 8), // 칩과 버튼 사이 여백
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (_isFetching || !_canFetch)
                                  ? null
                                  : () {
                                      setState(
                                        () => _isSelectionExpanded = false,
                                      ); // 자동 접힘
                                      _fetchRecipes();
                                    },
                              child: const Text('레시피 추천 받기'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (_currentMode == RecipeMode.search) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 검색 타입 토글
                        Row(
                          children: [
                            const Text(
                              '검색 기준: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                            DropdownButton<SearchType>(
                              value: _searchType,
                              underline: const SizedBox.shrink(),
                              items: const [
                                DropdownMenuItem(
                                  value: SearchType.ingredient,
                                  child: Text(
                                    '재료명',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: SearchType.recipeName,
                                  child: Text(
                                    '요리명',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null || value == _searchType) {
                                  return;
                                }
                                setState(() {
                                  _searchType = value;
                                  // 타입 바뀌면 결과 비움 (다른 검색이니까)
                                  _recipes = [];
                                  _hasSearched = false;
                                  _searchedKeywords = '';
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: _searchType == SearchType.ingredient
                                ? '재료명 입력'
                                : '요리명 입력',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: const Color.fromARGB(15, 158, 158, 158),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _searchKeyword = v),
                          onSubmitted: (_) {
                            if (_canFetch && !_isFetching) {
                              _fetchSearchRecipes();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_isFetching || !_canFetch)
                                ? null
                                : _fetchSearchRecipes,
                            child: const Text('검색'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_hasSearched && _searchedKeywords.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '"$_searchedKeywords" 로 검색된 레시피',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                // 결과 필터 칩
                if (_showResultFilterChips)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // "전체" 칩
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text('전체 (${_recipes.length})'),
                              selected: _resultFilterKeyword == null,
                              onSelected: (_) =>
                                  setState(() => _resultFilterKeyword = null),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          // 키워드별 칩
                          ..._resultKeywords.map((keyword) {
                            final count = _recipes.where((r) {
                              final ks =
                                  (r['searched_keywords'] as List?)
                                      ?.cast<String>() ??
                                  [];
                              return ks.contains(keyword);
                            }).length;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text('$keyword ($count)'),
                                selected: _resultFilterKeyword == keyword,
                                onSelected: count == 0
                                    ? null
                                    : (_) => setState(() {
                                        _resultFilterKeyword =
                                            _resultFilterKeyword == keyword
                                            ? null
                                            : keyword;
                                      }),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _isFetching
                      ? const Center(child: CircularProgressIndicator())
                      : _filteredRecipes
                            .isEmpty // _recipes → _filteredRecipes
                      ? Center(child: Text(_emptyMessage))
                      : ListView.builder(
                          itemCount: _filteredRecipes.length,
                          itemBuilder: (context, index) {
                            final recipe = _filteredRecipes[index];
                            final imageUrl =
                                (recipe['ATT_FILE_NO_MAIN'] ??
                                        recipe['MANUAL_IMG01'] ??
                                        '')
                                    .toString();
                            final name = recipe['RCP_NM'] ?? '';
                            final keywords =
                                (recipe['searched_keywords'] as List?)?.join(
                                  ', ',
                                ) ??
                                '';

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                leading: imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: CachedNetworkImage(
                                          imageUrl: imageUrl,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 120,
                                          memCacheHeight: 120,
                                          placeholder: (context, url) =>
                                              Container(
                                                width: 60,
                                                height: 60,
                                                color: Colors.grey.shade200,
                                              ),
                                          errorWidget: (context, url, error) {
                                            debugPrint('이미지 에러: $url, $error');
                                            return const Icon(
                                              Icons.restaurant,
                                              size: 40,
                                            );
                                          },
                                        ),
                                      )
                                    : const Icon(Icons.restaurant, size: 40),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '"$keywords" 포함 레시피',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  final imminentNames = _imminentIngredients
                                      .map((e) => e.name)
                                      .toList();

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailScreen(
                                        recipe: recipe,
                                        ownedIngredients: _notExpiredItems
                                            .map((e) => e.name)
                                            .toList(), // _items → _notExpiredItems
                                        extraIngredients: _cartIngredientNames,
                                        imminentIngredients: imminentNames,
                                        mode: _currentMode,
                                        fridgeFilter: _fridgeFilter,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
