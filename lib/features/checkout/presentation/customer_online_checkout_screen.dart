import 'package:sieuthimini/features/checkout/application/checkout_controller.dart';
import 'package:sieuthimini/features/checkout/data/checkout_repository.dart';
import 'package:sieuthimini/features/cart/application/cart_controller.dart';
import 'package:sieuthimini/features/catalog/presentation/cache_sync_banner.dart';
import 'package:sieuthimini/services/token_store.dart';
import 'package:flutter/material.dart';

import 'package:sieuthimini/models/product.dart';
import 'package:sieuthimini/models/voucher.dart';
import 'package:sieuthimini/services/api_service.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:sieuthimini/services/voucher_service.dart';
import 'package:sieuthimini/utils/product_asset_resolver.dart';
import 'package:sieuthimini/widgets/product_image_widget.dart';
import 'package:sieuthimini/widgets/slide_page_route.dart';
import 'package:sieuthimini/screens/orders_screen.dart';
import 'package:sieuthimini/screens/vnpay_payment_screen.dart';

part 'online_checkout_sections.dart';

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
  void _redraw(VoidCallback update) {
    if (mounted) setState(update);
  }

  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF111827);

  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late final CartController _cartState;
  Map<String, int> get _cart => _cartState.items;
  final _checkoutState = CheckoutController();
  void _controllerChanged() {
    if (mounted) setState(() {});
  }

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
    _cartState = CartController(
      initial: widget.cart,
      loadCart: () async => widget.cart,
      saveCart: (cart) async {
        final email = DBService.currentUserEmail();
        if (email != null) await DBService.saveCartForUser(email, cart);
      },
    )..addListener(_controllerChanged);
    _cart.removeWhere((_, qty) => qty <= 0);
    _checkoutState.addListener(_controllerChanged);
    _loadSavedVouchers();
  }

  @override
  void dispose() {
    _checkoutState.dispose();
    _cartState.dispose();
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

    final token = (TokenStore.instance.accessToken ?? '').toString();
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

  Future<void> _persistCart() => _cartState.persist();

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
    if (_isCheckingOut || _checkoutState.busy) return;
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
      final order = await _checkoutState.submit(
        () => CheckoutRepository.online(
          email: email,
          cart: Map.of(_cart),
          userId: userId,
          deliveryMethod: _deliveryMethod,
          paymentMethod: _paymentMethod,
          shippingAddress: _deliveryMethod == 'delivery'
              ? _addressController.text.trim()
              : null,
          voucherCode: _voucherCode,
          note: _noteController.text,
        ),
      );
      widget.onCheckoutComplete();

      if (!mounted) return;

      if (order.paymentMethod == 'vnpay') {
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
}
