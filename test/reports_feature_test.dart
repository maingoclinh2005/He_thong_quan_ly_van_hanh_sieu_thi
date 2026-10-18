import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sieuthimini/features/reports/application/report_controller.dart';
import 'package:sieuthimini/features/reports/data/report_source.dart';
import 'package:sieuthimini/features/reports/data/revenue_repository.dart';
import 'package:sieuthimini/features/reports/data/performance_repository.dart';
import 'package:sieuthimini/features/reports/domain/report_query.dart';
import 'package:sieuthimini/models/order.dart';
import 'package:sieuthimini/screens/RevenueOverviewScreen.dart';
import 'package:sieuthimini/screens/product_performance_report_screen.dart';

class FakeReportSource implements ReportSource {
  @override
  int? userId = 7;
  int performanceCalls = 0;
  int revenueCalls = 0;
  bool fail = false;
  String? lastRange;
  String? lastMonth;
  List<Order> rows = [];
  int activeDetails = 0;
  int peakDetails = 0;
  final detailIds = <String>[];
  @override
  Future<Map<String, dynamic>> revenue(int userId) async {
    revenueCalls++;
    return {'total_revenue': 99999};
  }

  @override
  Future<List<Order>> orders() async => rows;
  @override
  Future<Order> orderDetail(String id) async {
    detailIds.add(id);
    activeDetails++;
    if (activeDetails > peakDetails) peakDetails = activeDetails;
    await Future<void>.delayed(Duration.zero);
    activeDetails--;
    if (fail) throw StateError('detail failed');
    return rows.firstWhere((order) => order.id == id);
  }

  @override
  Future<Map<String, dynamic>> performance(
    int userId, {
    required String range,
    String? month,
  }) async {
    performanceCalls++;
    lastRange = range;
    lastMonth = month;
    if (fail) throw StateError('network failed');
    return {'top_products': [], 'revenue_chart': []};
  }
}

Order order(String id, DateTime date) => Order(
  id: id,
  orderDate: date,
  totalAmount: 90,
  discountAmount: 10,
  customerName: 'Test',
  status: 'completed',
  items: [],
);

void main() {
  test('range boundaries, calendar month and immutable query', () {
    final query = ReportQuery(
      range: ReportRange.sevenDays,
      now: DateTime(2026, 10, 18, 23),
    );
    expect(query.contains(DateTime(2026, 10, 12)), true);
    expect(query.contains(DateTime(2026, 10, 11, 23, 59)), false);
    expect(query.contains(DateTime(2026, 10, 19)), false);
    final month = ReportQuery(
      range: ReportRange.month,
      month: DateTime(2024, 2),
    );
    expect(month.contains(DateTime(2024, 2, 29)), true);
    expect(month.contains(DateTime(2024, 3)), false);
    expect(month.monthKey, '2024-02');
  });
  test(
    'refresh shares in-flight request and only completes when result arrives',
    () async {
      final completer = Completer<int>();
      var calls = 0;
      final controller = ReportController<int>((_) {
        calls++;
        return completer.future;
      });
      addTearDown(controller.dispose);
      final first = controller.refresh(), second = controller.refresh();
      expect(identical(first, second), true);
      expect(calls, 1);
      expect(controller.snapshot.connectionState, ConnectionState.waiting);
      completer.complete(5);
      await first;
      expect(controller.snapshot.data, 5);
    },
  );
  test('new range wins even when old request completes later', () async {
    final old = Completer<String>(), latest = Completer<String>();
    final controller = ReportController<String>(
      (q) => q.range == ReportRange.today ? latest.future : old.future,
    );
    addTearDown(controller.dispose);
    final a = controller.refresh(), b = controller.setRange(ReportRange.today);
    latest.complete('today');
    await b;
    old.complete('old');
    await a;
    expect(controller.snapshot.data, 'today');
    expect(controller.query.range, ReportRange.today);
  });
  test(
    'stale error cannot overwrite data; error can retry; dispose ignores completion',
    () async {
      final old = Completer<int>();
      var calls = 0;
      final controller = ReportController<int>(
        (_) => ++calls == 1 ? old.future : Future.value(8),
      );
      final a = controller.refresh();
      await controller.changeMonth(-1);
      old.completeError(StateError('late'));
      await a;
      expect(controller.snapshot.data, 8);
      controller.dispose();

      var fail = true;
      final retry = ReportController<int>((_) async {
        if (fail) throw StateError('offline');
        return 9;
      });
      await retry.refresh();
      expect(retry.snapshot.hasError, true);
      fail = false;
      await retry.refresh();
      expect(retry.snapshot.data, 9);
      retry.dispose();

      final pending = Completer<int>();
      final disposed = ReportController<int>((_) => pending.future);
      var notifications = 0;
      disposed.addListener(() => notifications++);
      final work = disposed.refresh();
      disposed.dispose();
      pending.complete(1);
      await work;
      expect(notifications, 1);
    },
  );
  test(
    'revenue uses selected period, bounded requests and does not return stale totals on failure',
    () async {
      final source = FakeReportSource();
      source.rows = [
        for (var i = 0; i < 15; i++) order('$i', DateTime(2026, 10, 18)),
        order('old', DateTime(2020)),
      ];
      final repository = RevenueRepository(source);
      final query = ReportQuery(
        range: ReportRange.today,
        now: DateTime(2026, 10, 18),
      );
      final data = await repository.load(query);
      expect(data.revenue['total_revenue'], 1500);
      expect(data.revenue['total_net_revenue'], 1350);
      expect(source.peakDetails, lessThanOrEqualTo(6));
      expect(source.detailIds, hasLength(15));
      source.fail = true;
      await expectLater(repository.load(query), throwsStateError);
      source.fail = false;
      source.rows = [];
      expect((await repository.load(query)).revenue['total_revenue'], 0);
    },
  );
  test(
    'performance sends snapshot filter and never falls back to unrelated report/cache',
    () async {
      final source = FakeReportSource();
      final repository = PerformanceRepository(source);
      await repository.load(
        ReportQuery(range: ReportRange.month, month: DateTime(2026, 9)),
      );
      expect(source.lastRange, 'month');
      expect(source.lastMonth, '2026-09');
      source.fail = true;
      await expectLater(repository.load(ReportQuery()), throwsStateError);
      expect(source.revenueCalls, 0);
      source.userId = null;
      await expectLater(
        repository.load(ReportQuery()),
        throwsA(isA<ReportFailure>()),
      );
      expect(source.performanceCalls, 2);
    },
  );
  testWidgets(
    'performance screen handles error/retry without Hive or real API',
    (tester) async {
      final source = FakeReportSource()..fail = true;
      await tester.pumpWidget(
        MaterialApp(home: ProductPerformanceReportScreen(source: source)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Thử lại'), findsOneWidget);
      source.fail = false;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(source.performanceCalls, 2);
      expect(find.text('Bộ lọc thời gian'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'revenue screen renders empty period through existing route export',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: RevenueOverviewScreen(source: FakeReportSource())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tổng quan kinh doanh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'feature screens do not access storage/network and modules stay under 1000 lines',
    () {
      for (final file
          in Directory('lib/features/reports')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final text = file.readAsStringSync();
        expect(text.split('\n').length, lessThan(1000), reason: file.path);
        if (file.path.contains('presentation')) {
          expect(text, isNot(contains('ApiService.')), reason: file.path);
          expect(text, isNot(contains('DBService.')), reason: file.path);
          expect(text, isNot(contains('Hive.')), reason: file.path);
        }
      }
    },
  );
}
