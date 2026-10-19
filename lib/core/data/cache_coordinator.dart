import 'package:flutter/foundation.dart';

class SessionChanged implements Exception {
  const SessionChanged();
  @override
  String toString() => 'Phiên đăng nhập đã thay đổi; vui lòng tải lại.';
}

/// Serializes API/cache work. A failed cache write never retries a confirmed API write.
class CacheCoordinator extends ChangeNotifier {
  CacheCoordinator({required this.scope});
  final String Function() scope;
  Future<void> _tail = Future.value();
  final Map<String, Future<void>> _reads = {};
  final Map<String, Object> _errors = {};
  Map<String, Object> get errors => Map.unmodifiable(_errors);
  int _revision = 0;
  Future<T> serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> refresh<T>(
    String key,
    Future<T> Function() fetch,
    Future<void> Function(T) apply,
  ) {
    final owner = scope();
    final readKey = '$owner:$_revision:$key';
    final existing = _reads[readKey];
    if (existing != null) return existing;
    late final Future<void> result;
    result =
        serial(() async {
          if (scope() != owner) throw const SessionChanged();
          try {
            final data = await fetch();
            if (scope() != owner) throw const SessionChanged();
            await apply(data);
            _errors.remove(key);
          } catch (error) {
            if (scope() == owner) _errors[key] = error;
            rethrow;
          } finally {
            notifyListeners();
          }
        }).whenComplete(() {
          _reads.remove(readKey);
        });
    _reads[readKey] = result;
    return result;
  }

  Future<T> mutate<T>(
    String key,
    Future<T> Function() remote,
    Future<void> Function(T) apply,
  ) {
    final owner = scope();
    _revision++; // Reads queued after a write must not join an older read.
    return serial(() async {
      if (scope() != owner) throw const SessionChanged();
      final value =
          await remote(); // Remote failure/unknown outcome propagates.
      if (scope() != owner) return value; // Never publish old-session data.
      try {
        await apply(value);
        _errors.remove(key);
      } catch (error) {
        _errors[key] = error; // Remote success remains success.
      }
      notifyListeners();
      return value;
    });
  }

  Future<void> clear(Future<void> Function() clearCache) {
    _revision++;
    _reads.clear();
    return serial(() async {
      await clearCache();
      _errors.clear();
      notifyListeners();
    });
  }
}
