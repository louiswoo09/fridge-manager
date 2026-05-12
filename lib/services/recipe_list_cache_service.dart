import '../models/recipe_mode.dart';

/// 레시피 추천 결과를 모드별로 메모리에 보관 (세션 캐시)
///
/// 같은 모드로 재진입 시 마지막 추천 결과 복원.
/// 모드별로 슬롯 분리되어 있어서 fridge/shopping 결과 섞이지 않음.
class RecipeListCacheService {
  static final RecipeListCacheService _instance = RecipeListCacheService._();
  factory RecipeListCacheService() => _instance;
  RecipeListCacheService._();

  final Map<String, _CachedResult> _slots = {};

  String _key(RecipeMode mode, FridgeFilter filter, [SearchType? searchType]) {
    if (mode == RecipeMode.fridge) {
      return '${mode.name}|${filter.name}';
    }
    if (mode == RecipeMode.search && searchType != null) {
      return '${mode.name}|${searchType.name}';
    }
    return mode.name;
  }

  bool hasResult(
    RecipeMode mode,
    FridgeFilter filter, [
    SearchType? searchType,
  ]) => _slots.containsKey(_key(mode, filter, searchType));

  List<Map<String, dynamic>> recipes(RecipeMode mode, FridgeFilter filter) =>
      _slots[_key(mode, filter)]?.recipes ?? [];

  String searchedKeywords(RecipeMode mode, FridgeFilter filter) =>
      _slots[_key(mode, filter)]?.searchedKeywords ?? '';

  void save({
    required RecipeMode mode,
    required FridgeFilter filter,
    SearchType? searchType,
    required List<Map<String, dynamic>> recipes,
    required String searchedKeywords,
  }) {
    _slots[_key(mode, filter, searchType)] = _CachedResult(
      recipes: recipes,
      searchedKeywords: searchedKeywords,
    );
  }

  void clear({required RecipeMode mode, required FridgeFilter filter}) =>
      _slots.remove(_key(mode, filter));
  void clearAll() => _slots.clear();
}

class _CachedResult {
  final List<Map<String, dynamic>> recipes;
  final String searchedKeywords;
  _CachedResult({required this.recipes, required this.searchedKeywords});
}
