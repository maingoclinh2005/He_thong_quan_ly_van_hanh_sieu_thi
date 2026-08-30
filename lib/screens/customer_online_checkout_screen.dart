import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/voucher.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/voucher_service.dart';
import '../utils/product_asset_resolver.dart';
import '../widgets/product_image_widget.dart';
import '../widgets/slide_page_route.dart';
import 'orders_screen.dart';
import 'vnpay_payment_screen.dart';

class CustomerOnlineCheckoutScreen extends StatefulWidget {
  final Map<String, int> cart;
  final VoidCallback onCheckoutComplete;

  const CustomerOnlineCheckoutScreen({
    super.key,
    required this.cart,
    required this.onCheckoutComplete,
  });

  @override
  State<CustomerOnlineCheckoutScreen> createState() =>
      _CustomerOnlineCheckoutScreenState();
}

class _CustomerOnlineCheckoutScreenState
    extends State<CustomerOnlineCheckoutScreen> {
  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF111827);

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late final Map<String, int> _cart;

  String _deliveryMethod = 'pickup';
  String _paymentMethod = 'cash';
  bool _isApplyingVoucher = false;
  bool _isLoadingSavedVouchers = true;
  bool _isCheckingOut = false;
  String? _voucherCode;
  String? _voucherMessage;
  double _discountAmount = 0;
  List<Voucher> _savedVouchers = [];

  @override
  void initState() {
    super.initState();
    _cart = Map<String, int>.from(widget.cart)
      ..removeWhere((key, value) => value <= 0);
    _loadSavedVouchers();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _voucherController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Map<String, Product> _productById() {
    return {
      for (final product in DBService.getAllProducts()) product.id: product,
    };
  }

  List<MapEntry<String, int>> _visibleEntries(Map<String, Product> products) {
    return _cart.entries
        .where((entry) => entry.value > 0 && products.containsKey(entry.key))
        .toList();
  }

  double _subtotal(Map<String, Product> products) {
    double total = 0;
    for (final entry in _visibleEntries(products)) {
      total += products[entry.key]!.price * entry.value;
    }
    return total;
  }

  int _itemsCount() => _cart.values.fold(0, (sum, quantity) => sum + quantity);

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  int? _currentUserId() {
    final raw = DBService.settings().get('current_user_id');
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _loadSavedVouchers() async {
    final userId = _currentUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _savedVouchers = [];
        _isLoadingSavedVouchers = false;
      });
      return;
    }

    final token = (DBService.settings().get('auth_token') ?? '').toString();
    final vouchers = await VoucherService.getUserVouchers(userId, token);
    if (!mounted) return;
    setState(() {
      _savedVouchers = vouchers;
      _isLoadingSavedVouchers = false;
    });
  }

  void _clearVoucher() {
    _voucherCode = null;
    _discountAmount = 0;
    _voucherMessage = null;
    _voucherController.clear();
  }

  Future<void> _persistCart() async {
    final email = DBService.currentUserEmail();
    if (email != null) {
      await DBService.saveCartForUser(email, _cart);
    }
  }

  Future<void> _increaseQty(Product product) async {
    final current = _cart[product.id] ?? 0;
    if (current >= product.stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} đã đạt giới hạn tồn kho')),
      );
      return;
    }
    setState(() {
      _cart[product.id] = current + 1;
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _decreaseQty(Product product) async {
    final current = _cart[product.id] ?? 0;
    setState(() {
      if (current <= 1) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = current - 1;
      }
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _removeItem(Product product) async {
    setState(() {
      _cart.remove(product.id);
      _clearVoucher();
    });
    await _persistCart();
  }

  Future<void> _applyVoucher(double subtotal) async {
    final code = _voucherController.text.trim().toUpperCase();
    final userId = _currentUserId();
    if (code.isEmpty || userId == null) {
      setState(() => _voucherMessage = 'Nhập mã ưu đãi hợp lệ');
      return;
    }

    setState(() {
      _isApplyingVoucher = true;
      _voucherMessage = null;
    });
    try {
      final voucher = await ApiService.validateVoucher(
        code: code,
        orderTotal: subtotal,
        userId: userId,
      );
      final discount =
          double.tryParse(voucher['discountAmount']?.toString() ?? '0') ?? 0;
      setState(() {
        _voucherCode = code;
        _discountAmount = discount;
        _voucherMessage = 'Đã áp dụng $code';
      });
    } catch (e) {
      setState(() {
        _voucherCode = null;
        _discountAmount = 0;
        _voucherMessage = e is ApiException ? e.message : e.toString();
      });
    } finally {
      if (mounted) setState(() => _isApplyingVoucher = false);
    }
  }

  Future<void> _checkout() async {
    if (_isCheckingOut) return;
    final userId = _currentUserId();
    final email = DBService.currentUserEmail();
    if (userId == null || email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy người dùng hiện tại')),
      );
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giỏ hàng đang trống')));
      return;
    }
    if (_deliveryMethod == 'delivery' &&
        _addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập địa chỉ giao hàng')),
      );
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đặt hàng?'),
        content: const Text('Kiểm tra lại thông tin trước khi tạo đơn hàng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đặt hàng'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() => _isCheckingOut = true);
    try {
      final order = await ApiService.checkoutOnlineOrder(
        userId: userId,
        deliveryMethod: _deliveryMethod,
        paymentMethod: _paymentMethod,
        shippingAddress: _deliveryMethod == 'delivery'
            ? _addressController.text.trim()
            : null,
        voucherCode: _voucherCode,
        note: _noteController.text,
      );
      await DBService.carts().put(email, <String, int>{});
      await DBService.orders().put(order.id, order);
      widget.onCheckoutComplete();
      DBService.syncProductsFromApi();

      if (!mounted) return;

      if (_paymentMethod == 'vnpay') {
        Navigator.of(context).pushReplacement(
          buildSlidePageRoute(
            VnpayPaymentScreen(
              orderId: int.parse(order.id),
              userId: userId,
              amount: order.totalAmount,
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đặt hàng thành công')));
      Navigator.of(
        context,
      ).pushReplacement(buildSlidePageRoute(const OrdersScreen()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _isCheckingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _productById();
    final entries = _visibleEntries(products);
    final subtotal = _subtotal(products);
    final finalTotal = subtotal - _discountAmount;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text('Giỏ hàng và thanh toán'),
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
      ),
      body: entries.isEmpty
          ? _emptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 820;
                final content = _checkoutContent(
                  products: products,
                  entries: entries,
                  subtotal: subtotal,
                  finalTotal: finalTotal,
                  wide: wide,
                );
                if (!wide) return content;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: content,
                  ),
                );
              },
            ),
      bottomNavigationBar: entries.isEmpty
          ? null
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 820) return const SizedBox.shrink();
                return _mobileSummary(subtotal, finalTotal);
              },
            ),
    );
  }

  Widget _checkoutContent({
    required Map<String, Product> products,
    required List<MapEntry<String, int>> entries,
    required double subtotal,
    required double finalTotal,
    required bool wide,
  }) {
    final list = ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, wide ? 24 : 150),
      children: [
        _heroHeader(),
        const SizedBox(height: 14),
        _progressSteps(),
        const SizedBox(height: 14),
        _sectionCard(
          title: 'Sản phẩm trong giỏ',
          subtitle: '${_itemsCount()} sản phẩm',
          icon: Icons.shopping_bag_outlined,
          child: Column(
            children: entries
                .map((entry) => _cartItem(products[entry.key]!, entry.value))
                .toList(),
          ),
        ),
        _sectionCard(
          title: 'Mã ưu đãi',
          subtitle: 'Nhập coupon để giảm tổng đơn',
          icon: Icons.local_offer_outlined,
          child: _voucherInput(subtotal),
        ),
        _sectionCard(
          title: 'Nhận hàng',
          subtitle: _deliveryMethod == 'delivery'
              ? 'Dự kiến giao trong 24-48h'
              : 'Sẵn sàng nhận tại quầy sau khi xác nhận',
          icon: Icons.local_shipping_outlined,
          child: _deliveryOptions(),
        ),
        _sectionCard(
          title: 'Thanh toán',
          subtitle: 'Chọn phương thức phù hợp',
          icon: Icons.payments_outlined,
          child: _paymentOptions(finalTotal),
        ),
        _sectionCard(
          title: 'Ghi chú',
          subtitle: 'Yêu cầu đóng gói hoặc liên hệ',
          icon: Icons.notes_outlined,
          child: TextField(
            controller: _noteController,
            decoration: InputDecoration(
              hintText: 'Ví dụ: Gọi trước khi giao, cần túi riêng...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            minLines: 2,
            maxLines: 3,
          ),
        ),
      ],
    );

    if (!wide) return list;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: list),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 24),
            child: _summaryPanel(subtotal, finalTotal, sticky: true),
          ),
        ),
      ],
    );
  }

  Widget _heroHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B7F4D), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(
            Icons.shopping_cart_checkout_rounded,
            color: Colors.white,
            size: 34,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoàn tất đơn hàng',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kiểm tra giỏ hàng, áp dụng ưu đãi và chọn cách nhận hàng.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressSteps() {
    const steps = [
      ('Giỏ hàng', Icons.shopping_bag_outlined),
      ('Nhận hàng', Icons.local_shipping_outlined),
      ('Thanh toán', Icons.verified_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  Icon(steps[i].$2, color: i == 0 ? _primary : _accent),
                  const SizedBox(height: 4),
                  Text(
                    steps[i].$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _cartItem(Product product, int quantity) {
    final lineTotal = product.price * quantity;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: ProductImageWidget(
              product: product,
              assetFallback: ProductAssetResolver.forProduct,
              height: 68,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatCurrency(product.price)} / ${product.unit}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _qtyButton(
                      icon: Icons.remove,
                      onPressed: () => _decreaseQty(product),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '$quantity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _qtyButton(
                      icon: Icons.add,
                      onPressed: () => _increaseQty(product),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _removeItem(product),
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.red.shade600,
                      tooltip: 'Xóa',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatCurrency(lineTotal),
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton({required IconData icon, required VoidCallback onPressed}) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton.filledTonal(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: _ink,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  String _voucherDiscountText(Voucher voucher) {
    if (voucher.discountType == 'percent') {
      final max = voucher.maxDiscount == null
          ? ''
          : ' tối đa ${_formatCurrency(voucher.maxDiscount!)}';
      return 'Giảm ${voucher.discountValue.toStringAsFixed(0)}%$max';
    }
    return 'Giảm ${_formatCurrency(voucher.discountValue)}';
  }

  Widget _savedVoucherList(double subtotal) {
    if (_isLoadingSavedVouchers) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_savedVouchers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Bạn chưa lưu voucher nào. Vào tab Ưu đãi để lấy mã.',
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Voucher đã lưu',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ..._savedVouchers.map(
          (voucher) => _savedVoucherTile(voucher, subtotal),
        ),
      ],
    );
  }

  Widget _savedVoucherTile(Voucher voucher, double subtotal) {
    final canUse = voucher.isValid(subtotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: canUse ? Colors.blue.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: canUse ? Colors.blue.shade100 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.local_offer_outlined,
            color: canUse ? _accent : Colors.black38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  voucher.code,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  voucher.minOrderAmount > subtotal
                      ? 'Cần đơn từ ${_formatCurrency(voucher.minOrderAmount)}'
                      : _voucherDiscountText(voucher),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: canUse
                ? () {
                    _voucherController.text = voucher.code;
                    _applyVoucher(subtotal);
                  }
                : null,
            child: const Text('Dùng'),
          ),
        ],
      ),
    );
  }

  Widget _voucherInput(double subtotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _voucherController,
                enabled: _voucherCode == null,
                decoration: InputDecoration(
                  hintText: 'Nhập mã voucher',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            if (_voucherCode == null)
              ElevatedButton(
                onPressed: _isApplyingVoucher
                    ? null
                    : () => _applyVoucher(subtotal),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isApplyingVoucher
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Áp dụng'),
              )
            else
              OutlinedButton(
                onPressed: () => setState(_clearVoucher),
                child: const Text('Bỏ'),
              ),
          ],
        ),
        if (_voucherMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _voucherMessage!,
            style: TextStyle(
              color: _voucherCode == null ? Colors.red : _primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        _savedVoucherList(subtotal),
      ],
    );
  }

  Widget _deliveryOptions() {
    return RadioGroup<String>(
      groupValue: _deliveryMethod,
      onChanged: (value) => setState(() => _deliveryMethod = value ?? 'pickup'),
      child: Column(
        children: [
          _optionTile(
            value: 'pickup',
            icon: Icons.storefront_outlined,
            title: 'Nhận tại cửa hàng',
            subtitle: 'Nhận đơn tại quầy sau khi nhân viên xác nhận.',
          ),
          const SizedBox(height: 10),
          _optionTile(
            value: 'delivery',
            icon: Icons.local_shipping_outlined,
            title: 'Giao tận nhà',
            subtitle: 'Dự kiến 24-48h, nhân viên sẽ liên hệ trước khi giao.',
          ),
          if (_deliveryMethod == 'delivery') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: 'Địa chỉ giao hàng',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ],
      ),
    );
  }

  Widget _paymentOptions(double amount) {
    return RadioGroup<String>(
      groupValue: _paymentMethod,
      onChanged: (value) => setState(() => _paymentMethod = value ?? 'cash'),
      child: Column(
        children: [
          _optionTile(
            value: 'cash',
            icon: Icons.payments_outlined,
            title: 'Tiền mặt',
            subtitle: 'Thanh toán khi nhận hàng hoặc tại quầy.',
          ),
          const SizedBox(height: 10),
          _optionTile(
            value: 'vnpay',
            icon: Icons.account_balance_outlined,
            title: 'Thanh toán online VNPay',
            subtitle: 'Mở cổng VNPay sandbox, xác nhận tự động qua IPN.',
          ),
          const SizedBox(height: 10),
          _optionTile(
            value: 'ewallet',
            icon: Icons.qr_code_2_outlined,
            title: 'QR mô phỏng (demo)',
            subtitle:
                'Chỉ dùng demo: đánh dấu đã thanh toán ngay, không qua cổng thật.',
          ),
          if (_paymentMethod == 'ewallet') _fakeQr(amount),
        ],
      ),
    );
  }

  Widget _optionTile({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = value == _deliveryMethod || value == _paymentMethod;
    return Container(
      decoration: BoxDecoration(
        color: selected ? _primary.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? _primary : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: RadioListTile<String>(
        value: value,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        secondary: Icon(icon, color: selected ? _primary : Colors.black54),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _summaryPanel(
    double subtotal,
    double finalTotal, {
    bool sticky = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tóm tắt đơn hàng',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _moneyRow('Tạm tính', subtotal),
          _moneyRow('Phí dịch vụ', 0),
          if (_discountAmount > 0) _moneyRow('Giảm giá', -_discountAmount),
          const Divider(height: 24),
          _moneyRow('Tổng thanh toán', finalTotal, isTotal: true),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: Colors.black54,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _deliveryMethod == 'delivery'
                      ? 'Dự kiến giao: 24-48h'
                      : 'Nhận tại cửa hàng sau khi xác nhận',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isCheckingOut ? null : _checkout,
              icon: _isCheckingOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.lock_outline),
              label: Text(_isCheckingOut ? 'Đang tạo đơn...' : 'Đặt hàng'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSummary(double subtotal, double finalTotal) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: _summaryPanel(subtotal, finalTotal),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: _card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: _primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTotal ? _ink : Colors.black54,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
                fontSize: isTotal ? 17 : 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                _formatCurrency(amount),
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isTotal ? _primary : _ink,
                  fontSize: isTotal ? 19 : 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fakeQr(double amount) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomPaint(painter: _FakeQrPainter()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'QR demo\nONLINE-${DateTime.now().millisecondsSinceEpoch}\n${_formatCurrency(amount)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 44,
                color: _primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Giỏ hàng đang trống',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thêm sản phẩm vào giỏ để bắt đầu thanh toán online.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Tiếp tục mua hàng'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeQrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black87;
    final cell = size.width / 9;
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 9; x++) {
        if ((x * 3 + y * 5 + x * y) % 4 == 0 ||
            (x < 3 && y < 3) ||
            (x > 5 && y < 3) ||
            (x < 3 && y > 5)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell * 0.82, cell * 0.82),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
