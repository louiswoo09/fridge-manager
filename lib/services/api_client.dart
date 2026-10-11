import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/api_config.dart';

/// 서버에 연결 자체가 안 될 때 (서버 꺼짐, 인터넷 끊김 등)
class ServerUnavailableException implements Exception {
  @override
  String toString() => '서버에 연결할 수 없어요';
}

/// 에러를 사용자에게 보여줄 문장으로 바꿈
String friendlyError(Object e, {required String fallback}) {
  if (e is ServerUnavailableException) {
    return '서버에 연결할 수 없어요\n\n잠시 후 다시 시도해주세요';
  }
  if (e is TimeoutException) {
    return '응답이 너무 오래 걸려요\n\n잠시 후 다시 시도해주세요';
  }
  return fallback;
}

/// 우리 서버 전용 요청 도우미
/// - 모든 요청에 Firebase ID 토큰(출입증)을 자동으로 붙임
/// - 연결은 5초 안에 안 되면 바로 실패 (응답 대기 시간과 별개)
class ApiClient {
  static final http.Client _client = IOClient(
    HttpClient()..connectionTimeout = const Duration(seconds: 5),
  );

  static Future<Map<String, String>> _headers({
    bool json = false,
    bool forceRefresh = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('로그인이 필요해요');

    final String? token;
    try {
      token = await user.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (e) {
      // 토큰 갱신 중 인터넷이 끊긴 경우
      if (e.code == 'network-request-failed') throw ServerUnavailableException();
      rethrow;
    }
    if (token == null) throw StateError('인증 토큰을 받지 못했어요');

    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  /// 공통 처리: 토큰 첨부 → 401이면 새 토큰으로 1회 재시도 → 연결 실패는 전용 에러로
  static Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    required Duration timeout,
    bool json = false,
  }) async {
    try {
      var res = await request(await _headers(json: json)).timeout(timeout);
      if (res.statusCode == 401) {
        res = await request(await _headers(json: json, forceRefresh: true))
            .timeout(timeout);
      }
      return res;
    } on SocketException {
      throw ServerUnavailableException();
    } on HandshakeException {
      throw ServerUnavailableException();
    } on http.ClientException {
      throw ServerUnavailableException();
    }
  }

  static Future<http.Response> get(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final uri = Uri.parse('$kApiBaseUrl$path').replace(queryParameters: query);
    return _send((h) => _client.get(uri, headers: h), timeout: timeout);
  }

  static Future<http.Response> post(
    String path,
    String jsonBody, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    final uri = Uri.parse('$kApiBaseUrl$path');
    return _send(
      (h) => _client.post(uri, headers: h, body: jsonBody),
      timeout: timeout,
      json: true,
    );
  }
}