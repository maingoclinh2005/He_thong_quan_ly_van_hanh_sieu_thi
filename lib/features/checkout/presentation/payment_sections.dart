part of 'payment_screen.dart';

extension _PaymentSections on _PaymentScreenState {
  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_PaymentScreenState._primary, _PaymentScreenState._accent],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _PaymentScreenState._primary.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.point_of_sale, color: Colors.white, size: 34),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoàn tất thanh toán POS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kiểm tra hóa đơn, áp dụng voucher và chọn phương thức thanh toán.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _PaymentScreenState._primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _PaymentScreenState._primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _PaymentScreenState._ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.55),
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
    );
  }

  Widget _invoiceCard() {
    final productsById = {
      for (final product in DBService.products().values.cast<Product>())
        product.id: product,
    };
    final invoiceEntries = widget.originalCart.entries
        .where((entry) => productsById.containsKey(entry.key))
        .toList();

    return _sectionCard(
      title: 'Sản phẩm trong hóa đơn',
      subtitle: '${widget.cartForDisplay.length} dòng sản phẩm',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: invoiceEntries.map((entry) {
          final product = productsById[entry.key]!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _productImage(product),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _PaymentScreenState._surface,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'x${entry.value}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
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

  Widget _savedVoucherList() {
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
        ..._savedVouchers.map(_savedVoucherTile),
      ],
    );
  }

  Widget _savedVoucherTile(Voucher voucher) {
    final canUse = voucher.isValid(widget.totalAmount);
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
            color: canUse ? _PaymentScreenState._accent : Colors.black38,
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
                  voucher.minOrderAmount > widget.totalAmount
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
            onPressed: canUse ? () => _applyVoucher(voucher.code) : null,
            child: const Text('Dùng'),
          ),
        ],
      ),
    );
  }

  Widget _voucherCard() {
    return _sectionCard(
      title: 'Mã ưu đãi',
      subtitle: 'Áp dụng voucher riêng cho hóa đơn tại quầy',
      icon: Icons.local_offer_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _voucherController,
                  enabled: _appliedVoucherId == null && !_isApplyingVoucher,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Nhập mã voucher',
                    filled: true,
                    fillColor: _PaymentScreenState._surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _applyVoucher,
                ),
              ),
              const SizedBox(width: 8),
              if (_appliedVoucherId == null)
                ElevatedButton(
                  onPressed: _isApplyingVoucher
                      ? null
                      : () => _applyVoucher(_voucherController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _PaymentScreenState._primary,
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
                TextButton(onPressed: _removeVoucher, child: const Text('Bỏ')),
            ],
          ),
          if (_voucherMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _voucherMessage!,
              style: TextStyle(
                color: _appliedVoucherId != null
                    ? _PaymentScreenState._primary
                    : Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          _savedVoucherList(),
        ],
      ),
    );
  }

  Widget _loyaltyCard() {
    return _sectionCard(
      title: 'Tích điểm khách hàng',
      subtitle: 'Dành cho khách mua tại quầy muốn lưu điểm bằng số điện thoại',
      icon: Icons.stars_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _wantsLoyaltyPoints,
            activeThumbColor: _PaymentScreenState._primary,
            title: const Text(
              'Khách muốn tích điểm?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text(
              'Tra điểm bằng SĐT, có thể dùng điểm để giảm tiền và vẫn tích điểm sau đơn.',
            ),
            onChanged: (value) {
              _redraw(() {
                _wantsLoyaltyPoints = value;
                if (!value) {
                  _loyaltyCustomer = null;
                  _usePoints = false;
                  _pointsToUseController.clear();
                }
              });
            },
          ),
          if (_wantsLoyaltyPoints) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _loyaltyNameController,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _redraw(() {}),
              decoration: InputDecoration(
                labelText: 'Tên khách',
                prefixIcon: const Icon(Icons.person_outline),
                filled: true,
                fillColor: _PaymentScreenState._surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _loyaltyPhoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _redraw(() {
                  _loyaltyCustomer = null;
                  _usePoints = false;
                  _pointsToUseController.clear();
                });
              },
              decoration: InputDecoration(
                labelText: 'Số điện thoại',
                prefixIcon: const Icon(Icons.phone_outlined),
                suffixIcon: _isCheckingPoints
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _checkCustomerPoints,
                        icon: const Icon(Icons.search),
                        tooltip: 'Kiểm tra điểm',
                      ),
                filled: true,
                fillColor: _PaymentScreenState._surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _checkCustomerPoints(),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCheckingPoints ? null : _checkCustomerPoints,
                icon: const Icon(Icons.manage_search),
                label: const Text('Kiểm tra điểm'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _PaymentScreenState._primary,
                  side: BorderSide(
                    color: _PaymentScreenState._primary.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_loyaltyCustomer != null) ...[
              const SizedBox(height: 12),
              _loyaltyLookupResult(),
            ],
          ],
          if (_isCheckingPoints) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }

  Widget _loyaltyLookupResult() {
    final exists = _loyaltyCustomer?['exists'] == true;
    final points = NumberParser.toInt(_loyaltyCustomer?['points']) ?? 0;
    final maxPoints =
        NumberParser.toInt(_loyaltyCustomer?['max_redeem_points']) ?? 0;
    final maxDiscount = NumberParser.toDouble(
      _loyaltyCustomer?['max_discount'],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: exists
            ? _PaymentScreenState._primary.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exists
                ? '${_loyaltyCustomer?['name'] ?? 'Khách hàng'} • $points điểm'
                : (_loyaltyCustomer?['message']?.toString() ??
                      'Khách hàng chưa có điểm'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          if (exists) ...[
            const SizedBox(height: 6),
            Text(
              maxPoints >= 100
                  ? 'Có thể dùng tối đa $maxPoints điểm (${_formatCurrency(maxDiscount)})'
                  : 'Chưa đủ 100 điểm để sử dụng giảm giá',
            ),
            if (maxPoints >= 100) ...[
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _usePoints,
                title: const Text(
                  'Sử dụng điểm',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onChanged: (value) {
                  _redraw(() {
                    _usePoints = value == true;
                    if (_usePoints && _pointsToUseController.text.isEmpty) {
                      _pointsToUseController.text = maxPoints.toString();
                    }
                    if (!_usePoints) _pointsToUseController.clear();
                  });
                },
              ),
              if (_usePoints) ...[
                TextField(
                  controller: _pointsToUseController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số điểm sử dụng (bội số 100)',
                    helperText: 'Tối đa $maxPoints điểm',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => _redraw(() {}),
                ),
                const SizedBox(height: 10),
                _moneyRow('Sau voucher', _finalTotal),
                _moneyRow('Giảm bằng điểm', -_pointsDiscount),
                _moneyRow('Còn phải trả', _payableTotal, isTotal: true),
              ],
            ],
          ],
        ],
      ),
    );
  }

  Widget _paymentMethodCard() {
    return _sectionCard(
      title: 'Phương thức thanh toán',
      subtitle: 'Chọn cách khách thanh toán tại quầy',
      icon: Icons.payments_outlined,
      child: Column(
        children: [
          _paymentOption(
            icon: Icons.money,
            title: 'Tiền mặt',
            subtitle: 'Thu tiền trực tiếp tại quầy.',
            value: 'cash',
          ),
          const SizedBox(height: 10),
          _paymentOption(
            icon: Icons.account_balance,
            title: 'Chuyển khoản QR',
            subtitle:
                'Hiển thị QR đúng tổng tiền, xác nhận sau khi khách chuyển.',
            value: 'bank_transfer',
          ),
        ],
      ),
    );
  }

  Widget _paymentOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final selected = _selectedPaymentMethod == value;
    return InkWell(
      onTap: () => _redraw(() => _selectedPaymentMethod = value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _PaymentScreenState._primary.withValues(alpha: 0.08)
              : _PaymentScreenState._surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _PaymentScreenState._primary
                : Colors.black.withValues(alpha: 0.06),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? _PaymentScreenState._primary : Colors.black54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? _PaymentScreenState._primary
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? _PaymentScreenState._primary
                      : Colors.black26,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tóm tắt hóa đơn',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _moneyRow('Tạm tính', widget.totalAmount),
          if (_discountAmount > 0) _moneyRow('Giảm giá', -_discountAmount),
          if (_pointsDiscount > 0)
            _moneyRow('Giảm bằng điểm', -_pointsDiscount),
          const Divider(height: 24),
          _moneyRow('Tổng thanh toán', _payableTotal, isTotal: true),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _PaymentScreenState._accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  color: _PaymentScreenState._accent,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hóa đơn POS hoàn thành ngay sau khi xác nhận thanh toán.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isProcessing || _selectedPaymentMethod == null
                  ? null
                  : _placeOrder,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _isProcessing
                    ? 'Đang thanh toán...'
                    : _wantsLoyaltyPoints
                    ? 'Tích điểm & Thanh toán'
                    : 'Xác nhận thanh toán',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _PaymentScreenState._primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isTotal
                    ? _PaymentScreenState._ink
                    : Colors.black.withValues(alpha: 0.62),
                fontSize: isTotal ? 17 : 15,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
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
                  color: isTotal
                      ? _PaymentScreenState._primary
                      : _PaymentScreenState._ink,
                  fontSize: isTotal ? 20 : 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NumberParser {
  static int? toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
