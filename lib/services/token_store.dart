import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A single encrypted record avoids torn access/refresh pairs. Never falls back to Hive.
class TokenStore extends ChangeNotifier {
  TokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static final instance = TokenStore();
  static const _key = 'auth_session_v1';
  final FlutterSecureStorage _storage;
  String? accessToken;
  String? _refreshToken;
  String? get refreshToken => _refreshToken;
  bool get hasSession => accessToken != null && _refreshToken != null;
  int generation = 0;
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<void> initialize() => _serial(() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _validate(data);
      accessToken = data['token'] as String;
      _refreshToken = data['refresh_token'] as String;
    } on FormatException {
      await _storage.delete(key: _key);
    } on TypeError {
      await _storage.delete(key: _key);
    }
  });

  void _validate(Map<String, dynamic> pair) {
    if (pair['token'] is! String ||
        (pair['token'] as String).isEmpty ||
        pair['refresh_token'] is! String ||
        (pair['refresh_token'] as String).isEmpty) {
      throw const FormatException('Phiên đăng nhập không hợp lệ');
    }
  }

  Future<bool> save(
    Map<String, dynamic> pair, {
    required int expectedGeneration,
    bool newLogin = false,
  }) => _serial(() async {
    if (generation != expectedGeneration) return false;
    _validate(pair);
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'token': pair['token'],
        'refresh_token': pair['refresh_token'],
      }),
    );
    if (generation != expectedGeneration) return false;
    accessToken = pair['token'] as String;
    _refreshToken = pair['refresh_token'] as String;
    if (newLogin) generation++;
    notifyListeners();
    return true;
  });

  Future<void> clear() {
    generation++;
    accessToken = null;
    _refreshToken = null;
    notifyListeners();
    return _serial(() => _storage.delete(key: _key));
  }
}
