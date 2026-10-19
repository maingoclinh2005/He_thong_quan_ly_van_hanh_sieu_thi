import 'package:flutter/foundation.dart';

class CartController extends ChangeNotifier {
  CartController({
    Map<String, int> initial = const {},
    required this.loadCart,
    required this.saveCart,
  }) : items = Map.of(initial);
  final Future<Map<String, int>> Function() loadCart;
  final Future<void> Function(Map<String, int>) saveCart;
  final Map<String, int> items;
  Object? error;
  bool loading = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> load() async {
    final revision = _revision;
    loading = true;
    _notify();
    try {
      final saved = await loadCart();
      if (!_disposed && revision == _revision) {
        items
          ..clear()
          ..addAll(saved);
        error = null;
      }
    } catch (e) {
      if (!_disposed && revision == _revision) error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> persist() async {
    final revision = ++_revision;
    final snapshot = Map<String, int>.from(items);
    try {
      await saveCart(snapshot);
      if (!_disposed && revision == _revision) error = null;
    } catch (e) {
      if (!_disposed) error = e;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
