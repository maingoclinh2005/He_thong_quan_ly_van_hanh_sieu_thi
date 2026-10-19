import 'package:hive/hive.dart';
import '../../../core/data/cache_coordinator.dart';
import '../../../models/inventory_history_entry.dart';
import '../../../models/order.dart';
import '../../../services/api_service.dart';
import '../../../services/db_service.dart';
import '../../../services/token_store.dart';
import '../../../utils/type_converters.dart';

class StoreCacheRepository {
  static final coordinator = CacheCoordinator(
    scope: () =>
        '${TokenStore.instance.generation}:${DBService.currentUserId()}',
  );

  /// No clear-then-fill blank state; an empty server snapshot is authoritative.
  /// Hive boxes are not transactional across tables. Controllers publish after completion.
  static Future<void> replace<T>(Box<T> box, Map<dynamic, T> values) async {
    await box.putAll(values);
    await box.deleteAll(
      box.keys.where((key) => !values.containsKey(key)).toList(),
    );
  }

  static Future<void> products() =>
      coordinator.refresh('products', ApiService.fetchProducts, (items) async {
        await replace(DBService.products(), {
          for (final item in items) item.id: item,
        });
        for (final item in items) {
          if (item.imageUrl?.isNotEmpty == true) {
            await DBService.productImages().put(
              item.id,
              ApiService.resolveBackendUrl(item.imageUrl!),
            );
          } else {
            await DBService.productImages().delete(item.id);
          }
        }
      });

  static Future<void> inventory() => coordinator.refresh(
    'inventory',
    ApiService.fetchInventoryItems,
    (items) async {
      await replace(DBService.inventoryProducts(), {
        for (final item in items) item.id: item,
      });
    },
  );

  static Future<void> users() => coordinator.refresh(
    'users',
    ApiService.fetchUsers,
    (items) => replace(DBService.users(), {
      for (final item in items) item.email: item,
    }),
  );

  static Future<List<Order>> _fetchOrders() async {
    final orders = await ApiService.fetchOrders();
    final details = <Order>[];
    for (var i = 0; i < orders.length; i += 6) {
      details.addAll(
        await Future.wait(
          orders
              .skip(i)
              .take(6)
              .map((order) => ApiService.fetchOrderDetail(order.id)),
        ),
      );
    }
    return details;
  }

  static Future<void> orders() => coordinator.refresh(
    'orders',
    _fetchOrders,
    (items) =>
        replace(DBService.orders(), {for (final item in items) item.id: item}),
  );

  static Future<void> history() => coordinator.refresh(
    'history',
    ApiService.fetchInventoryLogs,
    (logs) async {
      final entries = logs.map(
        (log) => InventoryHistoryEntry(
          id: log['log_id'].toString(),
          type: (log['action'] ?? '').toString().toLowerCase(),
          itemId: (log['inventory_item_id'] ?? log['product_id']).toString(),
          itemName: (log['item_name'] ?? log['product_name'] ?? '').toString(),
          unit: (log['unit'] ?? 'sp').toString(),
          quantityChange: TypeConverters.toInt(log['quantity']),
          beforeQuantity: 0,
          afterQuantity: 0,
          note: (log['note'] ?? '').toString(),
          createdAt:
              DateTime.tryParse((log['created_at'] ?? '').toString()) ??
              DateTime.now(),
        ),
      );
      await replace(DBService.inventoryHistory(), {
        for (final item in entries) item.id: item,
      });
    },
  );

  /// Called after confirmed writes. Errors stay visible via coordinator.errors.
  static Future<void> refreshAfterWrite({bool warehouse = false}) async {
    for (final refresh in [
      products,
      if (warehouse) inventory,
      if (warehouse) history,
    ]) {
      try {
        await refresh();
      } catch (_) {
        /* recorded by coordinator */
      }
    }
  }
}
