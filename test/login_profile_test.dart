import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:sieuthimini/models/user.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:sieuthimini/services/token_store.dart';
import 'package:sieuthimini/core/data/cache_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('login-profile-test-');
    Hive.init(directory.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(UserAdapter());
    await Hive.openBox(DBService.settingsBox);
    await Hive.openBox<User>(DBService.usersBox);
    await TokenStore.instance.save(
      {'token': 'test', 'refresh_token': 'test-refresh'},
      expectedGeneration: TokenStore.instance.generation,
      newLogin: true,
    );
    await DBService.settings().put('current_user_id', 2);
    await DBService.settings().put(
      'current_user_email',
      'employee@example.test',
    );
  });
  tearDown(() async {
    await TokenStore.instance.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'employee and customer profile survives without fetching admin users',
    () async {
      for (final role in ['employee', 'customer']) {
        await DBService.cacheLoginProfile({
          'user_id': 2,
          'email': 'employee@example.test',
          'role_name': role,
          'full_name': 'Test profile',
          'password': 'must-not-be-cached',
        });
        final profile = DBService.users().get(DBService.currentUserEmail());
        expect(profile?.fullName, 'Test profile');
        expect(profile?.role, role);
        expect(profile?.password, isEmpty);
        expect(DBService.users().length, 1);
      }
    },
  );
  test('another session profile cannot overwrite current user cache', () async {
    await expectLater(
      DBService.cacheLoginProfile({
        'user_id': 9,
        'email': 'other@example.test',
      }),
      throwsA(isA<SessionChanged>()),
    );
    expect(DBService.users().isEmpty, true);
  });
}
