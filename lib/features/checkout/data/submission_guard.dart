import '../../../core/data/cache_coordinator.dart';
import '../../../models/order.dart';
import '../../../services/api_service.dart';
import '../application/checkout_controller.dart';

/// Persistent receipt boundary, injectable for tests. Does not assume backend idempotency.
class SubmissionGuard {
  SubmissionGuard({
    required this.read,
    required this.write,
    required this.remove,
    required this.recover,
    required this.scope,
  });
  final Object? Function(String) read;
  final Future<void> Function(String, Map<String, dynamic>) write;
  final Future<void> Function(String) remove;
  final Future<Order> Function(String) recover;
  final String Function() scope;
  Future<Order> execute(String key, Future<Order> Function() create) async {
    final owner = scope();
    final pending = read(key);
    if (pending is Map) {
      final id = pending['order_id'];
      if (id != null) return recover(id.toString());
      throw const CheckoutUncertain();
    }
    await write(key, {'started_at': DateTime.now().toIso8601String()});
    if (scope() != owner) {
      try {
        await remove(key);
      } catch (_) {}
      throw const SessionChanged();
    }
    try {
      final order = await create();
      try {
        await write(key, {'order_id': order.id});
      } catch (_) {}
      return order;
    } on ApiException catch (e) {
      if (e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
        try {
          await remove(key);
        } catch (_) {}
      }
      rethrow;
    }
  }
}
