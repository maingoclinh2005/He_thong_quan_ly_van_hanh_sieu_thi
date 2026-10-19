import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sieuthimini/core/data/cache_coordinator.dart';
import 'package:sieuthimini/features/catalog/data/store_cache_repository.dart';
import 'package:sieuthimini/features/cart/application/cart_controller.dart';
import 'package:sieuthimini/features/checkout/application/checkout_controller.dart';
import 'package:sieuthimini/features/checkout/data/submission_guard.dart';
import 'package:sieuthimini/services/api_service.dart';
import 'package:sieuthimini/models/order.dart';

Order savedOrder([String id = '42']) => Order(
  id: id,
  orderDate: DateTime(2026, 10, 19),
  totalAmount: 100,
  customerName: 'Test',
  status: 'pending',
  items: [],
);
void main() {
  test('sync shares in-flight read and writes are serialized', () async {
    final c = CacheCoordinator(scope: () => 'user1');
    addTearDown(c.dispose);
    final gate = Completer<int>();
    final values = <int>[];
    final first = c.refresh(
      'products',
      () => gate.future,
      (v) async => values.add(v),
    );
    final same = c.refresh(
      'products',
      () => Future.value(9),
      (v) async => values.add(v),
    );
    expect(identical(first, same), true);
    var writes = 0;
    final write = c.mutate('products', () async {
      writes++;
      return 2;
    }, (v) async => values.add(v));
    final fresh = c.refresh(
      'products',
      () => Future.value(3),
      (v) async => values.add(v),
    );
    expect(identical(first, fresh), false);
    gate.complete(1);
    await Future.wait([first, write, fresh]);
    expect(values, [1, 2, 3]);
    expect(writes, 1);
  });
  test(
    'cache failure preserves remote success, exposes warning and never repeats write',
    () async {
      final c = CacheCoordinator(scope: () => 'user1');
      addTearDown(c.dispose);
      var calls = 0;
      final result = await c.mutate('orders', () async {
        calls++;
        return 42;
      }, (_) async => throw StateError('disk'));
      expect(result, 42);
      expect(calls, 1);
      expect(c.errors.containsKey('orders'), true);
      await c.refresh('orders', () => Future.value(42), (_) async {});
      expect(c.errors, isEmpty);
      expect(calls, 1);
    },
  );
  test('read failure preserves old cache and queue continues', () async {
    final c = CacheCoordinator(scope: () => 'user1');
    addTearDown(c.dispose);
    var cache = 4;
    await expectLater(
      c.refresh<int>(
        'products',
        () async => throw StateError('offline'),
        (v) async => cache = v,
      ),
      throwsStateError,
    );
    expect(cache, 4);
    await c.refresh('products', () => Future.value(0), (v) async => cache = v);
    expect(cache, 0);
  });
  test(
    'logout prevents stale response/cache resurrection and queued writes',
    () async {
      var scope = 'user1';
      var cache = 7;
      var writes = 0;
      final c = CacheCoordinator(scope: () => scope);
      addTearDown(c.dispose);
      final gate = Completer<int>();
      final started = Completer<void>();
      final read = c.refresh('products', () {
        started.complete();
        return gate.future;
      }, (v) async => cache = v);
      final readCheck = expectLater(read, throwsA(isA<SessionChanged>()));
      await started.future;
      final write = c.mutate('products', () async {
        writes++;
        return 3;
      }, (v) async => cache = v);
      final writeCheck = expectLater(write, throwsA(isA<SessionChanged>()));
      scope = 'user2';
      final clear = c.clear(() async => cache = 0);
      gate.complete(99);
      await Future.wait([readCheck, writeCheck, clear]);
      expect(cache, 0);
      expect(writes, 0);
    },
  );
  test(
    'confirmed old-session result is returned but not cached for next user',
    () async {
      var scope = 'a';
      var applied = false;
      final c = CacheCoordinator(scope: () => scope);
      addTearDown(c.dispose);
      final gate = Completer<int>(), started = Completer<void>();
      final work = c.mutate('orders', () {
        started.complete();
        return gate.future;
      }, (_) async => applied = true);
      await started.future;
      scope = 'b';
      gate.complete(1);
      expect(await work, 1);
      expect(applied, false);
    },
  );
  test(
    'Hive replacement removes obsolete rows and accepts empty authoritative list',
    () async {
      final dir = await Directory.systemTemp.createTemp('store-cache-test-');
      Hive.init(dir.path);
      final box = await Hive.openBox<int>('snapshot');
      try {
        await box.putAll({'old': 1, 'keep': 2});
        await StoreCacheRepository.replace(box, {'keep': 3, 'new': 4});
        expect(box.toMap(), {'keep': 3, 'new': 4});
        await StoreCacheRepository.replace<int>(box, {});
        expect(box.isEmpty, true);
      } finally {
        await box.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'cart load arriving after an edit does not overwrite local draft',
    () async {
      final load = Completer<Map<String, int>>();
      final writes = <Map<String, int>>[];
      final c = CartController(
        loadCart: () => load.future,
        saveCart: (value) async => writes.add(value),
      );
      addTearDown(c.dispose);
      final work = c.load();
      c.items['p'] = 2;
      await c.persist();
      load.complete({'old': 1});
      await work;
      expect(c.items, {'p': 2});
      expect(writes, [
        {'p': 2},
      ]);
    },
  );
  test(
    'cart save errors are surfaced and retry uses snapshot, not shared mutable map',
    () async {
      var fail = true;
      final writes = <Map<String, int>>[];
      final c = CartController(
        loadCart: () async => {},
        saveCart: (value) async {
          writes.add(value);
          if (fail) throw StateError('offline');
        },
      );
      addTearDown(c.dispose);
      c.items['p'] = 1;
      await c.persist();
      expect(c.error, isNotNull);
      c.items['p'] = 2;
      fail = false;
      await c.persist();
      expect(c.error, isNull);
      expect(writes.first, {'p': 1});
    },
  );
  test(
    'checkout double tap and later retry return the same server order',
    () async {
      final c = CheckoutController();
      addTearDown(c.dispose);
      final gate = Completer<Order>();
      var calls = 0;
      Future<Order> create() {
        calls++;
        return gate.future;
      }

      final a = c.submit(create), b = c.submit(create);
      expect(identical(a, b), true);
      gate.complete(savedOrder());
      expect((await a).id, '42');
      await b;
      expect((await c.submit(create)).id, '42');
      expect(calls, 1);
    },
  );
  test(
    'checkout timeout is not automatically resubmitted; explicit 4xx can retry',
    () async {
      final c = CheckoutController();
      addTearDown(c.dispose);
      var calls = 0;
      Future<Order> create() async {
        calls++;
        throw TimeoutException('lost response');
      }

      await expectLater(c.submit(create), throwsA(isA<CheckoutUncertain>()));
      await expectLater(c.submit(create), throwsA(isA<CheckoutUncertain>()));
      expect(calls, 1);
      final rejected = CheckoutController();
      addTearDown(rejected.dispose);
      await expectLater(
        rejected.submit(
          () async => throw ApiException('invalid', statusCode: 400),
        ),
        throwsA(isA<ApiException>()),
      );
      expect((await rejected.submit(() async => savedOrder())).id, '42');
    },
  );
  test(
    'checkout completion after disposal does not notify a closed view',
    () async {
      final c = CheckoutController();
      final gate = Completer<Order>();
      var events = 0;
      c.addListener(() => events++);
      final work = c.submit(() => gate.future);
      c.dispose();
      gate.complete(savedOrder());
      await work;
      expect(events, 1);
    },
  );
  test(
    'persistent unknown marker blocks a new controller/process attempt',
    () async {
      final markers = <String, Map<String, dynamic>>{};
      var calls = 0;
      SubmissionGuard guard() => SubmissionGuard(
        read: (k) => markers[k],
        write: (k, v) async => markers[k] = v,
        remove: (k) async => markers.remove(k),
        recover: (id) async => savedOrder(id),
        scope: () => 'user1',
      );
      await expectLater(
        guard().execute('u', () async {
          calls++;
          throw TimeoutException('unknown');
        }),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        guard().execute('u', () async {
          calls++;
          return savedOrder();
        }),
        throwsA(isA<CheckoutUncertain>()),
      );
      expect(calls, 1);
    },
  );
  test(
    'receipt recovery and known rejection do not duplicate order creation',
    () async {
      final markers = <String, Map<String, dynamic>>{};
      final guard = SubmissionGuard(
        read: (k) => markers[k],
        write: (k, v) async => markers[k] = v,
        remove: (k) async => markers.remove(k),
        recover: (id) async => savedOrder(id),
        scope: () => 'user1',
      );
      await expectLater(
        guard.execute(
          'u',
          () async => throw ApiException('invalid', statusCode: 422),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(markers, isEmpty);
      expect((await guard.execute('u', () async => savedOrder())).id, '42');
      expect(
        (await guard.execute(
          'u',
          () async => throw StateError('must not create'),
        )).id,
        '42',
      );
    },
  );
  test('receipt disk failure does not lose confirmed result', () async {
    final markers = <String, Map<String, dynamic>>{};
    final guard = SubmissionGuard(
      read: (k) => markers[k],
      write: (k, v) async {
        if (v.containsKey('order_id')) throw StateError('disk full');
        markers[k] = v;
      },
      remove: (k) async => markers.remove(k),
      recover: (id) async => savedOrder(id),
      scope: () => 'user1',
    );
    expect((await guard.execute('u', () async => savedOrder())).id, '42');
    expect(markers['u']!.containsKey('started_at'), true);
  });
  test(
    'session change while persisting marker never sends order with new credentials',
    () async {
      var scope = 'old';
      var calls = 0;
      final guard = SubmissionGuard(
        read: (_) => null,
        write: (_, __) async => scope = 'new',
        remove: (_) async {},
        recover: (id) async => savedOrder(id),
        scope: () => scope,
      );
      await expectLater(
        guard.execute('u', () async {
          calls++;
          return savedOrder();
        }),
        throwsA(isA<SessionChanged>()),
      );
      expect(calls, 0);
    },
  );
  test(
    'feature modules stay under 1000 lines; legacy routes remain exports',
    () {
      for (final name in ['catalog', 'cart', 'checkout', 'home']) {
        for (final file
            in Directory('lib/features/$name')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))) {
          expect(
            file.readAsLinesSync().length,
            lessThan(1000),
            reason: file.path,
          );
        }
      }
      for (final name in [
        'home_screen',
        'payment_screen',
        'checkout_screen',
        'customer_online_checkout_screen',
        'inventory_management_screen',
        'product_management_screen',
      ]) {
        expect(
          File('lib/screens/$name.dart').readAsStringSync(),
          contains('export '),
        );
      }
    },
  );
}
