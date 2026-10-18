import 'package:flutter/material.dart';
import 'widgets/performance_widgets.dart';

class ProductPerformanceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> product;
  final int? rank;

  const ProductPerformanceDetailScreen({
    super.key,
    required this.product,
    this.rank,
  });

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _formatCurrency(num amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} VNĐ';
  }

  String _productName() {
    final name = (product['product_name'] ?? '').toString().trim();
    return name.isEmpty ? 'Sản phẩm chưa đặt tên' : name;
  }

  @override
  Widget build(BuildContext context) {
    final sold = _toInt(product['total_quantity_sold']);
    final revenue = _toDouble(product['total_revenue']);
    final stock = _toInt(product['current_stock']);
    final ordersCount = _toInt(product['orders_count']);
    final unit = (product['unit'] ?? 'sp').toString();
    final salePrice = _toDouble(product['sale_price'] ?? product['price']);
    final daysWithoutOrder = _toInt(product['days_without_order']);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Chi tiết sản phẩm'),
        backgroundColor: const Color(0xFF146C43),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 180,
              child: ProductThumb(product: product, size: double.infinity),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rank != null) ...[
                RankBadge(rank: rank!),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _productName(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${product['category_name'] ?? 'Chưa phân loại'} • ${product['barcode'] ?? 'Chưa có mã'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final ratio = constraints.maxWidth < 380 ? 1.35 : 1.8;
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: ratio,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  MetricCard(
                    title: 'Đã bán',
                    value: '$sold $unit',
                    subtitle: 'Trong kỳ lọc',
                    icon: Icons.shopping_bag_outlined,
                    color: const Color(0xFF146C43),
                  ),
                  MetricCard(
                    title: 'Doanh thu',
                    value: _formatCurrency(revenue),
                    subtitle: '$ordersCount đơn hàng',
                    icon: Icons.payments_outlined,
                    color: Colors.orange.shade700,
                  ),
                  MetricCard(
                    title: 'Tồn kho',
                    value: '$stock $unit',
                    subtitle: 'Hiện tại',
                    icon: Icons.warehouse_outlined,
                    color: Colors.blueGrey,
                  ),
                  MetricCard(
                    title: 'Giá bán',
                    value: salePrice <= 0
                        ? 'Chưa có'
                        : _formatCurrency(salePrice),
                    subtitle: 'Giá niêm yết',
                    icon: Icons.sell_outlined,
                    color: Colors.indigo,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Thông tin phân tích',
            child: Column(
              children: [
                DetailRow('Số đơn', '$ordersCount'),
                DetailRow('Số ngày không phát sinh đơn', '$daysWithoutOrder'),
                DetailRow('Mã sản phẩm', '${product['product_id'] ?? '-'}'),
                DetailRow('Mã vạch', '${product['barcode'] ?? '-'}'),
                DetailRow('Danh mục', '${product['category_name'] ?? '-'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
