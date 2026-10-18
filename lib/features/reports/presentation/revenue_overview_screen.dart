import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../screens/order_list_screen.dart';
import '../application/report_controller.dart';
import '../data/report_source.dart';
import '../data/revenue_repository.dart';
import '../domain/report_query.dart';
import '../domain/revenue_chart_data.dart';
import 'widgets/revenue_widgets.dart';

class RevenueOverviewScreen extends StatefulWidget {
  final ReportSource? source;
  const RevenueOverviewScreen({super.key, this.source});

  @override
  State<RevenueOverviewScreen> createState() => _RevenueOverviewScreenState();
}

class _RevenueOverviewScreenState extends State<RevenueOverviewScreen> {
  late final ReportController<RevenueDashboardData> _controller;
  DashboardTimeFilter _selectedFilter = DashboardTimeFilter.day;
  late DateTime _visibleRevenueMonth;
  late DateTime _selectedRevenueDate;
  ReportRange get _timeRange => _controller.query.range;
  DateTime get _selectedMonth => _controller.query.month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleRevenueMonth = DateTime(now.year, now.month);
    _selectedRevenueDate = DateTime(now.year, now.month, now.day);
    _controller = ReportController(
      RevenueRepository(widget.source ?? ApiReportSource()).load,
    );
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() => _controller.refresh();
  void _setTimeRange(ReportRange value) => _controller.setRange(value);
  void _changeMonth(int offset) => _controller.changeMonth(offset);

  void _changeRevenueMonth(int monthOffset) {
    setState(() {
      _visibleRevenueMonth = DateTime(
        _visibleRevenueMonth.year,
        _visibleRevenueMonth.month + monthOffset,
      );
      _selectedRevenueDate = DateTime(
        _visibleRevenueMonth.year,
        _visibleRevenueMonth.month,
        1,
      );
    });
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

  String _formatCurrency(num amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} đ';
  }

  String _compactCurrency(num value) {
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)} tỷ';
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)} tr';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    }
    return value.round().toString();
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid(Map<String, dynamic> revenue) {
    final totalRevenue = _toDouble(revenue['total_revenue']);
    final netRevenue = _toDouble(
      revenue['total_net_revenue'] ?? revenue['total_revenue'],
    );
    final totalOrders = _toInt(revenue['total_orders']);
    final averageOrderValue = _toDouble(revenue['average_order_value']);
    final totalDiscount = _toDouble(revenue['total_discount']);
    final totalProfit = revenue['total_profit'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final childAspectRatio = width < 380
            ? 1.05
            : width < 520
            ? 1.18
            : 1.45;

        return GridView.count(
          crossAxisCount: 2,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildKpiCard(
              title: 'Tổng doanh thu',
              value: _formatCurrency(totalRevenue),
              subtitle: 'Doanh thu trước giảm giá',
              icon: Icons.payments_outlined,
              color: Colors.indigo,
            ),
            _buildKpiCard(
              title: 'Tổng số đơn hàng',
              value: '$totalOrders',
              subtitle: 'Đơn đã thanh toán/hoàn thành',
              icon: Icons.receipt_long_outlined,
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderListScreen()),
                );
              },
            ),
            _buildKpiCard(
              title: 'Giá trị trung bình/đơn',
              value: _formatCurrency(averageOrderValue),
              subtitle: 'Theo doanh thu thuần',
              icon: Icons.trending_up_outlined,
              color: Colors.orange,
            ),
            _buildKpiCard(
              title: 'Doanh thu thuần',
              value: _formatCurrency(netRevenue),
              subtitle: 'Sau giảm giá: ${_formatCurrency(totalDiscount)}',
              icon: Icons.account_balance_wallet_outlined,
              color: Colors.blue,
            ),
            if (totalProfit != null)
              _buildKpiCard(
                title: 'Tổng lợi nhuận',
                value: _formatCurrency(_toDouble(totalProfit)),
                subtitle: 'Tính theo giá nhập gần nhất',
                icon: Icons.ssid_chart_outlined,
                color: Colors.teal,
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilterSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<DashboardTimeFilter>(
        segments: const [
          ButtonSegment(
            value: DashboardTimeFilter.day,
            icon: Icon(Icons.today_outlined),
            label: Text('Ngày'),
          ),
          ButtonSegment(
            value: DashboardTimeFilter.month,
            icon: Icon(Icons.calendar_view_month_outlined),
            label: Text('Tháng'),
          ),
          ButtonSegment(
            value: DashboardTimeFilter.year,
            icon: Icon(Icons.event_available_outlined),
            label: Text('Năm'),
          ),
        ],
        selected: {_selectedFilter},
        showSelectedIcon: false,
        onSelectionChanged: (value) {
          setState(() {
            _selectedFilter = value.first;
          });
        },
      ),
    );
  }

  Widget _buildTimeRangeFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<ReportRange>(
            showSelectedIcon: false,
            selected: {_timeRange},
            onSelectionChanged: (value) => _setTimeRange(value.first),
            segments: const [
              ButtonSegment(
                value: ReportRange.today,
                icon: Icon(Icons.today_outlined),
                label: Text('Hôm nay'),
              ),
              ButtonSegment(
                value: ReportRange.sevenDays,
                icon: Icon(Icons.date_range_outlined),
                label: Text('7 ngày'),
              ),
              ButtonSegment(
                value: ReportRange.thirtyDays,
                icon: Icon(Icons.calendar_view_week_outlined),
                label: Text('30 ngày'),
              ),
              ButtonSegment(
                value: ReportRange.month,
                icon: Icon(Icons.calendar_month_outlined),
                label: Text('Theo tháng'),
              ),
            ],
          ),
        ),
        if (_timeRange == ReportRange.month) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Tháng trước',
              ),
              Expanded(
                child: Text(
                  'Tháng ${_selectedMonth.month}/${_selectedMonth.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Tháng sau',
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTrendSection(Map<String, dynamic> revenue) {
    if (_selectedFilter == DashboardTimeFilter.day) {
      return _buildRevenueCalendar(revenue);
    }

    final chartData = TrendChartData.fromApi(revenue, _selectedFilter);

    return DashboardSection(
      title: chartData.title,
      trailing: Text(
        chartData.totalFormatted,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chartData.description,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 280,
            child: chartData.points.isEmpty
                ? const Center(child: Text('Chưa có dữ liệu doanh thu'))
                : BarChart(
                    BarChartData(
                      maxY: chartData.maxY,
                      barGroups: chartData.points.asMap().entries.map((entry) {
                        final index = entry.key;
                        final point = entry.value;
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: point.revenue,
                              width: chartData.barWidth,
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.blue.shade600,
                            ),
                          ],
                        );
                      }).toList(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: chartData.interval,
                        getDrawingHorizontalLine: (value) =>
                            FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 46,
                            interval: chartData.interval,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                _compactCurrency(value),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black54,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 ||
                                  index >= chartData.points.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 8,
                                child: Text(
                                  chartData.points[index].label,
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final point = chartData.points[groupIndex];
                            return BarTooltipItem(
                              '${point.label}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text: _formatCurrency(point.revenue),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueCalendar(Map<String, dynamic> revenue) {
    final calendarData = RevenueCalendarData.fromApi(
      revenue,
      month: _visibleRevenueMonth,
      selectedDate: _selectedRevenueDate,
    );

    return DashboardSection(
      title: 'Quản lý doanh thu theo ngày',
      trailing: Text(
        calendarData.totalFormatted,
        style: TextStyle(
          color: Colors.blue.shade700,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Tháng trước',
                onPressed: () => _changeRevenueMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Tháng ${calendarData.month}/${calendarData.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Chọn một ngày để xem biểu đồ tuần đó',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Tháng sau',
                onPressed: () => _changeRevenueMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DaySummaryPill(
                  label: 'Ngày có doanh thu',
                  value: '${calendarData.revenueDays}',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DaySummaryPill(
                  label: 'Ngày cao nhất',
                  value: calendarData.bestDayLabel,
                  icon: Icons.trending_up,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DaySummaryPill(
                  label: 'Trung bình/ngày',
                  value: _compactCurrency(calendarData.averageRevenue),
                  icon: Icons.insights_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DaySummaryPill(
                  label: 'Ngày đang chọn',
                  value:
                      '${calendarData.selectedDate.day}/${calendarData.selectedDate.month}',
                  icon: Icons.today_outlined,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Lịch doanh thu',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              WeekdayLabel('T2'),
              WeekdayLabel('T3'),
              WeekdayLabel('T4'),
              WeekdayLabel('T5'),
              WeekdayLabel('T6'),
              WeekdayLabel('T7'),
              WeekdayLabel('CN'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: calendarData.cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final cell = calendarData.cells[index];
              if (cell == null) return const SizedBox.shrink();

              final hasRevenue = cell.revenue > 0;
              final isToday = cell.isToday;
              final isSelected = cell.isSelected;
              final isSelectedWeek = cell.isSelectedWeek;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() {
                    _selectedRevenueDate = cell.date;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade100
                        : isSelectedWeek
                        ? Colors.blue.shade50
                        : hasRevenue
                        ? Colors.green.shade50
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade700
                          : isToday
                          ? Colors.blue.shade400
                          : hasRevenue
                          ? Colors.green.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${cell.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: isSelected || isToday
                              ? Colors.blue.shade800
                              : Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hasRevenue ? _compactCurrency(cell.revenue) : '0',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: hasRevenue
                                ? Colors.green.shade800
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Biểu đồ tuần ${calendarData.weekRangeLabel}',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: BarChart(
              BarChartData(
                maxY: calendarData.weekMaxY,
                barGroups: calendarData.weekPoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final point = entry.value;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: point.revenue,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                        color: point.isSelected
                            ? Colors.blue.shade700
                            : Colors.green.shade600,
                      ),
                    ],
                  );
                }).toList(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: calendarData.weekInterval,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      interval: calendarData.weekInterval,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Text(
                          _compactCurrency(value),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 ||
                            index >= calendarData.weekPoints.length) {
                          return const SizedBox.shrink();
                        }
                        final point = calendarData.weekPoints[index];
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          space: 8,
                          child: Text(
                            point.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: point.isSelected
                                  ? Colors.blue.shade800
                                  : Colors.black54,
                              fontWeight: point.isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final point = calendarData.weekPoints[groupIndex];
                      return BarTooltipItem(
                        '${point.label}\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: _formatCurrency(point.revenue),
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountProfitStrip(Map<String, dynamic> revenue) {
    final totalDiscount = _toDouble(revenue['total_discount']);
    final productsSold = _toInt(revenue['total_products_sold']);
    final profitNote = (revenue['profit_note'] ?? '').toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemCount = profitNote.isNotEmpty ? 3 : 2;
        final itemWidth = constraints.maxWidth < 520
            ? constraints.maxWidth
            : (constraints.maxWidth - ((itemCount - 1) * 10)) / itemCount;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: itemWidth,
              child: SmallMetric(
                label: 'Tổng giảm giá',
                value: _formatCurrency(totalDiscount),
                icon: Icons.local_offer_outlined,
                color: Colors.purple,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: SmallMetric(
                label: 'Sản phẩm đã bán',
                value: '$productsSold',
                icon: Icons.inventory_2_outlined,
                color: Colors.cyan,
              ),
            ),
            if (profitNote.isNotEmpty)
              SizedBox(
                width: itemWidth,
                child: SmallMetric(
                  label: 'Ghi chú lợi nhuận',
                  value: 'Thiếu giá nhập',
                  icon: Icons.info_outline,
                  color: Colors.amber,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Consumer<ReportController<RevenueDashboardData>>(
        builder: (context, controller, child) {
          final snapshot = controller.snapshot;
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Dashboard doanh thu'),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Dashboard doanh thu'),
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        snapshot.error is ReportFailure
                            ? (snapshot.error as ReportFailure).message
                            : 'Không tải được báo cáo',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final data = snapshot.data!;

          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FB),
            appBar: AppBar(
              title: const Text('Dashboard doanh thu'),
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: 'Tải lại',
                  icon: const Icon(Icons.refresh),
                  onPressed: _reload,
                ),
              ],
            ),
            body: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tổng quan kinh doanh',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Theo dõi doanh thu, đơn hàng và sản phẩm bán chạy',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    DashboardSection(
                      title: 'Bộ lọc kỳ báo cáo',
                      child: _buildTimeRangeFilter(),
                    ),
                    const SizedBox(height: 14),
                    _buildKpiGrid(data.revenue),
                    const SizedBox(height: 12),
                    _buildDiscountProfitStrip(data.revenue),
                    const SizedBox(height: 18),
                    DashboardSection(
                      title: 'Bộ lọc hiển thị lịch',
                      child: _buildFilterSelector(),
                    ),
                    const SizedBox(height: 14),
                    _buildTrendSection(data.revenue),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
