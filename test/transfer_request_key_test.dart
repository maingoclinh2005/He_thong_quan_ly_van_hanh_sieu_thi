import 'package:flutter_test/flutter_test.dart';
import 'package:sieuthimini/features/catalog/data/transfer_request_key.dart';

void main() {
  test('transfer keys work on Web and match backend validation', () {
    final keys = List.generate(1000, (_) => createTransferRequestKey());
    for (final key in keys) {
      expect(RegExp(r'^[a-zA-Z0-9_-]{16,80}$').hasMatch(key), isTrue);
      expect(RegExp(r'^transfer_\d+_[0-9a-f]{32}$').hasMatch(key), isTrue);
    }
    expect(keys.toSet().length, keys.length);
  });
}
