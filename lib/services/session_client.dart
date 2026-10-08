import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'token_store.dart';

/// One shared client for normal requests, vouchers and multipart uploads.
class SessionClient extends http.BaseClient {
  SessionClient({
    required this.baseUrl,
    http.Client? transport,
    TokenStore? tokens,
  }) : _transport = transport ?? http.Client(),
       _tokens = tokens ?? TokenStore.instance;
  final String Function() baseUrl;
  final http.Client _transport;
  final TokenStore _tokens;
  Future<bool>? _refreshing;
  static const _publicAuth = {
    '/api/auth/login',
    '/api/auth/register',
    '/api/auth/refresh',
    '/api/auth/forgot-password/email',
    '/api/auth/forgot-password/phone',
    '/api/auth/verify-otp',
    '/api/auth/reset-password',
  };

  Future<bool> _refresh(int generation) {
    return _refreshing ??= _performRefresh(
      generation,
    ).whenComplete(() => _refreshing = null);
  }

  Future<bool> _performRefresh(int generation) async {
    final refresh = _tokens.refreshToken;
    if (refresh == null) return false;
    final request =
        http.Request('POST', Uri.parse('${baseUrl()}/api/auth/refresh'))
          ..followRedirects = false
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({'refresh_token': refresh});
    final response = await _transport
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 15));
    if (_tokens.generation != generation) return false;
    if (response.statusCode == 401 || response.statusCode == 403) {
      await _tokens.clear();
      return false;
    }
    // Transient failures do not erase a valid local session or retry the rotating token.
    if (response.statusCode != 200) return false;
    return _tokens.save(
      jsonDecode(response.body) as Map<String, dynamic>,
      expectedGeneration: generation,
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (kReleaseMode && request.url.scheme != 'https') {
      throw StateError('Bản phát hành yêu cầu API qua HTTPS.');
    }
    if (request.url.origin != Uri.parse(baseUrl()).origin) {
      throw ArgumentError('Không gửi thông tin đăng nhập sang máy chủ khác');
    }
    final protected = !_publicAuth.contains(request.url.path);
    final generation = _tokens.generation;
    final sentToken = protected ? _tokens.accessToken : null;
    final bytes = await request.finalize().toBytes();
    http.Request copy(String? token) =>
        http.Request(request.method, request.url)
          ..followRedirects = false
          ..headers.addAll(
            Map.of(request.headers)
              ..removeWhere((key, _) => key.toLowerCase() == 'authorization'),
          )
          ..headers.addAll(
            token == null ? {} : {'Authorization': 'Bearer $token'},
          )
          ..bodyBytes = bytes;
    var response = await _transport.send(copy(sentToken));
    if (!protected ||
        sentToken == null ||
        response.statusCode != 401 ||
        generation != _tokens.generation) {
      return response;
    }
    // Buffer the small unauthorized response so it can still be returned if refresh fails.
    final denied = await response.stream.toBytes();
    final refreshed =
        sentToken != _tokens.accessToken || await _refresh(generation);
    if (!refreshed || generation != _tokens.generation || !_tokens.hasSession) {
      return http.StreamedResponse(
        Stream.value(denied),
        response.statusCode,
        headers: response.headers,
      );
    }
    response = await _transport.send(copy(_tokens.accessToken));
    if (response.statusCode == 401 && generation == _tokens.generation) {
      await _tokens.clear();
    }
    return response;
  }

  @override
  void close() => _transport.close();
}
