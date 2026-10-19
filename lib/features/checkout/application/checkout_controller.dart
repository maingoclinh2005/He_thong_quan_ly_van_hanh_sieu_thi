import 'package:flutter/foundation.dart';
import '../../../models/order.dart';
import '../../../services/api_service.dart';
import '../../../core/data/cache_coordinator.dart';

class CheckoutUncertain implements Exception {
  const CheckoutUncertain();
  @override
  String toString() =>
      'Chưa xác định kết quả tạo đơn. Kiểm tra lịch sử đơn hoặc liên hệ quản trị viên trước khi tạo lại.';
}

class CheckoutController extends ChangeNotifier {
  Future<Order>? _pending;
  Order? confirmed;
  Object? error;
  bool uncertain = false;
  bool _disposed = false;
  bool get busy => _pending != null;
  Future<Order> submit(Future<Order> Function() create) {
    if (confirmed != null) return Future.value(confirmed!);
    if (_pending != null) return _pending!;
    if (uncertain) return Future.error(const CheckoutUncertain());
    late final Future<Order> operation;
    operation = Future<Order>.sync(create)
        .then(
          (order) {
            confirmed = order;
            error = null;
            return order;
          },
          onError: (Object e, StackTrace stack) {
            error = e;
            uncertain =
                e is! SessionChanged &&
                !(e is ApiException &&
                    e.statusCode != null &&
                    e.statusCode! >= 400 &&
                    e.statusCode! < 500);
            Error.throwWithStackTrace(
              uncertain ? const CheckoutUncertain() : e,
              stack,
            );
          },
        )
        .whenComplete(() {
          _pending = null;
          if (!_disposed) notifyListeners();
        });
    _pending = operation;
    if (!_disposed) notifyListeners();
    return operation;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
