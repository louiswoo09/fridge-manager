import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'product_name_formatter.dart';

const String _kKamisCertKey = String.fromEnvironment('KAMIS_CERT_KEY');
const String _kKamisCertId = String.fromEnvironment('KAMIS_CERT_ID');

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
    final isCacheValid = _cachedItems != null &&
        _fetchedAt != null &&
        now.difference(_fetchedAt!) < _cacheTtl;

    if (!forceRefresh && isCacheValid) {
      return _cachedItems!;
    }

    // 이미 진행 중인 fetch 있으면 그거 기다림 (중복 호출 방지)
    if (_inflightRequest != null) {
      return _inflightRequest!;
    }

    _inflightRequest = _fetchAndProcess();
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

  Future<List<Map<String, dynamic>>> _fetchAndProcess() async {
    if (_kKamisCertKey.isEmpty || _kKamisCertId.isEmpty) {
      throw StateError('KAMIS API 키가 설정되지 않았습니다');
    }

    final url = Uri.parse(
      'http://www.kamis.or.kr/service/price/xml.do'
      '?action=dailySalesList'
      '&p_cert_key=$_kKamisCertKey'
      '&p_cert_id=$_kKamisCertId'
      '&p_returntype=json',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw HttpException('KAMIS API 응답 오류: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final priceData = data['price'];

    if (priceData == null || priceData is! List) {
      return [];
    }

    // 소매(productclscode='01')만 + 가격 있는 것만
    final filtered = priceData
        .cast<Map<String, dynamic>>()
        .where((item) {
          final clsCode = item['product_cls_code']?.toString() ?? '';
          return clsCode == '01';
        })
        .where((item) {
          final dpr1 = item['dpr1']?.toString().replaceAll(',', '') ?? '';
          return dpr1.isNotEmpty && dpr1 != '-';
        })
        .toList();

    // displayName 기준 중복 제거
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final item in filtered) {
      final displayName = ProductNameFormatter.format(item);
      if (!seen.contains(displayName)) {
        seen.add(displayName);
        unique.add(item);
      }
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