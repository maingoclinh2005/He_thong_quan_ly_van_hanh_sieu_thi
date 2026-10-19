import '../../../services/api_service.dart';
import '../../../services/db_service.dart';
import '../../catalog/data/store_cache_repository.dart';

class CartRepository {
  static Future<void> save(String email, Map<String, int> cart) {
    final snapshot = Map<String, int>.from(cart)
      ..removeWhere((_, qty) => qty <= 0);
    final userId = DBService.currentUserId();
    return StoreCacheRepository.coordinator.mutate<void>('cart', () async {
      if (userId != null) await ApiService.saveCart(userId, snapshot);
    }, (_) => DBService.carts().put(email, snapshot));
  }

  static Future<Map<String, int>> load(String email) {
    final userId = DBService.currentUserId();
    return StoreCacheRepository.coordinator.mutate('cart', () async {
      if (userId == null) return DBService.getCartForUser(email);
      // Empty remote cart is authoritative. Never resurrect an already checked-out cart.
      return ApiService.fetchCart(userId);
    }, (cart) => DBService.carts().put(email, cart));
  }
}
