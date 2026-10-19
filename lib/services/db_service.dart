import 'package:flutter/foundation.dart';
import '../features/cart/data/cart_repository.dart';
import '../features/checkout/data/checkout_repository.dart';
import '../features/catalog/data/catalog_repository.dart';
import '../features/catalog/data/store_cache_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product.dart';
import '../models/inventory_item.dart';
import '../models/user.dart';
import '../models/order.dart';
import '../models/order_line.dart';
import '../models/inventory_history_entry.dart';
import 'api_service.dart';
import 'token_store.dart';
import '../utils/constants.dart';

/// Helper class for seed data structure
class _SeedItem {
  final String barcode;
  final String name;
  final double price;
  final double importPrice;
  final String unit;
  final int stock;

  const _SeedItem({
    required this.barcode,
    required this.name,
    required this.price,
    required this.importPrice,
    required this.unit,
    required this.stock,
  });
}

class DBService {
  static const int cacheSchemaVersion = AppConstants.cacheSchemaVersion;
  static const bool forceUseLocalProductSeed =
      AppConstants.forceUseLocalProductSeed;
  static const String productsBox = AppConstants.productsBox;
  static const String usersBox = AppConstants.usersBox;
  static const String ordersBox = AppConstants.ordersBox;
  static const String settingsBox = AppConstants.settingsBox;
  static const String cartsBox = AppConstants.cartsBox;
  static const String productImagesBox = AppConstants.productImagesBox;
  static const String inventoryProductsBox = AppConstants.inventoryProductsBox;
  static const String inventoryHistoryBox = AppConstants.inventoryHistoryBox;

  static Future<void> init() async {
    // 1. Initialize Hive & Register Adapters
    await Hive.initFlutter();
    _registerAdapterOnce(ProductAdapter());
    _registerAdapterOnce(InventoryItemAdapter());
    _registerAdapterOnce(UserAdapter());
    _registerAdapterOnce(OrderAdapter());
    _registerAdapterOnce(OrderLineAdapter());
    _registerAdapterOnce(InventoryHistoryEntryAdapter());

    await Hive.openBox(settingsBox);
    await initializeAuthStorage();
    await _deleteOldCacheFromDiskIfNeeded();

    // 2. Open Boxes
    await Hive.openBox<Product>(productsBox);
    await Hive.openBox<User>(usersBox);
    await Hive.openBox<Order>(ordersBox);
    await Hive.openBox<InventoryItem>(inventoryProductsBox);
    await Hive.openBox<InventoryHistoryEntry>(inventoryHistoryBox);
    await Hive.openBox<String>(productImagesBox);
    await Hive.openBox(cartsBox);

    // 3. Migrate product keys (if they were stored with numeric keys)
    try {
      await _migrateProductsToIdKeys();
    } catch (e) {
      debugPrint('Cache sản phẩm cũ không tương thích, xóa cache: $e');
      await _clearRuntimeCache();
    }

    // 4. Pull remote data into the local cache. If the API is not running,
    // keep the app usable with the existing Hive cache/sample data.
    try {
      if (forceUseLocalProductSeed) {
        // Ưu tiên dữ liệu local mới, không cho API cũ ghi đè products/inventory.
        await products().clear();
        await inventoryProducts().clear();
        await seedProducts();
        await seedInventory();
        await Future.wait([
          syncUsersFromApi(),
          syncOrdersFromApi(),
          syncInventoryHistoryFromApi(),
        ]);
      } else {
        await syncAllFromApi();
      }
    } catch (e) {
      debugPrint('Không đồng bộ được API, dùng cache Hive: $e');
      if (forceUseLocalProductSeed) {
        await seedProducts();
        await seedInventory();
        await seedUsers();
      }
    }
  }

  // CÁC HÀM GETTER
  static Future<void> initializeAuthStorage() async {
    // Old stateless JWTs cannot be upgraded to revocable sessions. Require login once.
    final hadLegacySecret =
        settings().containsKey('auth_token') ||
        settings().containsKey('remember_pass');
    if (settings().containsKey('auth_token')) await clearAuthSession();
    await settings().delete('remember_pass');
    if (hadLegacySecret) await settings().compact();
    await TokenStore.instance.initialize();
  }

  static Box<Product> products() => Hive.box<Product>(productsBox);
  static Box<InventoryItem> inventoryProducts() =>
      Hive.box<InventoryItem>(inventoryProductsBox);
  static Box<InventoryHistoryEntry> inventoryHistory() =>
      Hive.box<InventoryHistoryEntry>(inventoryHistoryBox);
  static Box<User> users() => Hive.box<User>(usersBox);
  static Box<Order> orders() => Hive.box<Order>(ordersBox);
  static Box carts() => Hive.box(cartsBox);
  static Box settings() => Hive.box(settingsBox);
  static Box<String> productImages() => Hive.box<String>(productImagesBox);

  static void _registerAdapterOnce<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter(adapter);
    }
  }

  static Future<void> _deleteOldCacheFromDiskIfNeeded() async {
    final box = settings();
    final currentVersion = box.get('cache_schema_version');
    if (currentVersion == cacheSchemaVersion) return;

    for (final boxName in [
      productsBox,
      usersBox,
      ordersBox,
      cartsBox,
      productImagesBox,
      inventoryProductsBox,
      inventoryHistoryBox,
    ]) {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
      await Hive.deleteBoxFromDisk(boxName);
    }

    await box.put('cache_schema_version', cacheSchemaVersion);
  }

  static Future<void> _clearRuntimeCache() async {
    // Auth migration can run before typed boxes are opened.
    Future<void> clear(String name, Future<dynamic> Function() opened) async {
      if (Hive.isBoxOpen(name)) {
        await opened();
      } else {
        await Hive.deleteBoxFromDisk(name);
      }
    }

    await Future.wait([
      clear(productsBox, () => products().clear()),
      clear(inventoryProductsBox, () => inventoryProducts().clear()),
      clear(usersBox, () => users().clear()),
      clear(ordersBox, () => orders().clear()),
      clear(inventoryHistoryBox, () => inventoryHistory().clear()),
      clear(productImagesBox, () => productImages().clear()),
      clear(cartsBox, () => carts().clear()),
    ]);
  }

  static Future<void> syncAllFromApi() async {
    if (forceUseLocalProductSeed) {
      await Future.wait([
        syncUsersFromApi(),
        syncOrdersFromApi(),
        syncInventoryHistoryFromApi(),
      ]);
      return;
    }

    await Future.wait([
      syncProductsFromApi(),
      syncInventoryItemsFromApi(),
      syncUsersFromApi(),
      syncOrdersFromApi(),
      syncInventoryHistoryFromApi(),
    ]);
  }

  static Future<void> syncProductsFromApi() => StoreCacheRepository.products();

  static Future<void> syncInventoryItemsFromApi() =>
      StoreCacheRepository.inventory();

  static Future<void> syncUsersFromApi() => StoreCacheRepository.users();

  static Future<User> updateCurrentUserProfile({
    required User user,
    required String fullName,
    required String phone,
    required String address,
    String? password,
  }) async {
    if (user.userId == null) {
      throw ApiException('Thiếu user_id để cập nhật thông tin cá nhân');
    }
    final saved = await ApiService.updateUserProfile(
      userId: user.userId!,
      fullName: fullName,
      phone: phone,
      address: address,
      password: password,
    );
    await users().put(saved.email, saved);
    await settings().put('current_user_email', saved.email);
    return saved;
  }

  static Future<void> syncOrdersFromApi() => StoreCacheRepository.orders();

  static Future<void> syncInventoryHistoryFromApi() =>
      StoreCacheRepository.history();

  static Future<void> addInventoryHistoryEntry(
    InventoryHistoryEntry entry,
  ) async {
    await inventoryHistory().put(entry.id, entry);
  }

  // --- LOGIC SEEDING ---

  // Master seed data structure to avoid duplication
  static const List<_SeedItem> _masterSeedData = [
    _SeedItem(
      barcode: 'PROD001',
      name: 'Chuối',
      price: 25000.0,
      importPrice: 15000.0,
      unit: 'Kg',
      stock: 100,
    ),
    _SeedItem(
      barcode: 'PROD002',
      name: 'Dâu tây',
      price: 120000.0,
      importPrice: 80000.0,
      unit: 'Hộp',
      stock: 50,
    ),
    _SeedItem(
      barcode: 'PROD003',
      name: 'Táo',
      price: 60000.0,
      importPrice: 40000.0,
      unit: 'Kg',
      stock: 80,
    ),
    _SeedItem(
      barcode: 'PROD004',
      name: 'Dứa (Thơm)',
      price: 15000.0,
      importPrice: 8000.0,
      unit: 'Quả',
      stock: 40,
    ),
    _SeedItem(
      barcode: 'PROD005',
      name: 'Dưa hấu',
      price: 20000.0,
      importPrice: 12000.0,
      unit: 'Kg',
      stock: 150,
    ),
    _SeedItem(
      barcode: 'PROD006',
      name: 'Xốt Thái sả tắc',
      price: 35000.0,
      importPrice: 25000.0,
      unit: 'Chai',
      stock: 60,
    ),
    _SeedItem(
      barcode: 'PROD007',
      name: 'Xốt BBQ',
      price: 45000.0,
      importPrice: 32000.0,
      unit: 'Chai',
      stock: 40,
    ),
    _SeedItem(
      barcode: 'PROD008',
      name: 'Muối ớt chanh Nha Trang',
      price: 18000.0,
      importPrice: 12000.0,
      unit: 'Chai',
      stock: 100,
    ),
    _SeedItem(
      barcode: 'PROD009',
      name: 'Xốt kim quất',
      price: 35000.0,
      importPrice: 25000.0,
      unit: 'Chai',
      stock: 50,
    ),
    _SeedItem(
      barcode: 'PROD010',
      name: 'Xốt trứng muối',
      price: 55000.0,
      importPrice: 40000.0,
      unit: 'Chai',
      stock: 30,
    ),
    _SeedItem(
      barcode: 'PROD011',
      name: 'Trà TH true TEA',
      price: 10000.0,
      importPrice: 7000.0,
      unit: 'Chai',
      stock: 200,
    ),
    _SeedItem(
      barcode: 'PROD012',
      name: 'Trà đào và hạt chia Fuze Tea',
      price: 12000.0,
      importPrice: 8500.0,
      unit: 'Chai',
      stock: 120,
    ),
    _SeedItem(
      barcode: 'PROD013',
      name: 'Trà xanh C2 hương chanh',
      price: 8000.0,
      importPrice: 5500.0,
      unit: 'Chai',
      stock: 300,
    ),
    _SeedItem(
      barcode: 'PROD014',
      name: 'Trà đá TRADA hương hoa nhài',
      price: 10000.0,
      importPrice: 6500.0,
      unit: 'Lon',
      stock: 100,
    ),
    _SeedItem(
      barcode: 'PROD015',
      name: 'Trà xanh Lipton vị chanh mật ong',
      price: 12000.0,
      importPrice: 8000.0,
      unit: 'Chai',
      stock: 150,
    ),
  ];

  static Future<void> seedProducts() async {
    final box = products();
    if (box.isEmpty) {
      for (final item in _masterSeedData) {
        await box.put(
          item.barcode,
          Product(
            id: item.barcode,
            name: item.name,
            price: item.price,
            unit: item.unit,
            stockQuantity: item.stock,
            barcode: item.barcode,
          ),
        );
      }
      debugPrint('--- ĐÃ TẠO ${_masterSeedData.length} SẢN PHẨM MẪU ---');
    }
  }

  static Future<void> seedUsers() async {
    final box = users();
    if (box.isEmpty) {
      box.add(User(email: 'abc', password: '123', role: 'owner'));
      box.add(User(email: 'xyz', password: '123', role: 'staff'));
    }
  }

  static Future<void> seedInventory() async {
    final box = inventoryProducts();
    if (box.isEmpty) {
      for (final item in _masterSeedData) {
        await box.put(
          item.barcode,
          InventoryItem(
            id: item.barcode,
            name: item.name,
            price: item.price,
            importPrice: item.importPrice,
            unit: item.unit,
            stockQuantity: item.stock,
          ),
        );
      }
      debugPrint('--- ĐÃ TẠO ${_masterSeedData.length} MẶT HÀNG KHO MẪU ---');
    }
  }

  // ✅ FIXED: tránh trùng instance HiveObject khi đổi key
  static Future<void> _migrateProductsToIdKeys() async {
    final box = products();
    final current = Map<dynamic, Product>.from(
      box.toMap().cast<dynamic, Product>(),
    );

    for (final e in current.entries) {
      final key = e.key;
      final oldProduct = e.value;

      // Chỉ xử lý nếu key không phải String
      if (key is! String) {
        // Tạo bản sao mới để tránh lỗi instance trùng key
        final newProduct = Product(
          id: oldProduct.id,
          name: oldProduct.name,
          price: oldProduct.price,
          unit: oldProduct.unit,
          stockQuantity: oldProduct.stockQuantity,
        );

        await box.put(newProduct.id, newProduct);
        await box.delete(key);
      }
    }
  }

  // --- LOGIC QUẢN LÝ KHO & BÁN HÀNG ---

  static Future<Order> saveOrder(Order order) =>
      CheckoutRepository.create(order);
  static Future<Order> saveOrderWithVoucher(
    Order order, {
    int? voucherId,
    double discountAmount = 0,
    int? userId,
  }) => CheckoutRepository.create(
    order,
    voucherId: voucherId,
    discountAmount: discountAmount,
    userId: userId,
  );

  static List<Product> getAllProducts() {
    return products().values.toList();
  }

  static List<Order> getAllOrders() {
    final allOrders = orders().values.cast<Order>().toList();
    allOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return allOrders;
  }

  static int getOrderCount() {
    return orders().length;
  }

  static double getTotalRevenue() {
    return orders().values.fold(0.0, (sum, order) => sum + order.totalAmount);
  }

  static Map<String, int> getCartForUser(String email) {
    final raw = carts().get(email);
    if (raw == null) return <String, int>{};
    try {
      return Map<String, int>.from(raw as Map);
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> saveCartForUser(String email, Map<String, int> cart) =>
      CartRepository.save(email, cart);
  static Future<Map<String, int>> loadCartForCurrentUser(String email) =>
      CartRepository.load(email);

  static String? currentUserEmail() {
    if (!TokenStore.instance.hasSession) return null;
    final value = settings().get('current_user_email');
    return value is String && value.isNotEmpty ? value : null;
  }

  static int? currentUserId() {
    if (!TokenStore.instance.hasSession) return null;
    final value = settings().get('current_user_id');
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static Future<void> clearAuthSession() async {
    await TokenStore.instance.clear();
    await StoreCacheRepository.coordinator.clear(_clearRuntimeCache);
    final box = settings();
    await Future.wait([
      box.delete('auth_token'),
      box.delete('current_user_id'),
      box.delete('current_user_email'),
      box.delete('current_user_name'),
      box.delete('current_role'),
      box.delete('remember_pass'),
    ]);
  }

  static Future<Product> findSaleProductByCode(String code) =>
      CatalogRepository.scan(code);

  static Future<Map<String, int>> addProductToCurrentCart(
    Product product,
  ) async {
    if (product.stockQuantity <= 0) {
      throw ApiException('Sản phẩm đã hết hàng');
    }

    final email = currentUserEmail();
    if (email == null) {
      throw ApiException('Không tìm thấy người dùng hiện tại');
    }

    final cart = await loadCartForCurrentUser(email);
    final currentQty = cart[product.id] ?? 0;
    if (currentQty + 1 > product.stockQuantity) {
      throw ApiException('Không thể thêm quá số lượng tồn kho');
    }
    cart[product.id] = currentQty + 1;
    await saveCartForUser(email, cart);
    return cart;
  }

  static Future<Product> createProduct(Product product, {String? imagePath}) =>
      CatalogRepository.saveProduct(
        product,
        create: true,
        imagePath: imagePath,
      );

  static Future<Product> updateProductRemote(
    Product product, {
    String? imagePath,
  }) => CatalogRepository.saveProduct(product, imagePath: imagePath);

  static Future<void> deleteProductRemote(Product product) =>
      CatalogRepository.deleteProduct(product);

  static Future<void> importInventoryRemote({
    required InventoryItem item,
    required int quantity,
    required double importPrice,
    String? note,
  }) => CatalogRepository.importStock(
    item: item,
    quantity: quantity,
    importPrice: importPrice,
    note: note,
  );

  static Future<void> adjustInventoryRemote({
    required InventoryItem item,
    required int actualQuantity,
    String? note,
  }) => CatalogRepository.adjust(
    item: item,
    actualQuantity: actualQuantity,
    note: note,
  );

  static Future<InventoryItem> createInventoryItemRemote({
    required String barcode,
    required String name,
    required double price,
    required double importPrice,
    required String unit,
    required int quantity,
    int? categoryId,
    String? imagePath,
  }) => CatalogRepository.create(
    barcode: barcode,
    name: name,
    price: price,
    importPrice: importPrice,
    unit: unit,
    quantity: quantity,
    categoryId: categoryId,
    imagePath: imagePath,
  );

  static Future<double?> fetchLatestImportPrice(String barcode) {
    return ApiService.fetchInventoryImportPrice(barcode);
  }

  static Future<String> generateInternalProductCode({String? prefix}) async {
    for (var attempt = 0; attempt < 20; attempt += 1) {
      final generated = await ApiService.generateProductCode(prefix: prefix);
      final code = generated.trim();
      if (code.isEmpty) continue;
      if (!code.toUpperCase().startsWith('SP')) continue;
      if (await ApiService.productCodeExists(code)) continue;
      return code;
    }
    throw ApiException('Không tạo được mã nội bộ không trùng');
  }

  static Future<InventoryItem?> findInventoryItemByCode(String code) async {
    try {
      final result = await ApiService.scanProductCode(code);
      final itemMap = result['inventory_item'];
      if (itemMap is Map) {
        return InventoryItem.fromJson(Map<String, dynamic>.from(itemMap));
      }
      final productMap = result['product'];
      if (productMap is Map) {
        final product = Product.fromJson(Map<String, dynamic>.from(productMap));
        return InventoryItem(
          id: product.barcode ?? product.id,
          name: product.name,
          price: product.price,
          unit: product.unit,
          stockQuantity: product.stockQuantity,
          imageUrl: product.imageUrl,
        );
      }
    } on ApiException {
      return null;
    }
    return null;
  }

  static Future<Product> releaseInventoryToShelf({
    required InventoryItem item,
    required int quantity,
    required int categoryId,
  }) => CatalogRepository.transfer(item: item, quantity: quantity);

  static List<Product> searchProducts(String query, List<Product> source) {
    if (query.isEmpty) {
      return source;
    }
    final lowerQuery = query.toLowerCase();
    return source
        .where(
          (p) =>
              p.name.toLowerCase().contains(lowerQuery) ||
              p.id.toLowerCase().contains(lowerQuery),
        )
        .toList();
  }
}
