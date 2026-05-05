import 'dart:collection';

/// Gemini 변형 결과를 메모리에 캐시 (LRU)
/// 
/// 같은 (레시피 + 보유재료 + 장바구니재료 + 모드) 조합으로 다시 변형 요청하면
/// 캐시된 결과 반환. 앱 재시작하면 사라짐 (세션 캐시).
class GeminiCacheService {
  static final GeminiCacheService _instance = GeminiCacheService._();
  factory GeminiCacheService() => _instance;
  GeminiCacheService._();

  static const int _maxEntries = 30;

  // LinkedHashMap은 삽입 순서 유지 → LRU 구현에 사용
  final LinkedHashMap<String, String> _cache = LinkedHashMap();

  /// 캐시 조회. hit이면 LRU 갱신(최근 사용으로 이동)하고 반환.
  String? get(String key) {
    if (!_cache.containsKey(key)) return null;
    
    // LRU: 조회한 항목을 맨 뒤로 옮김 (최근 사용)
    final value = _cache.remove(key)!;
    _cache[key] = value;
    return value;
  }

  /// 캐시 저장. 용량 초과 시 가장 오래된 항목 제거.
  void put(String key, String value) {
    // 이미 있으면 제거 후 다시 넣음 (순서 갱신)
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= _maxEntries) {
      // 가장 오래된 항목 제거 (LinkedHashMap의 첫 번째 키)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// 캐시 초기화 (디버그/테스트용)
  void clear() => _cache.clear();

  /// 현재 캐시 크기 (디버그용)
  int get size => _cache.length;
}