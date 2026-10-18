import '../../../utils/type_converters.dart';

enum DashboardTimeFilter { day, month, year }

class CalendarCell {
  final DateTime date;
  final int day;
  final double revenue;
  final bool isToday;
  final bool isSelected;
  final bool isSelectedWeek;

  const CalendarCell({
    required this.date,
    required this.day,
    required this.revenue,
    required this.isToday,
    required this.isSelected,
    required this.isSelectedWeek,
  });
}

class DailyRevenuePoint {
  final DateTime date;
  final String label;
  final int day;
  final double revenue;
  final bool isSelected;

  const DailyRevenuePoint({
    required this.date,
    required this.label,
    required this.day,
    required this.revenue,
    required this.isSelected,
  });
}

class RevenueCalendarData {
  final int month;
  final int year;
  final DateTime selectedDate;
  final List<CalendarCell?> cells;
  final List<DailyRevenuePoint> monthPoints;
  final List<DailyRevenuePoint> weekPoints;

  const RevenueCalendarData({
    required this.month,
    required this.year,
    required this.selectedDate,
    required this.cells,
    required this.monthPoints,
    required this.weekPoints,
  });

  double get totalRevenue =>
      monthPoints.fold(0, (sum, point) => sum + point.revenue);

  int get revenueDays => monthPoints.where((point) => point.revenue > 0).length;

  double get averageRevenue {
    if (monthPoints.isEmpty) return 0;
    return totalRevenue / monthPoints.length;
  }

  DailyRevenuePoint? get bestDay {
    if (monthPoints.isEmpty) return null;
    return monthPoints.reduce(
      (best, point) => point.revenue > best.revenue ? point : best,
    );
  }

  String get bestDayLabel {
    final day = bestDay;
    if (day == null || day.revenue <= 0) return 'Chưa có';
    return day.label;
  }

  String get weekRangeLabel {
    if (weekPoints.isEmpty) return '';
    final start = weekPoints.first.date;
    final end = weekPoints.last.date;
    return '${start.day}/${start.month} - ${end.day}/${end.month}';
  }

  double get weekMaxY {
    final highest = weekPoints.fold<double>(
      0,
      (max, point) => point.revenue > max ? point.revenue : max,
    );
    if (highest <= 0) return 1;
    return highest * 1.2;
  }

  double get weekInterval {
    final value = weekMaxY / 4;
    return value <= 0 ? 1 : value;
  }

  String get totalFormatted =>
      '${totalRevenue.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

  factory RevenueCalendarData.fromApi(
    Map<String, dynamic> api, {
    required DateTime month,
    required DateTime selectedDate,
  }) {
    final today = DateTime.now();
    final visibleMonth = DateTime(month.year, month.month);
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final lastDay = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final normalizedSelected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final weekStart = normalizedSelected.subtract(
      Duration(days: normalizedSelected.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 6));
    final revenueByDate = TrendChartData.dailyRevenueMap(api);
    final cells = <CalendarCell?>[];
    final monthPoints = <DailyRevenuePoint>[];

    for (var i = 1; i < firstDay.weekday; i++) {
      cells.add(null);
    }

    for (var day = 1; day <= lastDay; day++) {
      final date = DateTime(visibleMonth.year, visibleMonth.month, day);
      final revenue = revenueByDate[TrendChartData.dateKey(date)] ?? 0;
      final isToday = _isSameDate(date, today);
      final isSelected = _isSameDate(date, normalizedSelected);
      final isSelectedWeek =
          !date.isBefore(weekStart) && !date.isAfter(weekEnd);

      monthPoints.add(
        DailyRevenuePoint(
          date: date,
          label: _weekdayDateLabel(date),
          day: day,
          revenue: revenue,
          isSelected: isSelected,
        ),
      );
      cells.add(
        CalendarCell(
          date: date,
          day: day,
          revenue: revenue,
          isToday: isToday,
          isSelected: isSelected,
          isSelectedWeek: isSelectedWeek,
        ),
      );
    }

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final weekPoints = List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      return DailyRevenuePoint(
        date: date,
        label: _weekdayDateLabel(date),
        day: date.day,
        revenue: revenueByDate[TrendChartData.dateKey(date)] ?? 0,
        isSelected: _isSameDate(date, normalizedSelected),
      );
    });

    return RevenueCalendarData(
      month: visibleMonth.month,
      year: visibleMonth.year,
      selectedDate: normalizedSelected,
      cells: cells,
      monthPoints: monthPoints,
      weekPoints: weekPoints,
    );
  }

  static bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _weekdayDateLabel(DateTime date) {
    const weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    return '${weekdays[date.weekday - 1]}\n${date.day}/${date.month}';
  }
}

class TrendPoint {
  final String label;
  final double revenue;

  const TrendPoint({required this.label, required this.revenue});
}

class TrendChartData {
  final List<TrendPoint> points;
  final DashboardTimeFilter filter;

  const TrendChartData({required this.points, required this.filter});

  String get title {
    switch (filter) {
      case DashboardTimeFilter.day:
        return 'Lịch doanh thu theo ngày';
      case DashboardTimeFilter.month:
        return 'Biểu đồ doanh thu theo tháng';
      case DashboardTimeFilter.year:
        return 'Biểu đồ doanh thu theo năm';
    }
  }

  String get description {
    switch (filter) {
      case DashboardTimeFilter.day:
        return 'Doanh thu từng ngày trong tháng hiện tại';
      case DashboardTimeFilter.month:
        return 'Doanh thu 12 tháng trong năm hiện tại';
      case DashboardTimeFilter.year:
        return 'Doanh thu theo từng năm có dữ liệu';
    }
  }

  double get totalRevenue =>
      points.fold(0, (sum, point) => sum + point.revenue);

  String get totalFormatted =>
      '${totalRevenue.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

  double get maxY {
    final highest = points.fold<double>(
      0,
      (max, point) => point.revenue > max ? point.revenue : max,
    );
    if (highest <= 0) return 1;
    return highest * 1.2;
  }

  double get interval {
    final value = maxY / 4;
    return value <= 0 ? 1 : value;
  }

  double get barWidth {
    switch (filter) {
      case DashboardTimeFilter.day:
        return 10;
      case DashboardTimeFilter.month:
        return 12;
      case DashboardTimeFilter.year:
        return 22;
    }
  }

  factory TrendChartData.fromApi(
    Map<String, dynamic> api,
    DashboardTimeFilter filter,
  ) {
    switch (filter) {
      case DashboardTimeFilter.day:
        return TrendChartData(points: const [], filter: filter);
      case DashboardTimeFilter.month:
        return TrendChartData(
          points: _currentYearMonthPoints(api),
          filter: filter,
        );
      case DashboardTimeFilter.year:
        return TrendChartData(points: _yearPoints(api), filter: filter);
    }
  }

  static List<TrendPoint> _currentYearMonthPoints(Map<String, dynamic> api) {
    final revenueByMonth = monthlyRevenueMap(api);
    final year = DateTime.now().year;
    return List.generate(12, (index) {
      final month = index + 1;
      return TrendPoint(
        label: 'T$month',
        revenue: revenueByMonth[monthKey(year, month)] ?? 0,
      );
    });
  }

  static List<TrendPoint> _yearPoints(Map<String, dynamic> api) {
    final rows = (api['revenue_by_year'] as List?) ?? const [];
    final points = rows.whereType<Map>().map((row) {
      final period = row['period']?.toString() ?? '';
      final year = period.length >= 4 ? period.substring(0, 4) : period;
      return TrendPoint(label: year, revenue: toDoubleValue(row['revenue']));
    }).toList();

    points.sort((a, b) => a.label.compareTo(b.label));
    return points;
  }

  static Map<String, double> dailyRevenueMap(Map<String, dynamic> api) {
    final rows = (api['revenue_by_time'] as List?) ?? const [];
    final result = <String, double>{};
    for (final row in rows.whereType<Map>()) {
      final key = TypeConverters.localDateKeyFromValue(row['period']);
      if (key == null) continue;
      result[key] = (result[key] ?? 0) + toDoubleValue(row['revenue']);
    }
    return result;
  }

  static Map<String, double> monthlyRevenueMap(Map<String, dynamic> api) {
    final rows = (api['revenue_by_month'] as List?) ?? const [];
    final result = <String, double>{};
    for (final row in rows.whereType<Map>()) {
      final key = TypeConverters.localDateKeyFromValue(row['period']);
      if (key == null || key.length < 7) continue;
      final monthKey = key.substring(0, 7);
      result[monthKey] =
          (result[monthKey] ?? 0) + toDoubleValue(row['revenue']);
    }
    return result;
  }

  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String monthKey(int year, int month) {
    return '$year-${month.toString().padLeft(2, '0')}';
  }

  static double toDoubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class RevenueDashboardData {
  final Map<String, dynamic> revenue;

  const RevenueDashboardData({required this.revenue});
}
