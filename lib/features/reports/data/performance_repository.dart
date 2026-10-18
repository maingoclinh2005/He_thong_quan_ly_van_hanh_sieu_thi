import '../../../services/api_service.dart';
import '../../../utils/type_converters.dart';
import '../domain/report_query.dart';
import 'report_source.dart';

class PerformanceRepository {
  final ReportSource source;
  PerformanceRepository(this.source);
  Future<Map<String, dynamic>> load(ReportQuery query) async {
    final userId = source.userId;
    if (userId == null) throw const ReportFailure('Thiếu thông tin đăng nhập');
    final data = await source.performance(
      userId,
      range: query.apiRange,
      month: query.range == ReportRange.month ? query.monthKey : null,
    );
    final result = Map<String, dynamic>.from(data);
    final chart = (data['revenue_chart'] as List?) ?? const [];
    result['revenue_chart'] = chart.map((row) {
      final copy = Map<String, dynamic>.from(row as Map);
      copy['period'] =
          TypeConverters.localDateKeyFromValue(copy['period']) ??
          copy['period'];
      return copy;
    }).toList();
    // Resolve transport-relative URLs at the data boundary, not inside widgets.
    for (final key in [
      'top_products',
      'top_revenue_products',
      'high_stock_products',
      'slow_products',
    ]) {
      result[key] = ((data[key] as List?) ?? const []).map((row) {
        final copy = Map<String, dynamic>.from(row as Map);
        copy['image_url'] = ApiService.resolveBackendUrl(
          (copy['image_url'] ?? '').toString(),
        );
        return copy;
      }).toList();
    }
    return result;
  }
}
