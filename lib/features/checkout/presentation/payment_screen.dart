import 'package:sieuthimini/features/checkout/application/checkout_controller.dart';
import 'package:sieuthimini/features/checkout/data/checkout_repository.dart';
import 'package:sieuthimini/features/catalog/presentation/cache_sync_banner.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sieuthimini/models/order.dart';
import 'package:sieuthimini/models/order_line.dart';
import 'package:sieuthimini/models/product.dart';
import 'package:sieuthimini/models/voucher.dart';
import 'package:sieuthimini/services/api_service.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:sieuthimini/services/voucher_service.dart';
import 'package:sieuthimini/utils/payment_config.dart';
import 'package:sieuthimini/utils/product_asset_resolver.dart';
import 'package:sieuthimini/widgets/product_image_widget.dart';
import 'package:sieuthimini/widgets/role_bottom_navigation_bar.dart';
import 'package:sieuthimini/widgets/slide_page_route.dart';
import 'package:sieuthimini/screens/bank_transfer_qr_screen.dart';
import 'package:sieuthimini/screens/checkout_screen.dart';
import 'package:sieuthimini/screens/employee.dart';
import 'package:sieuthimini/screens/employee_confirm_orders_screen.dart';
import 'package:sieuthimini/screens/customer_vouchers_screen.dart';
import 'package:sieuthimini/screens/order_management_screen.dart';
import 'package:sieuthimini/screens/order_success_screen.dart';
import 'package:sieuthimini/screens/profile_route.dart';
import 'package:sieuthimini/screens/scan_product_screen.dart';

part 'payment_sections.dart';

class PaymentScreen extends StatefulWidget {
  final String role;
  final Map<String, int> cartForDisplay;
  final Map<String, int> originalCart;
  final double totalAmount;
  final VoidCallback onCheckoutComplete;

  const PaymentScreen({
    super.key,
    required this.role,
    required this.cartForDisplay,
    required this.originalCart,
    required this.totalAmount,
    required this.onCheckoutComplete,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  void _redraw(VoidCallback update) {
    if (mounted) setState(update);
  }

  static const Color _primary = Color(0xFF1B7F4D);
  static const Color _accent = Color(0xFF2563EB);
  static const Color _surface = Color(0xFFF6F7F9);
  static const Color _ink = Color(0xFF111827);
  static const Duration _checkoutTimeout = Duration(seconds: 12);

  final TextEditingController _voucherController = TextEditingController();
  final TextEditingController _loyaltyNameController = TextEditingController();
  final TextEditingController _loyaltyPhoneController = TextEditingController();
  final TextEditingController _pointsToUseController = TextEditingController();
  String? _selectedPaymentMethod;
  String? _voucherMessage;
  int? _appliedVoucherId;
  double _discountAmount = 0;
  bool _isLoadingSavedVouchers = true;
  List<Voucher> _savedVouchers = [];
  final _checkout = CheckoutController();
  bool _uiBusy = false;
  bool get _isProcessing => _uiBusy || _checkout.busy;
  set _isProcessing(bool value) => _uiBusy = value;
  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  bool _isApplyingVoucher = false;
  bool _wantsLoyaltyPoints = false;
  bool _isCheckingPoints = false;
  bool _usePoints = false;
  Map<String, dynamic>? _loyaltyCustomer;

  String _imageFor(Product product) {
    return ProductAssetResolver.forProduct(product);
  }

  Widget _productImage(Product product) {
    return SizedBox(
      width: 46,
      height: 46,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ProductImageWidget(
          product: product,
          assetFallback: _imageFor,
          height: 46,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkout.addListener(_controllerChanged);
    _loadSavedVouchers();
  }

  @override
  void dispose() {
    _checkout.dispose();
    _voucherController.dispose();
    _loyaltyNameController.dispose();
    _loyaltyPhoneController.dispose();
    _pointsToUseController.dispose();
    super.dispose();
  }

  double get _finalTotal => widget.totalAmount - _discountAmount;
  int get _pointsToUse => int.tryParse(_pointsToUseController.text.trim()) ?? 0;
  double get _pointsDiscount => _usePoints ? (_pointsToUse ~/ 100) * 10000 : 0;
  double get _payableTotal =>
      (_finalTotal - _pointsDiscount).clamp(0, double.infinity).toDouble();

  String _formatCurrency(double amount) {
    return '${amount.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} VND';
  }

  Future<void> _loadSavedVouchers() async {
    final userId = DBService.currentUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _savedVouchers = [];
        _isLoadingSavedVouchers = false;
      });
      return;
    }

    // The shared HTTP client supplies the current secure token, including after refresh.
    const token = '';
    final vouchers = await VoucherService.getUserVouchers(userId, token);
    if (!mounted) return;
    setState(() {
      _savedVouchers = vouchers;
      _isLoadingSavedVouchers = false;
    });
  }

  Future<void> _applyVoucher(String voucherCode) async {
    final code = voucherCode.trim();
    if (code.isEmpty || _isApplyingVoucher) return;

    setState(() => _isApplyingVoucher = true);
    try {
      final rawUserId = DBService.settings().get('current_user_id');
      final userId = rawUserId is int
          ? rawUserId
          : int.tryParse(rawUserId?.toString() ?? '') ?? 0;
      final result = await VoucherService.validateVoucher(
        code: code,
        orderTotal: widget.totalAmount,
        userId: userId,
      );

      if (!mounted) return;
      if (result['success'] == true) {
        final data = Map<String, dynamic>.from(result['data'] as Map);
        setState(() {
          _appliedVoucherId = NumberParser.toInt(data['id']);
          _discountAmount = NumberParser.toDouble(data['discountAmount']);
          _voucherMessage = 'Đã áp dụng mã ${data['code']}';
          _voucherController.text = data['code'].toString();
          _usePoints = false;
          _pointsToUseController.clear();
        });
        _showSnack(_voucherMessage!, success: true);
      } else {
        setState(() {
          _appliedVoucherId = null;
          _discountAmount = 0;
          _voucherMessage =
              result['message']?.toString() ?? 'Mã voucher không hợp lệ';
        });
        _showSnack(_voucherMessage!, success: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _appliedVoucherId = null;
        _discountAmount = 0;
        _voucherMessage = 'Lỗi kiểm tra voucher';
      });
      _showSnack('Lỗi kiểm tra voucher: $e', success: false);
    } finally {
      if (mounted) setState(() => _isApplyingVoucher = false);
    }
  }

  void _removeVoucher() {
    setState(() {
      _appliedVoucherId = null;
      _discountAmount = 0;
      _voucherMessage = null;
      _voucherController.clear();
      _usePoints = false;
      _pointsToUseController.clear();
    });
  }

  void _showSnack(String message, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? _primary : Colors.red.shade700,
      ),
    );
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'cash':
        return 'Tiền mặt';
      case 'bank_transfer':
        return 'Chuyển khoản QR';
      default:
        return value;
    }
  }

  String _generateOrderCode() {
    return 'POS${DateTime.now().millisecondsSinceEpoch}';
  }

  List<OrderLine> _buildOrderLines() {
    final allProducts = DBService.getAllProducts();
    final orderLines = <OrderLine>[];
    for (final entry in widget.originalCart.entries) {
      final product = allProducts.firstWhere((p) => p.id == entry.key);
      if (entry.value > product.stockQuantity) {
        throw Exception('${product.name} không đủ tồn kho');
      }
      orderLines.add(
        OrderLine(
          productId: product.id,
          productName: product.name,
          quantity: entry.value,
          pricePerUnit: product.price,
        ),
      );
    }
    if (orderLines.isEmpty) {
      throw Exception('Giỏ hàng đang trống, không thể thanh toán.');
    }
    return orderLines;
  }

  Order _buildPaidOrder({
    required String paymentMethod,
    required String transactionId,
    required String? qrContent,
    required String? note,
  }) {
    final rawUserId = DBService.settings().get('current_user_id');
    final currentUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    return Order(
      id: transactionId,
      orderDate: DateTime.now(),
      totalAmount: _payableTotal,
      customerName: _wantsLoyaltyPoints
          ? _loyaltyNameController.text.trim()
          : 'Khách lẻ',
      customerId: _wantsLoyaltyPoints ? null : currentUserId,
      status: 'completed',
      paymentMethod: paymentMethod,
      paymentStatus: 'paid',
      paidAt: DateTime.now(),
      transactionId: transactionId,
      qrContent: qrContent,
      transferContent: note?.replaceFirst('Nội dung chuyển khoản: ', ''),
      note: note,
      items: _buildOrderLines(),
      voucherId: _appliedVoucherId,
      discountAmount: _discountAmount,
      pointsUsed: _usePoints ? _pointsToUse : 0,
      pointsDiscount: _pointsDiscount,
      customerPhone: _wantsLoyaltyPoints
          ? _loyaltyPhoneController.text.trim()
          : null,
    );
  }

  Order _buildPendingBankOrder() {
    final rawUserId = DBService.settings().get('current_user_id');
    final currentUserId = rawUserId is int
        ? rawUserId
        : int.tryParse(rawUserId?.toString() ?? '');
    return Order(
      id: 'PENDING-${DateTime.now().millisecondsSinceEpoch}',
      orderDate: DateTime.now(),
      totalAmount: _payableTotal,
      customerName: _wantsLoyaltyPoints
          ? _loyaltyNameController.text.trim()
          : 'Khách lẻ',
      customerId: _wantsLoyaltyPoints ? null : currentUserId,
      status: 'pending',
      paymentMethod: 'bank_transfer',
      paymentStatus: 'pending',
      items: _buildOrderLines(),
      voucherId: _appliedVoucherId,
      discountAmount: _discountAmount,
      pointsUsed: _usePoints ? _pointsToUse : 0,
      pointsDiscount: _pointsDiscount,
      customerPhone: _wantsLoyaltyPoints
          ? _loyaltyPhoneController.text.trim()
          : null,
    );
  }

  Future<Order> _savePaidOrder(Order order) => _checkout.submit(
    () => CheckoutRepository.create(
      order,
      voucherId: _appliedVoucherId,
      discountAmount: _discountAmount,
      userId: order.customerId,
    ),
  );
  Future<Order> _createPendingBankOrder() =>
      _savePaidOrder(_buildPendingBankOrder());

  void _openSuccess(Order order) {
    final startingPoints = NumberParser.toInt(_loyaltyCustomer?['points']) ?? 0;
    final totalPoints = _wantsLoyaltyPoints
        ? startingPoints - order.pointsUsed + order.pointsEarned
        : null;
    widget.onCheckoutComplete();
    Navigator.pushReplacement(
      context,
      buildSlidePageRoute(
        OrderSuccessScreen(
          totalAmount: _formatCurrency(order.totalAmount),
          paymentMethod: _paymentMethodLabel(_selectedPaymentMethod!),
          orderId: order.id,
          paidAt: order.paidAt ?? DateTime.now(),
          pointsAdded: order.pointsEarned,
          totalPoints: totalPoints,
          loyaltyCustomerName: _wantsLoyaltyPoints
              ? _loyaltyNameController.text.trim()
              : null,
          pointsUsed: order.pointsUsed,
          pointsDiscount: order.pointsDiscount,
        ),
      ),
    );
  }

  bool _validateLoyaltyFields() {
    if (!_wantsLoyaltyPoints) return true;
    final name = _loyaltyNameController.text.trim();
    final phone = _loyaltyPhoneController.text.trim();
    if (name.isEmpty) {
      _showSnack('Vui lòng nhập tên khách để tích điểm', success: false);
      return false;
    }
    if (!RegExp(r'^[0-9+\-\s]{8,15}$').hasMatch(phone)) {
      _showSnack('Số điện thoại tích điểm không hợp lệ', success: false);
      return false;
    }
    if (_usePoints) {
      if (_loyaltyCustomer?['exists'] != true) {
        _showSnack('Vui lòng kiểm tra điểm khách hàng trước', success: false);
        return false;
      }
      final points = _pointsToUse;
      final maxPoints =
          NumberParser.toInt(_loyaltyCustomer?['max_redeem_points']) ?? 0;
      if (points <= 0 || points % 100 != 0) {
        _showSnack('Số điểm sử dụng phải là bội số của 100', success: false);
        return false;
      }
      if (points > maxPoints) {
        _showSnack('Số điểm dùng vượt mức cho phép', success: false);
        return false;
      }
    }
    return true;
  }

  Future<void> _checkCustomerPoints() async {
    final phone = _loyaltyPhoneController.text.trim();
    if (!RegExp(r'^[0-9+\-\s]{8,15}$').hasMatch(phone)) {
      _showSnack('Số điện thoại tích điểm không hợp lệ', success: false);
      return;
    }
    setState(() => _isCheckingPoints = true);
    try {
      final result = await ApiService.fetchCustomerPoints(
        phone: phone,
        amountAfterVoucher: _finalTotal,
      ).timeout(_checkoutTimeout);
      if (mounted) {
        setState(() {
          _loyaltyCustomer = result;
          if (result['exists'] == true) {
            _loyaltyNameController.text =
                result['name']?.toString() ?? _loyaltyNameController.text;
          }
          _usePoints = false;
          _pointsToUseController.clear();
        });
        _showSnack(
          result['exists'] == true
              ? 'Khách có ${result['points']} điểm'
              : (result['message']?.toString() ?? 'Khách hàng chưa có điểm'),
          success: result['exists'] == true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), success: false);
    } finally {
      if (mounted) setState(() => _isCheckingPoints = false);
    }
  }

  Future<Order> _markPendingBankOrderPaid(
    Order order,
    Map<String, dynamic> data,
  ) async {
    final paymentStatus =
        (data['paymentStatus'] ?? data['payment_status'] ?? '')
            .toString()
            .toLowerCase();
    if (!['paid', 'completed', 'success'].contains(paymentStatus)) {
      throw ApiException('Hệ thống chưa xác nhận thanh toán', statusCode: 409);
    }
    final paidAtValue = data['paidAt'] ?? data['paid_at'];
    order.paymentStatus = 'paid';
    order.status = (data['orderStatus'] ?? data['status'] ?? 'completed')
        .toString();
    order.transactionId = (data['transactionId'] ?? data['transaction_id'])
        ?.toString();
    order.transferContent =
        (data['transferContent'] ?? data['transfer_content'])?.toString() ??
        order.transferContent;
    order.pointsUsed =
        NumberParser.toInt(data['pointsUsed'] ?? data['points_used']) ??
        order.pointsUsed;
    order.pointsEarned =
        NumberParser.toInt(data['pointsEarned'] ?? data['points_earned']) ??
        order.pointsEarned;
    order.pointsDiscount = NumberParser.toDouble(
      data['pointsDiscount'] ?? data['points_discount'] ?? order.pointsDiscount,
    );
    order.paidAt =
        DateTime.tryParse((paidAtValue ?? '').toString()) ?? DateTime.now();
    await CheckoutRepository.cacheConfirmed(order);
    return order;
  }

  Future<void> _placeOrder() async {
    if (_isProcessing) return;
    if (_checkout.confirmed != null) {
      _selectedPaymentMethod = _checkout.confirmed!.paymentMethod;
    }

    if (_selectedPaymentMethod == null) {
      _showSnack('Vui lòng chọn phương thức thanh toán', success: false);
      return;
    }
    if (!_validateLoyaltyFields()) return;

    if (_selectedPaymentMethod == 'bank_transfer') {
      await _handleBankTransferPayment();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận thu tiền mặt?'),
        content: Text(
          'Tạo hóa đơn đã thanh toán tiền mặt với tổng ${_formatCurrency(_finalTotal)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final transactionId = _generateOrderCode();
      final newOrder = _buildPaidOrder(
        paymentMethod: 'cash',
        transactionId: transactionId,
        qrContent: null,
        note: null,
      );
      final savedOrder = await _savePaidOrder(newOrder);

      if (!mounted) return;
      _openSuccess(savedOrder);
    } on TimeoutException {
      if (!mounted) return;
      _showSnack(
        'Thanh toán quá thời gian chờ. Kiểm tra lịch sử đơn trước khi tạo lại.',
        success: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), success: false);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleBankTransferPayment() async {
    setState(() => _isProcessing = true);
    late final Order pendingOrder;
    try {
      pendingOrder = await _createPendingBankOrder();
    } on TimeoutException {
      if (!mounted) return;
      _showSnack(
        'Tạo đơn chuyển khoản quá thời gian chờ. Kiểm tra lịch sử đơn trước khi tạo lại.',
        success: false,
      );
      setState(() => _isProcessing = false);
      return;
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), success: false);
      setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final orderCode = pendingOrder.id;
    final transferContent =
        pendingOrder.transferContent ??
        PaymentConfig.transferContent(orderCode);
    final qrContent = PaymentConfig.qrContent(
      orderCode: orderCode,
      amount: pendingOrder.totalAmount,
    );
    debugPrint('VietQR URL: $qrContent');

    final result = await Navigator.of(context).push<BankTransferQrResult>(
      buildSlidePageRoute(
        BankTransferQrScreen(
          orderCode: orderCode,
          amount: pendingOrder.totalAmount,
          qrContent: qrContent,
          transferContent: transferContent,
          userId: pendingOrder.customerId ?? DBService.currentUserId() ?? 0,
        ),
      ),
    );
    if (result == null || !result.confirmed || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final userId = pendingOrder.customerId ?? DBService.currentUserId() ?? 0;
      final orderId = int.tryParse(pendingOrder.id) ?? 0;
      if (!result.paidAutomatically) {
        if (!mounted) return;
        _showSnack(
          'Đã ghi nhận giao dịch. Đơn hàng sẽ được cập nhật sau khi hệ thống hoặc quản trị viên xác nhận.',
          success: true,
        );
        widget.onCheckoutComplete();
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      final data = await ApiService.fetchOrderPaymentStatus(
        userId: userId,
        orderId: orderId,
      ).timeout(_checkoutTimeout);
      final savedOrder = await _markPendingBankOrderPaid(pendingOrder, data);
      if (!mounted) return;
      _openSuccess(savedOrder);
    } on TimeoutException {
      if (!mounted) return;
      _showSnack(
        'Lưu đơn chuyển khoản quá thời gian chờ. Kiểm tra lịch sử đơn trước khi tạo lại.',
        success: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), success: false);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleBottomTab(RoleBottomTab tab) async {
    switch (tab) {
      case RoleBottomTab.home:
        Navigator.of(context).popUntil((route) => route.isFirst);
        break;
      case RoleBottomTab.cart:
        Navigator.of(context).pop();
        break;
      case RoleBottomTab.scan:
        final product = await Navigator.of(
          context,
        ).push<Product?>(buildSlidePageRoute(const ScanProductScreen()));
        if (product == null || !mounted) return;
        try {
          final updatedCart = await DBService.addProductToCurrentCart(product);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            buildSlidePageRoute(
              CheckoutScreen(
                cart: updatedCart,
                role: widget.role,
                onCheckoutComplete: widget.onCheckoutComplete,
              ),
            ),
          );
        } catch (e) {
          if (!mounted) return;
          _showSnack(
            e.toString().replaceFirst('Exception: ', ''),
            success: false,
          );
        }
        break;
      case RoleBottomTab.invoices:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(OrderManagementScreen(role: widget.role)));
        break;
      case RoleBottomTab.confirmOrders:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const EmployeeConfirmOrdersScreen()));
        break;
      case RoleBottomTab.account:
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(buildProfileScreenForRole(widget.role)));
        break;
      case RoleBottomTab.employees:
        Navigator.of(context).push(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;
      case RoleBottomTab.offers:
        await Navigator.of(
          context,
        ).push(buildSlidePageRoute(const CustomerVouchersScreen()));
        if (!mounted) return;
        setState(() => _isLoadingSavedVouchers = true);
        await _loadSavedVouchers();
        break;
      case RoleBottomTab.orders:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: const Text(
          'Thanh toán tại quầy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _surface,
        foregroundColor: _ink,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final left = Column(
            children: [
              const CacheSyncBanner(),
              _header(),
              const SizedBox(height: 14),
              _invoiceCard(),
              const SizedBox(height: 14),
              _voucherCard(),
              const SizedBox(height: 14),
              _loyaltyCard(),
              const SizedBox(height: 14),
              _paymentMethodCard(),
            ],
          );
          final summary = _summaryCard();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: left),
                          const SizedBox(width: 16),
                          Expanded(flex: 4, child: summary),
                        ],
                      )
                    : Column(
                        children: [left, const SizedBox(height: 14), summary],
                      ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: RoleBottomTab.cart,
        onTabSelected: _handleBottomTab,
      ),
    );
  }
}
