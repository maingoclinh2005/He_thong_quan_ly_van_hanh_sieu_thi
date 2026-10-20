import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sieuthimini/screens/admin_vouchers_screen.dart';
import 'package:sieuthimini/screens/apply_voucher_screen.dart';
import 'package:sieuthimini/services/api_service.dart';
import 'package:sieuthimini/widgets/voucher_input_widget.dart';

void main() {
  late Completer<http.Response> response;
  var requests = 0;

  setUpAll(() {
    // Initialize the shared client inside a mocked HTTP zone: no real API calls.
    http.runWithClient(
      () => ApiService.client,
      () => MockClient((request) {
        requests++;
        return response.future;
      }),
    );
  });

  setUp(() {
    requests = 0;
  });

  for (final screen in <Widget>[
    const AdminVouchersScreen(token: 'test'),
    const ApplyVoucherScreen(orderTotal: 100000, userId: 1),
  ]) {
    testWidgets('${screen.runtimeType}: late load after dispose is safe', (
      tester,
    ) async {
      response = Completer<http.Response>();
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete(http.Response('{"data":[]}', 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delete uses the screen context after the dialog closes', (
    tester,
  ) async {
    response = Completer<http.Response>();
    await tester.pumpWidget(
      const MaterialApp(home: AdminVouchersScreen(token: 'test')),
    );
    await tester.pump();
    expect(requests, 1);
    response.complete(
      http.Response(
        '{"data":[{"id":1,"code":"TEST","discount_value":1000}]}',
        200,
      ),
    );
    await tester.pumpAndSettle();
    response = Completer<http.Response>();
    await tester.tap(find.text('TEST'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Xóa')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    response.complete(http.Response('{"success":true,"data":[]}', 200));
    await tester.pumpAndSettle();
    expect(find.text('Xóa thành công'), findsOneWidget);
    expect(requests, 3); // Initial list, delete, refreshed list.
    expect(tester.takeException(), isNull);
  });

  testWidgets('late voucher validation does not notify a disposed parent', (
    tester,
  ) async {
    response = Completer<http.Response>();
    var notifications = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoucherInputWidget(
            orderTotal: 100000,
            userId: 1,
            onVoucherChanged: (_) => notifications++,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'TEST');
    await tester.tap(find.text('Áp dụng'));
    await tester.pump();
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete(
      http.Response('{"success":false,"message":"Invalid voucher"}', 400),
    );
    await tester.pumpAndSettle();
    expect(notifications, 0);
    expect(tester.takeException(), isNull);
  });
}
