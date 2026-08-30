/// Centralized constants for the application
/// Avoids duplication of constant values across screens

class AppConstants {
  // Inventory constants
  static const int minStockThreshold = 50;

  // API timeout
  static const int apiTimeoutSeconds = 5;
  static const int shiftTimeoutSeconds = 15;
  static const int checkoutTimeoutSeconds = 12;

  /// Ưu tiên truyền khi chạy:
  /// flutter run --dart-define=API_BASE_URL=http://IP_MAC:3000
  ///
  /// Nếu không truyền dart-define:
  /// - Android emulator dùng http://10.0.2.2:3000 trong ApiService.
  /// - iOS simulator dùng http://localhost:3000 trong ApiService.
  /// - iPhone thật phải truyền IP Wi-Fi hoặc mDNS của Mac bằng dart-define.
  static const String? apiBaseUrlOverride = null;
  static const String iosSimulatorApiBaseUrl = 'http://localhost:3000';

  // Hive box names
  static const String productsBox = 'products';
  static const String usersBox = 'users';
  static const String ordersBox = 'orders';
  static const String settingsBox = 'settings';
  static const String cartsBox = 'carts';
  static const String productImagesBox = 'product_images';
  static const String inventoryProductsBox = 'inventory_products';
  static const String inventoryHistoryBox = 'inventory_history_box';
  static const String workShiftSummariesBox = 'work_shift_summaries';

  // Cache schema
  static const int cacheSchemaVersion = 3;
  static const bool forceUseLocalProductSeed = false;
}
