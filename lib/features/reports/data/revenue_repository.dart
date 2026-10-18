import '../../../models/order.dart';
import '../../../utils/type_converters.dart';
import '../domain/report_query.dart';
import '../domain/revenue_chart_data.dart';
import 'report_source.dart';

class RevenueRepository {
  final ReportSource source;
  RevenueRepository(this.source);
  Future<RevenueDashboardData> load(ReportQuery query) async {
    final userId = source.userId;
    if (userId == null) throw const ReportFailure('Thiếu thông tin đăng nhập');
    final revenue = await source.revenue(userId);
    final orders = await source.orders();
    final filtered = orders
        .where((order) => query.contains(order.orderDate))
        .toList();
    // Bound detail requests rather than issuing one request per order concurrently.
    final detailed = <Order>[];
    for (var offset = 0; offset < filtered.length; offset += 6) {
      detailed.addAll(
        await Future.wait(
          filtered
              .skip(offset)
              .take(6)
              .map((order) => source.orderDetail(order.id)),
        ),
      );
    }
    // A failed detail request must surface as an error, not all-time fallback totals.
    return RevenueDashboardData(
      revenue: _calculateFilteredRevenue(revenue, detailed),
    );
  }

  Map<String, dynamic> _calculateFilteredRevenue(
    Map<String, dynamic> baseRevenue,
    List<Order> orders,
  ) {
    final filtered = Map<String, dynamic>.from(baseRevenue);
    double totalNetRevenue = 0; // after discount
    double totalDiscount = 0;
    double totalGrossRevenue = 0; // before discount
    int totalOrders = 0;
    int totalProductsSold = 0;
    final revenueByDate = <String, Map<String, dynamic>>{};
    final revenueByMonth = <String, Map<String, dynamic>>{};
    final revenueByYear = <String, Map<String, dynamic>>{};

    for (final order in orders) {
      totalNetRevenue += order.totalAmount;
      totalDiscount += order.discountAmount;
      final grossRevenue = order.totalAmount + order.discountAmount;
      totalGrossRevenue += grossRevenue;
      totalOrders += 1;
      totalProductsSold += order.items.fold<int>(
        0,
        (sum, item) => sum + item.quantity,
      );
      _addRevenueBucket(
        revenueByDate,
        TypeConverters.localDateKey(order.orderDate),
        grossRevenue,
      );
      final local = order.orderDate.toLocal();
      _addRevenueBucket(
        revenueByMonth,
        '${local.year}-${local.month.toString().padLeft(2, '0')}-01',
        grossRevenue,
      );
      _addRevenueBucket(revenueByYear, '${local.year}-01-01', grossRevenue);
    }

    final averageOrderValue = totalOrders > 0
        ? totalGrossRevenue / totalOrders
        : 0;

    filtered['total_revenue'] = totalGrossRevenue;
    filtered['total_orders'] = totalOrders;
    filtered['total_net_revenue'] = totalNetRevenue;
    filtered['average_order_value'] = averageOrderValue;
    filtered['total_discount'] = totalDiscount;
    filtered['total_products_sold'] = totalProductsSold;
    filtered['revenue_by_time'] = _sortedRevenueBuckets(revenueByDate);
    filtered['revenue_by_month'] = _sortedRevenueBuckets(revenueByMonth);
    filtered['revenue_by_year'] = _sortedRevenueBuckets(revenueByYear);

    return filtered;
  }

  void _addRevenueBucket(
    Map<String, Map<String, dynamic>> buckets,
    String period,
    double revenue,
  ) {
    final bucket = buckets.putIfAbsent(
      period,
      () => {'period': period, 'revenue': 0.0, 'orders_count': 0},
    );
    bucket['revenue'] = _toDouble(bucket['revenue']) + revenue;
    bucket['orders_count'] = _toInt(bucket['orders_count']) + 1;
  }

  List<Map<String, dynamic>> _sortedRevenueBuckets(
    Map<String, Map<String, dynamic>> buckets,
  ) {
    return buckets.values.toList()..sort(
      (a, b) => a['period'].toString().compareTo(b['period'].toString()),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
