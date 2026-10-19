import '../../../core/data/cache_coordinator.dart';
import 'dart:math';
import '../../../models/product.dart';
import '../../../models/inventory_item.dart';
import '../../../services/api_service.dart';
import '../../../services/db_service.dart';
import 'store_cache_repository.dart';

class CatalogRepository {
  static Future<void> _cacheProduct(Product saved) async {
    await DBService.products().put(saved.id, saved);
    if (saved.imageUrl?.isNotEmpty == true) {
      await DBService.productImages().put(
        saved.id,
        ApiService.resolveBackendUrl(saved.imageUrl!),
      );
    } else {
      await DBService.productImages().delete(saved.id);
    }
  }

  static Future<Product> saveProduct(
    Product product, {
    bool create = false,
    String? imagePath,
  }) => StoreCacheRepository.coordinator.mutate('products', () async {
    final owner = StoreCacheRepository.coordinator.scope();
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        !imagePath.startsWith('http')) {
      product.imageUrl = await ApiService.uploadProductImage(imagePath);
    }
    if (StoreCacheRepository.coordinator.scope() != owner) {
      throw const SessionChanged();
    }
    return create
        ? ApiService.createProduct(product)
        : ApiService.updateProduct(product);
  }, _cacheProduct);

  static Future<Product> scan(String code) =>
      StoreCacheRepository.coordinator.mutate('products', () async {
        final result = await ApiService.scanProductCode(code.trim());
        final value = result['product'];
        if (result['type'] != 'product' || value is! Map) {
          throw ApiException(
            'Không tìm thấy sản phẩm bán hàng',
            statusCode: 404,
          );
        }
        return Product.fromJson(Map<String, dynamic>.from(value));
      }, _cacheProduct);

  static Future<void> deleteProduct(Product product) =>
      StoreCacheRepository.coordinator.mutate<void>(
        'products',
        () => ApiService.deleteProduct(product.id),
        (_) async {
          await DBService.products().delete(product.id);
          await DBService.productImages().delete(product.id);
        },
      );

  static int _actor() {
    final id = DBService.currentUserId();
    if (id == null) throw ApiException('Vui lòng đăng nhập lại');
    return id;
  }

  static Future<void> importStock({
    required InventoryItem item,
    required int quantity,
    required double importPrice,
    String? note,
  }) async {
    final actor = _actor();
    await StoreCacheRepository.coordinator.mutate<void>(
      'inventory',
      () => ApiService.importInventory(
        inventoryItemId: item.id,
        employeeId: actor,
        quantity: quantity,
        importPrice: importPrice,
        note: note,
      ),
      (_) async {},
    );
    await StoreCacheRepository.refreshAfterWrite(warehouse: true);
  }

  static Future<void> adjust({
    required InventoryItem item,
    required int actualQuantity,
    String? note,
  }) async {
    final actor = _actor();
    await StoreCacheRepository.coordinator.mutate<void>(
      'inventory',
      () => ApiService.adjustInventory(
        inventoryItemId: item.id,
        employeeId: actor,
        actualQuantity: actualQuantity,
        note: note,
      ),
      (_) async {},
    );
    await StoreCacheRepository.refreshAfterWrite(warehouse: true);
  }

  static Future<InventoryItem> update(InventoryItem item) =>
      StoreCacheRepository.coordinator.mutate(
        'inventory',
        () => ApiService.updateInventoryItem(item),
        (saved) => DBService.inventoryProducts().put(saved.id, saved),
      );

  static Future<InventoryItem> create({
    required String barcode,
    required String name,
    required double price,
    required double importPrice,
    required String unit,
    required int quantity,
    int? categoryId,
    String? imagePath,
  }) async {
    final saved = await StoreCacheRepository.coordinator.mutate(
      'inventory',
      () async {
        final owner = StoreCacheRepository.coordinator.scope();
        String? imageUrl;
        if (imagePath != null && imagePath.isNotEmpty) {
          imageUrl = imagePath.startsWith('http')
              ? imagePath
              : await ApiService.uploadProductImage(imagePath);
        }
        if (StoreCacheRepository.coordinator.scope() != owner) {
          throw const SessionChanged();
        }
        // One server transaction creates the item and its opening ledger balance.
        return ApiService.createInventoryItem(
          InventoryItem(
            id: barcode,
            name: name,
            price: price,
            importPrice: importPrice,
            unit: unit,
            stockQuantity: quantity,
            categoryId: categoryId,
            imageUrl: imageUrl,
          ),
        );
      },
      (item) => DBService.inventoryProducts().put(item.id, item),
    );
    await StoreCacheRepository.refreshAfterWrite(warehouse: true);
    return saved;
  }

  static final Map<String, Future<Product>> _transfers = {};
  static Future<Product> transfer({
    required InventoryItem item,
    required int quantity,
  }) {
    final actor = _actor();
    final key =
        '${StoreCacheRepository.coordinator.scope()}:${item.id}:$quantity';
    return _transfers.putIfAbsent(
      key,
      () => _transfer(item, quantity, actor).whenComplete(() {
        _transfers.remove(key);
      }),
    );
  }

  static Future<Product> _transfer(
    InventoryItem item,
    int quantity,
    int actor,
  ) async {
    final pendingKey = 'pending_transfer_${actor}_${item.id}_$quantity';
    final legacyKey = 'pending_transfer_${item.id}_$quantity';
    final saved = await StoreCacheRepository.coordinator.mutate(
      'inventory',
      () async {
        final owner = StoreCacheRepository.coordinator.scope();
        final requestKey =
            DBService.settings().get(pendingKey) as String? ??
            DBService.settings().get(legacyKey) as String? ??
            'transfer_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
        await DBService.settings().put(pendingKey, requestKey);
        if (StoreCacheRepository.coordinator.scope() != owner) {
          throw const SessionChanged();
        }
        return ApiService.exportInventory(
          inventoryItemId: item.id,
          employeeId: actor,
          quantity: quantity,
          requestKey: requestKey,
          note: 'Đưa hàng lên kệ',
        );
      },
      (product) async {
        await _cacheProduct(product);
        await DBService.settings().delete(pendingKey);
        await DBService.settings().delete(legacyKey);
      },
    );
    await StoreCacheRepository.refreshAfterWrite(warehouse: true);
    return saved;
  }
}
