const { ApplicationError } = require("../../errors/application-error");
const { currentUserId, normalizeOrderStatus } = require("./order-policy");

function createOrderCreateService(repository, read, loyalty) {
  return {
    async create({ input, actor }) {
      const {
        customer_id,
        order_type = "offline",
        status,
        order_status,
        payment_status,
        shipping_address,
        note,
        payment_method = "cash",
        items,
        voucher_id,
        discount_amount = 0,
        user_id,
        transaction_id,
        transfer_content,
        qr_content,
        paid_at,
        customer_phone,
        customer_name,
        use_points = false,
        points_to_use = 0,
      } = input;
      if (!Array.isArray(items) || !items.length)
        throw new ApplicationError("invalid", "Đơn hàng cần có items");
      const orderId = await repository.transaction(async (tx, connection) => {
        const discountAmount = Number(discount_amount) || 0;
        if (voucher_id) {
          const voucher = await tx.lockVoucher({ id: voucher_id });
          if (!voucher) throw new Error("Mã voucher không tồn tại");
          if (voucher.status !== "active")
            throw new Error("Mã voucher không còn hoạt động");
          if (voucher.expiry_date && new Date(voucher.expiry_date) < new Date())
            throw new Error("Mã voucher đã hết hạn");
          if (voucher.usage_limit && voucher.used_count >= voucher.usage_limit)
            throw new Error("Mã voucher đã hết lượt sử dụng");
          await tx.consumeVoucher(voucher_id, user_id);
        }
        const employeeId = currentUserId(actor);
        const shiftId = await tx.activeShiftId(employeeId);
        const requestUserId = Number(user_id || customer_id) || null;
        let customerId =
          customer_id || (order_type === "online" ? requestUserId : null);
        const normalizedStatus = normalizeOrderStatus(
          order_status || status,
          order_type,
        );
        const normalizedPayment =
          payment_status === "unpaid"
            ? "pending"
            : payment_status || (order_type === "online" ? "pending" : "paid");
        let total = 0;
        const normalizedItems = [];
        for (const item of items) {
          const productId = Number(item.product_id || item.productId),
            quantity = Number(item.quantity);
          if (!productId || quantity <= 0) throw new Error("Item không hợp lệ");
          const product = await tx.lockProduct(productId);
          if (!product) throw new Error(`Không tìm thấy sản phẩm ${productId}`);
          if (product.stock < quantity)
            throw new Error(`Không đủ tồn kho cho ${product.product_name}`);
          const price = Number(item.price ?? product.price),
            subtotal = price * quantity;
          total += subtotal;
          normalizedItems.push({ productId, quantity, price, subtotal });
        }
        const amountAfterVoucher = Math.max(0, total - discountAmount);
        let pointsUsed = 0,
          pointsDiscount = 0,
          loyaltyCustomer = null;
        const loyaltyPhone = loyalty.normalizePhone(customer_phone);
        const wantsLoyalty =
          Boolean(loyaltyPhone) ||
          Boolean(customer_name) ||
          use_points === true ||
          use_points === "true" ||
          Number(points_to_use || 0) > 0;
        if (wantsLoyalty) {
          // Existing loyalty operations must share the transaction, never the global pool.
          loyaltyCustomer = await loyalty.ensureCustomerByPhone(connection, {
            customerName: customer_name || "Khách hàng",
            phone: loyaltyPhone,
          });
          customerId = loyaltyCustomer.user_id;
        }
        if (
          use_points === true ||
          use_points === "true" ||
          Number(points_to_use || 0) > 0
        ) {
          if (!loyaltyCustomer)
            throw new Error("Vui lòng tra khách hàng trước khi dùng điểm");
          const redeem = loyalty.validateRedeem({
            pointsToUse: Number(points_to_use || 0),
            availablePoints: Number(loyaltyCustomer.points || 0),
            amountAfterVoucher,
          });
          pointsUsed = redeem.pointsUsed;
          pointsDiscount = redeem.pointsDiscount;
        }
        const finalAmount = Math.max(0, amountAfterVoucher - pointsDiscount);
        const id = await tx.insertOrder({
          customer_id: customerId || null,
          employee_id: employeeId,
          shift_id: shiftId,
          voucher_id: voucher_id || null,
          order_type,
          total_amount: total,
          discount_amount: discountAmount,
          points_used: pointsUsed,
          points_earned: 0,
          points_discount: pointsDiscount,
          final_amount: finalAmount,
          payment_method,
          status: normalizedStatus,
          payment_status: normalizedPayment,
          transaction_id: transaction_id || null,
          transfer_content: transfer_content || null,
          paid_at:
            normalizedPayment === "paid"
              ? paid_at
                ? new Date(paid_at)
                : new Date()
              : null,
          shipping_address: shipping_address || null,
          note: note || null,
        });
        const content =
          payment_method === "bank_transfer"
            ? transfer_content || `DH${id}`
            : transfer_content || null;
        if (content) await tx.setTransferContent(id, content);
        await tx.insertItemsAndReduceStock(id, normalizedItems, Number(actor.user_id || actor.id));
        await tx.insertPayment(
          {
            order_id: id,
            method: payment_method,
            amount: finalAmount,
            status: normalizedPayment,
            transaction_id: transaction_id || null,
            qr_content: qr_content || content || null,
            paid_at: normalizedPayment === "paid" ? new Date() : null,
          },
        );
        if (
          ["paid", "success"].includes(
            String(normalizedPayment || "").toLowerCase(),
          )
        )
          await loyalty.finalizePaidOrderLoyalty(connection, id);
        return id;
      });
      return {
        success: true,
        message: "Đã tạo đơn hàng",
        data: await read.detail(orderId),
      };
    },
  };
}

module.exports = { createOrderCreateService };
