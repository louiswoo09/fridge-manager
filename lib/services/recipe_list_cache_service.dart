import '../models/recipe_mode.dart';

/// 레시피 추천 결과를 모드별로 메모리에 보관 (세션 캐시)
///
/// 같은 모드로 재진입 시 마지막 추천 결과 복원.
/// - 냉장고 모드: 필터(전체/임박)별 슬롯
/// - 검색 모드: 검색 기준(재료명/요리명)별 슬롯
/// 냉장고·담아놓기 결과는 활성 냉장고에 따라 달라지므로 전환 시 비움.
class RecipeListCacheService {
  static final RecipeListCacheService _instance = RecipeListCacheService._();
  factory RecipeListCacheService() => _instance;
  RecipeListCacheService._();

  final Map<String, _CachedResult> _slots = {};

  String _key(RecipeMode mode, FridgeFilter filter, SearchType? searchType) {
    if (mode == RecipeMode.fridge) return '${mode.name}|${filter.name}';
    if (mode == RecipeMode.search) {
      return '${mode.name}|${(searchType ?? SearchType.ingredient).name}';
    }
    return mode.name;
  }

  bool hasResult(RecipeMode mode, FridgeFilter filter, [SearchType? searchType]) =>
      _slots.containsKey(_key(mode, filter, searchType));

  List<Map<String, dynamic>> recipes(
    RecipeMode mode,
    FridgeFilter filter, [
    SearchType? searchType,
  ]) =>
      _slots[_key(mode, filter, searchType)]?.recipes ?? [];

  String searchedKeywords(
    RecipeMode mode,
    FridgeFilter filter, [
    SearchType? searchType,
  ]) =>
      _slots[_key(mode, filter, searchType)]?.searchedKeywords ?? '';

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

  /// 냉장고 재료·담아놓기에 의존하는 결과만 삭제 (검색 결과는 유지)
  void clearFridgeDependent() {
    _slots.removeWhere(
      (key, _) =>
          key.startsWith('${RecipeMode.fridge.name}|') ||
          key == RecipeMode.shopping.name,
    );
  }

  void clearAll() => _slots.clear();
}

class _CachedResult {
  final List<Map<String, dynamic>> recipes;
  final String searchedKeywords;
  _CachedResult({required this.recipes, required this.searchedKeywords});
}
