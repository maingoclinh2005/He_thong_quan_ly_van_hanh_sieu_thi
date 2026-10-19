import 'package:flutter/foundation.dart';
import '../../../models/product.dart';
import '../../../models/inventory_item.dart';
import '../../../services/api_service.dart';
import '../../../services/db_service.dart';
import '../data/store_cache_repository.dart';

class CatalogController extends ChangeNotifier {
  CatalogController() {
    StoreCacheRepository.coordinator.addListener(_changed);
  }
  bool busy = false;
  Object? error;
  Map<int, String> categories = {};
  bool _disposed = false;
  int _request = 0;
  List<Product> get products => List.unmodifiable(DBService.products().values);
  List<InventoryItem> get inventory =>
      List.unmodifiable(DBService.inventoryProducts().values);
  Future<void> refresh({bool warehouse = false}) async {
    final request = ++_request;
    final owner = StoreCacheRepository.coordinator.scope();
    busy = true;
    _changed();
    try {
      await StoreCacheRepository.products();
      if (warehouse) {
        await StoreCacheRepository.inventory();
        final rows = await ApiService.fetchCategories();
        if (!_disposed &&
            request == _request &&
            owner == StoreCacheRepository.coordinator.scope()) {
          categories = {
            for (final row in rows)
              if (int.tryParse(row['category_id'].toString()) != null)
                int.parse(row['category_id'].toString()): row['category_name']
                    .toString(),
          };
        }
      }
      if (request == _request) error = null;
    } catch (e) {
      if (request == _request) error = e;
    } finally {
      if (request == _request) busy = false;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    StoreCacheRepository.coordinator.removeListener(_changed);
    super.dispose();
  }
}
