import 'package:flutter_test/flutter_test.dart';
import 'package:sieuthimini/features/catalog/data/cache_sync_policy.dart';
import 'package:sieuthimini/core/data/cache_coordinator.dart';

void main() {
  test('guest never schedules private APIs, even with stale admin role', () {
    expect(CacheSyncPolicy.resources(authenticated: false, role: 'admin'), {
      'products',
    });
  });
  test('authenticated customer can sync own profile without user list', () {
    for (final role in ['customer', 'unknown', null]) {
      expect(CacheSyncPolicy.resources(authenticated: true, role: role), {
        'products',
        'profile',
      });
    }
  });
  test('employee excludes admin user list', () {
    expect(CacheSyncPolicy.resources(authenticated: true, role: 'employee'), {
      'products',
      'profile',
      'inventory',
      'history',
      'orders',
    });
  });
  test('admin syncs all supported resources', () {
    expect(CacheSyncPolicy.resources(authenticated: true, role: 'admin'), {
      'products',
      'profile',
      'inventory',
      'history',
      'orders',
      'users',
    });
  });
  test(
    'discarding inaccessible resource error preserves genuine errors',
    () async {
      final coordinator = CacheCoordinator(scope: () => 'session');
      addTearDown(coordinator.dispose);
      for (final key in ['users', 'products']) {
        await expectLater(
          coordinator.refresh<void>(
            key,
            () async => throw StateError('failed'),
            (_) async {},
          ),
          throwsStateError,
        );
      }
      coordinator.dismissError('users');
      expect(coordinator.errors.keys, ['products']);
    },
  );
}
