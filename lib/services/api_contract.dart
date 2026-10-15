import 'dart:convert';

/// JSON on the network uses snake_case. Domain/Hive objects keep their current
/// Dart names; compatibility aliases never leave this boundary.
class ApiContract {
  static String _snake(String key) => key
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m[1]}_${m[2]}',
      )
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
      .toLowerCase();

  static dynamic toWire(dynamic value) {
    if (value is List) return value.map(toWire).toList();
    if (value is! Map) return value;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (key != _snake(key)) result[_snake(key)] = toWire(entry.value);
    }
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (key == _snake(key)) result[key] = toWire(entry.value);
    }
    return result;
  }

  static dynamic fromWire(dynamic value) {
    if (value is List) return value.map(fromWire).toList();
    if (value is! Map) return value;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      result[key] = fromWire(entry.value);
    }
    for (final key in result.keys.toList()) {
      final alias = key.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (m) => m[1]!.toUpperCase(),
      );
      result.putIfAbsent(alias, () => result[key]);
    }
    return result;
  }

  static dynamic decode(String source) => fromWire(jsonDecode(source));
}
