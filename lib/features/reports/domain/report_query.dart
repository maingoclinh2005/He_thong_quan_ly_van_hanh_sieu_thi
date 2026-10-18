enum ReportRange { today, sevenDays, thirtyDays, month }

class ReportQuery {
  final ReportRange range;
  final DateTime month;
  final DateTime today;
  const ReportQuery._(this.range, this.month, this.today);
  factory ReportQuery({
    ReportRange range = ReportRange.thirtyDays,
    DateTime? month,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toLocal();
    final selected = month ?? current;
    return ReportQuery._(
      range,
      DateTime(selected.year, selected.month),
      DateTime(current.year, current.month, current.day),
    );
  }

  String get apiRange => switch (range) {
    ReportRange.today => 'today',
    ReportRange.sevenDays => '7days',
    ReportRange.thirtyDays => '30days',
    ReportRange.month => 'month',
  };
  String get monthKey =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';
  bool contains(DateTime value) {
    final local = value.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    if (range == ReportRange.month) {
      return date.year == month.year && date.month == month.month;
    }
    final days = range == ReportRange.today
        ? 0
        : range == ReportRange.sevenDays
        ? 6
        : 29;
    final start = DateTime(today.year, today.month, today.day - days);
    return !date.isBefore(start) && !date.isAfter(today);
  }
}
