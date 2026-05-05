import '../models/recipe_mode.dart';

/// 레시피 추천 결과를 모드별로 메모리에 보관 (세션 캐시)
/// 
/// 같은 모드로 재진입 시 마지막 추천 결과 복원.
/// 모드별로 슬롯 분리되어 있어서 fridge/shopping 결과 섞이지 않음.
class RecipeListCacheService {
  static final RecipeListCacheService _instance = RecipeListCacheService._();
  factory RecipeListCacheService() => _instance;
  RecipeListCacheService._();

  final Map<RecipeMode, _CachedResult> _slots = {};

  bool hasResult(RecipeMode mode) => _slots.containsKey(mode);

  List<Map<String, dynamic>> recipes(RecipeMode mode) =>
      _slots[mode]?.recipes ?? [];

  String searchedKeywords(RecipeMode mode) =>
      _slots[mode]?.searchedKeywords ?? '';

  void save({
    required RecipeMode mode,
    required List<Map<String, dynamic>> recipes,
    required String searchedKeywords,
  }) {
    _slots[mode] = _CachedResult(
      recipes: recipes,
      searchedKeywords: searchedKeywords,
    );
  }

  void clear(RecipeMode mode) => _slots.remove(mode);
  void clearAll() => _slots.clear();
}

class _CachedResult {
  final List<Map<String, dynamic>> recipes;
  final String searchedKeywords;
  _CachedResult({required this.recipes, required this.searchedKeywords});
}