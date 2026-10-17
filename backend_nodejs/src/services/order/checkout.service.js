const { ApplicationError } = require("../../errors/application-error");
const { currentUserId, calculateVoucherDiscount } = require("./order-policy");

function createOrderCheckoutService(repository, read) {
  async function applyVoucher(tx, userId, total, id, code) {
    if (!id && !code) return { voucher: null, discountAmount: 0 };
    const voucher = await tx.lockVoucher({ id, code, activeOnly: true });
    // Preserve legacy failures; changing checkout rules is a separate change.
    if (!voucher) throw new Error("Mã voucher không tồn tại");
    if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date())
      throw new Error("Voucher đã hết hạn");
    if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit)
      throw new Error("Voucher đã hết lượt dùng");
    if (total < Number(voucher.min_order_amount || 0))
      throw new Error(
        `Đơn hàng phải tối thiểu ${Number(voucher.min_order_amount).toLocaleString("vi-VN")} VND`,
      );
    const discountAmount = calculateVoucherDiscount(voucher, total);
    await tx.consumeVoucher(voucher.voucher_id, userId);
    return { voucher, discountAmount };
  }
  return {
    async checkout({ input, actor }) {
      const customerId = currentUserId(actor);
      const deliveryMethod = String(
        input.delivery_method || input.deliveryMethod || "pickup",
      ).trim();
      const paymentMethod = String(
        input.payment_method || input.paymentMethod || "cash",
      ).trim();
      const shippingAddress = String(
        input.shipping_address || input.shippingAddress || "",
      ).trim();
      const note = input.note ? String(input.note).trim() : null;
      const voucherId = Number(input.voucher_id || input.voucherId) || null;
      const voucherCode =
        input.voucher_code || input.voucherCode
          ? String(input.voucher_code || input.voucherCode)
              .trim()
              .toUpperCase()
          : null;
      if (!customerId)
        throw new ApplicationError("unauthorized", "Vui lòng đăng nhập");
      if (!["pickup", "delivery"].includes(deliveryMethod))
        throw new ApplicationError(
          "invalid",
          "Hình thức nhận hàng không hợp lệ",
        );
      if (deliveryMethod === "delivery" && !shippingAddress)
        throw new ApplicationError(
          "invalid",
          "Vui lòng nhập địa chỉ giao hàng",
        );
      if (!["cash", "ewallet", "vnpay"].includes(paymentMethod))
        throw new ApplicationError(
          "invalid",
          "Phương thức thanh toán không hợp lệ",
        );
      const result = await repository.transaction(async (tx) => {
        const cart = await tx.lockCart(customerId);
        if (!cart) throw new ApplicationError("invalid", "Giỏ hàng đang trống");
        const cartItems = await tx.lockCartItems(cart.cart_id);
        if (!cartItems.length)
          throw new ApplicationError("invalid", "Giỏ hàng đang trống");
        let total = 0;
        const items = [];
        for (const item of cartItems) {
          const quantity = Number(item.quantity);
          if (quantity <= 0) continue;
          if (Number(item.stock) < quantity)
            throw new Error(`Không đủ tồn kho cho ${item.product_name}`);
          const price = Number(item.price),
            subtotal = price * quantity;
          total += subtotal;
          items.push({
            productId: Number(item.product_id),
            quantity,
            price,
            subtotal,
          });
        }
        if (!items.length)
          throw new ApplicationError("invalid", "Giỏ hàng đang trống");
        const { voucher, discountAmount } = await applyVoucher(
          tx,
          customerId,
          total,
          voucherId,
          voucherCode,
        );
        const finalAmount = total - discountAmount;
        const paymentStatus = paymentMethod === "ewallet" ? "paid" : "pending";
        const orderId = await tx.insertOrder({
          customer_id: customerId,
          employee_id: null,
          shift_id: null,
          voucher_id: voucher?.voucher_id || null,
          order_type:
            deliveryMethod === "delivery" ? "delivery" : "store_pickup",
          delivery_method: deliveryMethod,
          total_amount: total,
          discount_amount: discountAmount,
          final_amount: finalAmount,
          payment_method: paymentMethod,
          status: "pending",
          payment_status: paymentStatus,
          shipping_address:
            deliveryMethod === "delivery" ? shippingAddress : null,
          note,
        });
        await tx.insertItemsAndReduceStock(orderId, items, Number(actor.user_id || actor.id));
        const fakeQrContent =
          paymentMethod === "ewallet"
            ? `FAKE_QR_ORDER_${orderId}_${Math.round(finalAmount)}`
            : null;
        await tx.insertPayment({
          order_id: orderId,
          method: paymentMethod,
          amount: finalAmount,
          status: paymentStatus,
          qr_content: fakeQrContent,
          paid_at: paymentStatus === "paid" ? new Date() : null,
        });
        await tx.clearCart(cart.cart_id);
        return {
          orderId,
          voucherCode: voucher?.code || null,
          discountAmount,
          finalAmount,
          fakeQrContent,
        };
      });
      const { orderId, ...checkoutData } = result;
      return {
        success: true,
        message: "Đã tạo đơn hàng online",
        data: {
          ...(await read.detail(orderId)),
          deliveryMethod,
          ...checkoutData,
          requiresVnpayPayment: paymentMethod === "vnpay",
        },
      };
    },
  };
}

module.exports = { createOrderCheckoutService };
