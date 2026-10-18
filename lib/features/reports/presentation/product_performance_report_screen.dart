import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../application/report_controller.dart';
import '../data/report_source.dart';
import '../data/performance_repository.dart';
import '../domain/report_query.dart';
import 'product_performance_detail_screen.dart';
import 'widgets/performance_widgets.dart';

class ProductPerformanceReportScreen extends StatefulWidget {
  final ReportSource? source;
  const ProductPerformanceReportScreen({super.key, this.source});

  @override
  State<ProductPerformanceReportScreen> createState() =>
      _ProductPerformanceReportScreenState();
}

class _ProductPerformanceReportScreenState
    extends State<ProductPerformanceReportScreen> {
  static const Color _surface = Color(0xFFF5F7FA);
  static const Color _primary = Color(0xFF146C43);
  static const Color _bestSeller = Color(0xFFFF6B00);
  static const Color _bestSellerDark = Color(0xFFC2410C);

  late final ReportController<Map<String, dynamic>> _controller;
  ReportRange get _range => _controller.query.range;
  TopProductMode _topProductMode = TopProductMode.quantity;
  DateTime get _selectedMonth => _controller.query.month;

  @override
  void initState() {
    super.initState();
    _controller = ReportController(
      PerformanceRepository(widget.source ?? ApiReportSource()).load,
    );
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reload() => _controller.refresh();
  void _setRange(ReportRange value) => _controller.setRange(value);
  void _changeMonth(int offset) => _controller.changeMonth(offset);
  void _setTopProductMode(TopProductMode value) =>
      setState(() => _topProductMode = value);

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    return ((value as List?) ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  String _productName(Map<String, dynamic> product) {
    final name = (product['product_name'] ?? '').toString().trim();
    return name.isEmpty ? 'Sản phẩm chưa đặt tên' : name;
  }

  Widget _buildFilterBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<ReportRange>(
            showSelectedIcon: false,
            selected: {_range},
            onSelectionChanged: (value) => _setRange(value.first),
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
        if (_range == ReportRange.month) ...[
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

  Widget _buildTopProductList(
    List<Map<String, dynamic>> topProducts,
    List<Map<String, dynamic>> topRevenueProducts,
  ) {
    final products = _topProductMode == TopProductMode.quantity
        ? topProducts
        : topRevenueProducts;
    final title = _topProductMode == TopProductMode.quantity
        ? 'Bán chạy'
        : 'Bán nhiều tiền';

    final isBestSellerMode = _topProductMode == TopProductMode.quantity;

    return SectionCard(
      title: 'Danh sách sản phẩm',
      borderColor: isBestSellerMode
          ? _bestSeller.withValues(alpha: 0.38)
          : Colors.grey.shade200,
      gradient: isBestSellerMode
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF7ED), Color(0xFFFFFBEB), Colors.white],
            )
          : null,
      boxShadow: isBestSellerMode
          ? [
              BoxShadow(
                color: _bestSeller.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
      trailing: StatusBadge(
        label: isBestSellerMode ? 'TOP BÁN CHẠY' : title,
        color: isBestSellerMode ? _bestSellerDark : _primary,
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TopProductMode>(
              showSelectedIcon: false,
              selected: {_topProductMode},
              onSelectionChanged: (value) => _setTopProductMode(value.first),
              segments: const [
                ButtonSegment(
                  value: TopProductMode.quantity,
                  icon: Icon(Icons.shopping_bag_outlined),
                  label: Text('Bán chạy'),
                ),
                ButtonSegment(
                  value: TopProductMode.revenue,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Bán nhiều tiền'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (products.isEmpty)
            const EmptyState(
              icon: Icons.insights_outlined,
              message: 'Chưa có sản phẩm phát sinh bán trong kỳ này.',
            )
          else
            Column(
              children: products.take(10).toList().asMap().entries.map((entry) {
                return SalesProductTile(
                  rank: entry.key + 1,
                  product: entry.value,
                  name: _productName(entry.value),
                  mode: _topProductMode,
                  onTap: () => _openDetail(entry.value, entry.key + 1),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildHighStock(List<Map<String, dynamic>> products) {
    return SectionCard(
      title: 'Sản phẩm tồn kho cao',
      trailing: const StatusBadge(label: 'Ngưỡng > 50', color: Colors.orange),
      child: products.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'Không có sản phẩm tồn kho cao.',
            )
          : Column(
              children: products
                  .take(8)
                  .map(
                    (product) => AlertProductTile(
                      product: product,
                      name: _productName(product),
                      badge: 'Tồn cao',
                      badgeColor: Colors.orange,
                      titleValue: 'Tồn ${_toInt(product['current_stock'])}',
                      subtitle:
                          'Đã bán ${_toInt(product['total_quantity_sold'])}',
                      onTap: () => _openDetail(product, null),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildSlowProducts(List<Map<String, dynamic>> products) {
    return SectionCard(
      title: 'Sản phẩm bán chậm',
      trailing: const StatusBadge(label: 'Sold < 5', color: Colors.red),
      child: products.isEmpty
          ? const EmptyState(
              icon: Icons.speed_outlined,
              message: 'Không có sản phẩm bán chậm trong kỳ này.',
            )
          : Column(
              children: products
                  .take(8)
                  .map(
                    (product) => AlertProductTile(
                      product: product,
                      name: _productName(product),
                      badge: _slowBadge(product),
                      badgeColor: Colors.red,
                      titleValue:
                          'Đã bán ${_toInt(product['total_quantity_sold'])}',
                      subtitle:
                          '${_toInt(product['days_without_order'])} ngày chưa phát sinh đơn',
                      onTap: () => _openDetail(product, null),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  String _slowBadge(Map<String, dynamic> product) {
    final stock = _toInt(product['current_stock']);
    if (stock > 50) return 'Cần xả kho';
    if (stock > 20) return 'Nên giảm giá';
    return 'Bán chậm';
  }

  Widget _buildSuggestions(List<Map<String, dynamic>> suggestions) {
    return SectionCard(
      title: 'Đề xuất thông minh',
      child: suggestions.isEmpty
          ? const EmptyState(
              icon: Icons.lightbulb_outline,
              message: 'Chưa có đề xuất trong kỳ này.',
            )
          : Column(
              children: suggestions
                  .map(
                    (item) => SuggestionTile(
                      title: (item['title'] ?? '').toString(),
                      message: (item['message'] ?? '').toString(),
                      severity: (item['severity'] ?? 'info').toString(),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  void _openDetail(Map<String, dynamic> product, int? rank) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProductPerformanceDetailScreen(product: product, rank: rank),
      ),
    );
  }

  Widget _buildError(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 42),
            const SizedBox(height: 12),
            Text(
              error is ReportFailure
                  ? error.message
                  : 'Không tải được dashboard hiệu suất sản phẩm',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Hiệu suất sản phẩm'),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: ChangeNotifierProvider.value(
        value: _controller,
        child: Consumer<ReportController<Map<String, dynamic>>>(
          builder: (context, controller, child) {
            final snapshot = controller.snapshot;
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return _buildError(snapshot.error!);

            final data = snapshot.data ?? const <String, dynamic>{};
            final topProducts = _list(data['top_products']);
            final topRevenueProducts = _list(data['top_revenue_products']);
            final highStock = _list(data['high_stock_products']);
            final slowProducts = _list(data['slow_products']);
            final suggestions = _list(data['suggestions']);
            if (topRevenueProducts.isEmpty && topProducts.isNotEmpty) {
              topRevenueProducts.addAll(
                List<Map<String, dynamic>>.from(topProducts)..sort(
                  (a, b) => _toDouble(
                    b['total_revenue'],
                  ).compareTo(_toDouble(a['total_revenue'])),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Bộ lọc thời gian',
                    child: _buildFilterBar(),
                  ),
                  const SizedBox(height: 14),
                  _buildTopProductList(topProducts, topRevenueProducts),
                  const SizedBox(height: 14),
                  _buildHighStock(highStock),
                  const SizedBox(height: 14),
                  _buildSlowProducts(slowProducts),
                  const SizedBox(height: 14),
                  _buildSuggestions(suggestions),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
