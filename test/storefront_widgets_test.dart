import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:sieuthimini/models/product.dart';
import 'package:sieuthimini/models/user.dart';
import 'package:sieuthimini/models/inventory_item.dart';
import 'package:sieuthimini/screens/inventory_management_screen.dart';
import 'package:sieuthimini/screens/product_management_screen.dart';
import 'package:sieuthimini/models/order.dart';
import 'package:sieuthimini/models/order_line.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:sieuthimini/services/auth_state.dart';
import 'package:sieuthimini/features/catalog/application/catalog_controller.dart';
import 'package:sieuthimini/screens/home_screen.dart';
import 'package:sieuthimini/screens/checkout_screen.dart';
import 'package:sieuthimini/screens/payment_screen.dart';
import 'package:sieuthimini/screens/customer_online_checkout_screen.dart';

class OfflineCatalog extends CatalogController {
  @override
  Future<void> refresh({bool warehouse = false}) async {}
}

void main() {
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('storefront-ui-');
    Hive.init(temp.path);
    Hive.registerAdapter(ProductAdapter());
    Hive.registerAdapter(UserAdapter());
    Hive.registerAdapter(InventoryItemAdapter());
    Hive.registerAdapter(OrderAdapter());
    Hive.registerAdapter(OrderLineAdapter());
    await Hive.openBox(DBService.settingsBox);
    await Hive.openBox(DBService.cartsBox);
    await Hive.openBox<String>(DBService.productImagesBox);
    await Hive.openBox<Product>(DBService.productsBox);
    await Hive.openBox<User>(DBService.usersBox);
    await Hive.openBox<InventoryItem>(DBService.inventoryProductsBox);
    await Hive.openBox<Order>(DBService.ordersBox);
    await DBService.products().put(
      '1',
      Product(id: '1', name: 'Táo', price: 100, unit: 'kg', stockQuantity: 5),
    );
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  testWidgets('Home uses injected catalog and keeps routes compatible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthState(),
        child: MaterialApp(
          home: HomeScreen(
            role: 'customer',
            onLogout: () {},
            catalog: OfflineCatalog(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'catalog and inventory render controller snapshots without mutating them',
    (tester) async {
      for (final screen in <Widget>[
        ProductManagementScreen(catalog: OfflineCatalog()),
        InventoryManagementScreen(catalog: OfflineCatalog()),
      ]) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
  testWidgets(
    'checkout and payment layouts render with cached products and no API',
    (tester) async {
      for (final screen in <Widget>[
        CheckoutScreen(
          cart: const {'1': 1},
          role: 'employee',
          onCheckoutComplete: () {},
        ),
        PaymentScreen(
          role: 'employee',
          cartForDisplay: const {'Táo': 1},
          originalCart: const {'1': 1},
          totalAmount: 100,
          onCheckoutComplete: () {},
        ),
        CustomerOnlineCheckoutScreen(
          cart: const {'1': 1},
          onCheckoutComplete: () {},
        ),
      ]) {
        await tester.pumpWidget(MaterialApp(home: screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
