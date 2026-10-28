import 'dart:math';

/// 128 random bits, using byte-sized bounds that work on Dart VM and Web.
/// Never use `1 << 32`: JavaScript bitwise operations truncate to 32 bits.
String createTransferRequestKey() {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'transfer_${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
