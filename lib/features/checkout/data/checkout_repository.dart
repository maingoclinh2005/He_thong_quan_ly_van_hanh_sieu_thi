import '../../../models/order.dart';
import '../../../services/api_service.dart';
import '../../../services/db_service.dart';
import '../../catalog/data/store_cache_repository.dart';
import '../../cart/data/cart_repository.dart';
import 'submission_guard.dart';
import '../../../core/data/cache_coordinator.dart';

class CheckoutRepository {
  static Future<Order> _submit(
    Future<Order> Function() create, {
    String? email,
  }) async {
    final actor = DBService.currentUserId();
    if (actor == null) {
      throw ApiException('Vui lòng đăng nhập lại', statusCode: 401);
    }
    final marker = 'pending_checkout_$actor';
    final saved = await StoreCacheRepository.coordinator.mutate(
      'orders',
      () => SubmissionGuard(
        read: (key) => DBService.settings().get(key),
        write: (key, value) => DBService.settings().put(key, value),
        remove: (key) => DBService.settings().delete(key),
        recover: ApiService.fetchOrderDetail,
        scope: StoreCacheRepository.coordinator.scope,
      ).execute(marker, create),
      (order) async {
        await DBService.orders().put(order.id, order);
        if (email != null) await DBService.carts().put(email, <String, int>{});
        await DBService.settings().delete(marker);
      },
    );
    await StoreCacheRepository.refreshAfterWrite();
    return saved;
  }

  static Future<Order> create(
    Order order, {
    int? voucherId,
    double discountAmount = 0,
    int? userId,
  }) => _submit(
    () => voucherId == null
        ? ApiService.createOrder(
            order,
            customerId: order.customerId,
            employeeId: DBService.currentUserId(),
          )
        : ApiService.createOrderWithVoucher(
            order,
            customerId: order.customerId,
            employeeId: DBService.currentUserId(),
            voucherId: voucherId,
            discountAmount: discountAmount,
            userId: order.customerId ?? userId ?? DBService.currentUserId(),
          ),
  );

  static Future<Order> online({
    required int userId,
    required String email,
    required Map<String, int> cart,
    required String deliveryMethod,
    required String paymentMethod,
    String? shippingAddress,
    String? voucherCode,
    String? note,
  }) async {
    final owner = StoreCacheRepository.coordinator.scope();
    if (DBService.settings().get('pending_checkout_$userId') == null) {
      await CartRepository.save(email, cart);
    }
    if (StoreCacheRepository.coordinator.scope() != owner) {
      throw const SessionChanged();
    }
    return _submit(
      () => ApiService.checkoutOnlineOrder(
        userId: userId,
        deliveryMethod: deliveryMethod,
        paymentMethod: paymentMethod,
        shippingAddress: shippingAddress,
        voucherCode: voucherCode,
        note: note,
      ),
      email: email,
    );
  }

  static Future<void> cacheConfirmed(Order order) async =>
      StoreCacheRepository.coordinator.mutate<Order>(
        'orders',
        () async => order,
        (saved) => DBService.orders().put(saved.id, saved),
      );
}
