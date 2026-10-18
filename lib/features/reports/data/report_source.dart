import '../../../models/order.dart';
import '../../../services/api_service.dart';
import '../../../services/db_service.dart';

abstract interface class ReportSource {
  int? get userId;
  Future<Map<String, dynamic>> revenue(int userId);
  Future<List<Order>> orders();
  Future<Order> orderDetail(String id);
  Future<Map<String, dynamic>> performance(
    int userId, {
    required String range,
    String? month,
  });
}

/// Reports are network-only. Hive supplies session identity, never fallback totals.
/// No report API response writes into the shared product/order cache.
class ApiReportSource implements ReportSource {
  @override
  int? get userId => int.tryParse(
    DBService.settings().get('current_user_id')?.toString() ?? '',
  );
  @override
  Future<Map<String, dynamic>> revenue(int userId) =>
      ApiService.fetchRevenueReport(userId);
  @override
  Future<List<Order>> orders() => ApiService.fetchOrders();
  @override
  Future<Order> orderDetail(String id) => ApiService.fetchOrderDetail(id);
  @override
  Future<Map<String, dynamic>> performance(
    int userId, {
    required String range,
    String? month,
  }) => ApiService.fetchProductPerformanceDashboard(
    userId,
    range: range,
    month: month,
  );
}

class ReportFailure implements Exception {
  final String message;
  const ReportFailure(this.message);
}
