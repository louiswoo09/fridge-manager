import 'dart:convert';
import 'package:http/http.dart' as http;
import 'product_name_formatter.dart';
import '../config/api_config.dart';

class KamisCacheService {
  static final KamisCacheService _instance = KamisCacheService._();
  factory KamisCacheService() => _instance;
  KamisCacheService._();

  static const Duration _cacheTtl = Duration(minutes: 30);

  List<Map<String, dynamic>>? _cachedItems;
  DateTime? _fetchedAt;
  Future<List<Map<String, dynamic>>>? _inflightRequest;

  /// 일별 도소매 가격 리스트 가져오기
  ///
  /// - 30분 이내 캐시 있으면 캐시 반환
  /// - [forceRefresh] true면 캐시 무시하고 새로 fetch
  /// - 동시 호출 시 in-flight request 공유 (중복 호출 방지)
  Future<List<Map<String, dynamic>>> getDailyItems({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final isCacheValid =
        _cachedItems != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _cacheTtl;

    if (!forceRefresh && isCacheValid) {
      return _cachedItems!;
    }

    // 이미 진행 중인 fetch 있으면 그거 기다림 (중복 호출 방지)
    if (_inflightRequest != null) {
      return _inflightRequest!;
    }

    _inflightRequest = _fetchAndProcess(forceRefresh: forceRefresh);
    try {
      final result = await _inflightRequest!;
      _cachedItems = result;
      _fetchedAt = DateTime.now();
      return result;
    } finally {
      _inflightRequest = null;
    }
  }

  /// 캐시 강제 무효화 (필요시 외부에서 호출)
  void invalidate() {
    _cachedItems = null;
    _fetchedAt = null;
  }

  Future<List<Map<String, dynamic>>> _fetchAndProcess({
    bool forceRefresh = false,
  }) async {
    final url = Uri.parse(
      '$kApiBaseUrl/kamis/daily',
    ).replace(queryParameters: {'force_refresh': '$forceRefresh'});

    final response = await http.get(url).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('서버 응답 오류: ${response.statusCode}');
    }

    // 서버 응답에 charset이 없어서 그냥 response.body 쓰면 한글이 깨짐
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final items = ((data['items'] as List?) ?? []).cast<Map<String, dynamic>>();

    // 필터링은 서버에서 끝남. 표시 이름 기준 중복 제거만 앱에서
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final item in items) {
      final displayName = ProductNameFormatter.format(item);
      if (seen.add(displayName)) unique.add(item);
    }

    return unique;
  }
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}
