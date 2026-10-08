import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sieuthimini/services/token_store.dart';
import 'package:sieuthimini/services/session_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TokenStore store;
  test(
    'legacy Hive token and saved password are removed; user must log in again',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp(
        'auth-migration-test-',
      );
      Hive.init(temp.path);
      final box = await Hive.openBox(DBService.settingsBox);
      try {
        await box.putAll({
          'auth_token': 'legacy-jwt',
          'remember_pass': 'legacy-password',
          'current_user_id': 1,
          'current_role': 'admin',
          'welcomeSeen': true,
        });
        await DBService.initializeAuthStorage();
        expect(box.containsKey('auth_token'), false);
        expect(box.containsKey('remember_pass'), false);
        expect(box.containsKey('current_user_id'), false);
        expect(box.get('welcomeSeen'), true);
        expect(TokenStore.instance.hasSession, false);
      } finally {
        await Hive.close();
        await temp.delete(recursive: true);
      }
    },
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = TokenStore();
    await store.save(
      {'token': 'old', 'refresh_token': 'refresh-old'},
      expectedGeneration: 0,
      newLogin: true,
    );
  });
  test(
    'secure record restores both tokens and clear removes persistent credentials',
    () async {
      final restored = TokenStore();
      await restored.initialize();
      expect(restored.accessToken, 'old');
      expect(restored.refreshToken, 'refresh-old');
      await restored.clear();
      final empty = TokenStore();
      await empty.initialize();
      expect(empty.hasSession, false);
    },
  );
  test(
    'concurrent 401s share one refresh; retries keep original request body',
    () async {
      var refreshes = 0;
      final client = SessionClient(
        baseUrl: () => 'https://api.test',
        tokens: store,
        transport: MockClient((request) async {
          if (request.url.path == '/api/auth/refresh') {
            refreshes++;
            expect(jsonDecode(request.body)['refresh_token'], 'refresh-old');
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response(
              jsonEncode({'token': 'new', 'refresh_token': 'refresh-new'}),
              200,
            );
          }
          expect(request.body, 'original-body');
          return http.Response(
            '{}',
            request.headers['Authorization'] == 'Bearer new' ? 200 : 401,
          );
        }),
      );
      final results = await Future.wait(
        List.generate(
          5,
          (_) => client.post(
            Uri.parse('https://api.test/api/orders'),
            body: 'original-body',
          ),
        ),
      );
      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(refreshes, 1);
      expect(store.refreshToken, 'refresh-new');
    },
  );
  test(
    'refresh rejection clears session; temporary server failure does not',
    () async {
      for (final status in [503, 401]) {
        final client = SessionClient(
          baseUrl: () => 'https://api.test',
          tokens: store,
          transport: MockClient(
            (request) async => http.Response(
              '{}',
              request.url.path.endsWith('/refresh') ? status : 401,
            ),
          ),
        );
        expect(
          (await client.get(Uri.parse('https://api.test/private'))).statusCode,
          401,
        );
        expect(store.hasSession, status == 503);
      }
    },
  );
  test('late refresh cannot restore a session after local logout', () async {
    final started = Completer<void>(), release = Completer<void>();
    final client = SessionClient(
      baseUrl: () => 'https://api.test',
      tokens: store,
      transport: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          await release.future;
          return http.Response(
            jsonEncode({'token': 'new', 'refresh_token': 'new-refresh'}),
            200,
          );
        }
        return http.Response('{}', 401);
      }),
    );
    final pending = client.get(Uri.parse('https://api.test/private'));
    await started.future;
    await store.clear();
    release.complete();
    await pending;
    expect(store.hasSession, false);
    final restored = TokenStore();
    await restored.initialize();
    expect(restored.hasSession, false);
  });
  test(
    'public auth gets no bearer, redirects disabled, different hosts rejected',
    () async {
      var sent = 0;
      final client = SessionClient(
        baseUrl: () => 'https://api.test',
        tokens: store,
        transport: MockClient((request) async {
          sent++;
          expect(request.headers.containsKey('Authorization'), false);
          expect(request.followRedirects, false);
          return http.Response('{}', 401);
        }),
      );
      await client.post(Uri.parse('https://api.test/api/auth/login'));
      expect(sent, 1);
      await expectLater(
        client.get(Uri.parse('https://evil.test/private')),
        throwsArgumentError,
      );
    },
  );
  test(
    'multipart bytes and content type survive authentication retry',
    () async {
      String? original;
      final client = SessionClient(
        baseUrl: () => 'https://api.test',
        tokens: store,
        transport: MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            return http.Response(
              jsonEncode({'token': 'new', 'refresh_token': 'new-refresh'}),
              200,
            );
          }
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          original ??= request.body;
          expect(request.body, original);
          expect(request.body, contains('image-data'));
          return http.Response(
            '{}',
            request.headers['Authorization'] == 'Bearer new' ? 201 : 401,
          );
        }),
      );
      final upload =
          http.MultipartRequest(
              'POST',
              Uri.parse('https://api.test/api/uploads/product-image'),
            )
            ..files.add(
              http.MultipartFile.fromString(
                'image',
                'image-data',
                filename: 'test.png',
              ),
            );
      expect((await client.send(upload)).statusCode, 201);
    },
  );
}
