import 'package:flutter/material.dart';
import '../../../../utils/product_asset_resolver.dart';

enum TopProductMode { quantity, revenue }

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? borderColor;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.borderColor,
    this.gradient,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? Colors.grey.shade200),
        boxShadow: boxShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(child: trailing!),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
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
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class SalesProductTile extends StatelessWidget {
  final int rank;
  final Map<String, dynamic> product;
  final String name;
  final TopProductMode mode;
  final VoidCallback onTap;

  const SalesProductTile({
    super.key,
    required this.rank,
    required this.product,
    required this.name,
    required this.mode,
    required this.onTap,
  });

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
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')} VNĐ';
  }

  @override
  Widget build(BuildContext context) {
    final sold = _toInt(product['total_quantity_sold']);
    final revenue = _toDouble(product['total_revenue']);
    final ordersCount = _toInt(product['orders_count']);
    final titleValue = mode == TopProductMode.quantity
        ? '$sold đã bán'
        : _formatCurrency(revenue);
    final subtitle = mode == TopProductMode.quantity
        ? '${_formatCurrency(revenue)} · $ordersCount đơn'
        : '$sold sản phẩm · $ordersCount đơn';

    final isBestSellerMode = mode == TopProductMode.quantity;
    final accentColor = isBestSellerMode
        ? const Color(0xFFFF6B00)
        : const Color(0xFF146C43);
    final borderColor = isBestSellerMode
        ? (rank == 1 ? const Color(0xFFFF6B00) : const Color(0xFFFDBA74))
        : Colors.grey.shade200;
    final tileGradient = isBestSellerMode
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: rank == 1
                ? const [Color(0xFFFFEDD5), Color(0xFFFFF7ED)]
                : const [Color(0xFFFFFBEB), Colors.white],
          )
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(rank == 1 && isBestSellerMode ? 12 : 10),
        decoration: BoxDecoration(
          color: tileGradient == null ? Colors.white : null,
          gradient: tileGradient,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: rank == 1 && isBestSellerMode ? 1.6 : 1,
          ),
          boxShadow: isBestSellerMode && rank <= 3
              ? [
                  BoxShadow(
                    color: accentColor.withValues(
                      alpha: rank == 1 ? 0.18 : 0.1,
                    ),
                    blurRadius: rank == 1 ? 18 : 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            RankBadge(
              rank: rank,
              color: accentColor,
              featured: isBestSellerMode,
            ),
            const SizedBox(width: 10),
            ProductThumb(
              product: product,
              size: rank == 1 && isBestSellerMode ? 56 : 50,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (isBestSellerMode && rank <= 3) ...[
                        const SizedBox(width: 6),
                        StatusBadge(
                          label: rank == 1 ? 'HOT NHẤT' : 'BÁN CHẠY',
                          color: accentColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                titleValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: isBestSellerMode
                      ? const Color(0xFFC2410C)
                      : Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlertProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final String name;
  final String badge;
  final Color badgeColor;
  final String titleValue;
  final String subtitle;
  final VoidCallback onTap;

  const AlertProductTile({
    super.key,
    required this.product,
    required this.name,
    required this.badge,
    required this.badgeColor,
    required this.titleValue,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: badgeColor.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: [
            ProductThumb(product: product, size: 50),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(label: badge, color: badgeColor),
                const SizedBox(height: 6),
                Text(
                  titleValue,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SuggestionTile extends StatelessWidget {
  final String title;
  final String message;
  final String severity;

  const SuggestionTile({
    super.key,
    required this.title,
    required this.message,
    required this.severity,
  });

  Color get _color {
    switch (severity) {
      case 'success':
        return const Color(0xFF146C43);
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  IconData get _icon {
    switch (severity) {
      case 'success':
        return Icons.trending_up_outlined;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProductThumb extends StatelessWidget {
  final Map<String, dynamic> product;
  final double size;

  const ProductThumb({super.key, required this.product, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = (product['image_url'] ?? '').toString();
    final resolvedUrl = imageUrl;
    final fallbackAsset = ProductAssetResolver.forMap(product);
    final fallback = Image.asset(
      fallbackAsset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        ProductAssetResolver.defaultProductAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.startsWith('assets/')
            ? fallback
            : resolvedUrl.startsWith('http')
            ? Image.network(
                resolvedUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class RankBadge extends StatelessWidget {
  final int rank;
  final Color color;
  final bool featured;

  const RankBadge({
    super.key,
    required this.rank,
    this.color = const Color(0xFF146C43),
    this.featured = false,
  });

  @override
  Widget build(BuildContext context) {
    final isChampion = featured && rank == 1;

    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isChampion ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: featured
            ? Border.all(color: color.withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        '#$rank',
        style: TextStyle(
          color: isChampion ? Colors.white : color,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const DetailRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Center(
        child: Column(
          children: [
            Icon(icon, color: Colors.black26, size: 38),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
