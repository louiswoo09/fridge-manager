/// 레시피 추천/변형의 컨텍스트 모드
enum RecipeMode {
  /// 보유 식재료 (필터: 전체 또는 임박)
  fridge,

  /// 담아놓기에 담은 재료
  shopping,

  /// 자유 키워드 검색
  search,

  /// (2학기) 보유 + AI 자동 선택 할인 재료
  free,
}

/// 냉장고 모드 내 재료 필터
enum FridgeFilter {
  all,
  imminent,
}

enum SearchType {
  ingredient,  // 재료명
  recipeName,  // 요리명
}