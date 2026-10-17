const { ApplicationError } = require("../../errors/application-error");
const {
  normalizeOrder,
  currentUserId,
  isStaff,
  canAccessOrder,
  paymentFlags,
} = require("./order-policy");

function createOrderReadService(repository) {
  async function detail(id) {
    const row = await repository.findById(id);
    if (!row) return null;
    const items = await repository.findItems(id);
    return {
      ...normalizeOrder(row),
      status: row.status,
      items: items.map((item) => ({
        ...item,
        productId: String(item.product_id),
        productName: item.product_name,
        unitPrice: Number(item.price),
        subtotal: Number(item.subtotal),
      })),
    };
  }
  async function details(rows) {
    const result = [];
    for (const row of rows) {
      const order = await detail(row.order_id);
      if (order) result.push(order);
    }
    return result;
  }
  function requireOrder(order) {
    if (!order)
      throw new ApplicationError("not_found", "Không tìm thấy đơn hàng");
  }
  function requireAccess(actor, order) {
    if (!canAccessOrder(actor, order))
      throw new ApplicationError(
        "forbidden",
        "Bạn không có quyền xem đơn hàng này",
      );
  }
  return {
    detail,
    async list() {
      return {
        success: true,
        data: (await repository.listAll()).map(normalizeOrder),
      };
    },
    async myOrders({ actor }) {
      const customerId = currentUserId(actor);
      if (!customerId)
        throw new ApplicationError("unauthorized", "Vui lòng đăng nhập");
      const rows = await repository.listForCustomer(customerId);
      const data = [];
      for (const row of rows) {
        const items = await repository.findCustomerItems(row.order_id);
        const status = row.status || "pending";
        const displayStatus =
          status === "waiting_confirm"
            ? "pending"
            : status === "cancelled"
              ? "rejected"
              : status;
        data.push({
          ...row,
          id: String(row.order_id),
          customerName: row.customer_name || "Khách lẻ",
          totalAmount: Number(row.final_amount),
          payment_method:
            row.payment_method || row.latest_payment_method || "cash",
          payment_status: row.payment_status || row.latest_payment_status,
          display_order_status: displayStatus,
          rejection_reason:
            row.rejection_reason ||
            (displayStatus === "rejected" ? row.note : null),
          items: items.map((item) => ({
            ...item,
            productId: String(item.product_id),
            productName: item.product_name,
            unitPrice: Number(item.price),
            subtotal: Number(item.subtotal),
          })),
        });
      }
      return { success: true, data };
    },
    async online() {
      return {
        success: true,
        data: (await repository.listOnline()).map(normalizeOrder),
      };
    },
    async pending() {
      return {
        success: true,
        data: await details(
          await repository.listOnline({ includeHistory: true }),
        ),
      };
    },
    async get({ id, actor }) {
      const order = await detail(id);
      requireOrder(order);
      requireAccess(actor, order);
      return { success: true, data: order };
    },
    async history({ customerId: requestedId, actor }) {
      const requested = Number(requestedId || 0);
      const customerId = isStaff(actor) ? requested : currentUserId(actor);
      if (requested && !isStaff(actor) && requested !== customerId)
        throw new ApplicationError(
          "forbidden",
          "Bạn chỉ có thể xem lịch sử mua hàng của mình",
        );
      return {
        success: true,
        data: await details(await repository.historyIds(customerId)),
      };
    },
    async statusByCode({ code, actor }) {
      const normalized = String(code || "")
        .trim()
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, "");
      if (!normalized)
        throw new ApplicationError("invalid", "Thiếu mã đơn hàng");
      const id = await repository.findIdByCode(
        normalized,
        Number(normalized.replace(/^DH/, "")) || 0,
      );
      if (!id)
        throw new ApplicationError("not_found", "Không tìm thấy đơn hàng");
      const order = await detail(id);
      requireAccess(actor, order);
      const paymentStatus = String(
        order.paymentStatus || "pending",
      ).toLowerCase();
      return {
        success: true,
        data: {
          orderCode: order.transferContent || `DH${order.id}`,
          orderId: Number(order.id),
          paymentStatus,
          orderStatus: order.orderStatus || order.status,
          status: order.status,
          totalAmount: order.totalAmount,
          paidAt: order.paidAt || null,
          transactionId: order.transactionId || null,
          ...paymentFlags(paymentStatus),
        },
      };
    },
    async paymentStatus({ id, actor }) {
      const userId = currentUserId(actor),
        orderId = Number(id);
      if (!userId)
        throw new ApplicationError("unauthorized", "Vui lòng đăng nhập");
      const order = await detail(orderId);
      requireOrder(order);
      // Keep the existing narrower payment-status permission (assigned employee/customer/admin).
      const access = await repository.paymentAccess(userId, orderId);
      if (
        Number(access.customer_id || 0) !== userId &&
        Number(access.employee_id || 0) !== userId &&
        String(access.role_name || "") !== "admin"
      ) {
        throw new ApplicationError("forbidden", "Không có quyền xem đơn này");
      }
      const latest = await repository.latestPayment(orderId);
      const paymentStatus = String(
        order.paymentStatus || "pending",
      ).toLowerCase();
      return {
        success: true,
        data: {
          orderId,
          paymentStatus,
          orderStatus: order.orderStatus || order.status,
          paymentMethod: order.paymentMethod,
          transactionId: order.transactionId || latest.transaction_id || null,
          paidAt: order.paidAt || latest.paid_at || null,
          transferContent: order.transferContent || null,
          totalAmount: order.totalAmount,
          pointsUsed: order.pointsUsed || 0,
          pointsEarned: order.pointsEarned || 0,
          pointsDiscount: order.pointsDiscount || 0,
          ...paymentFlags(paymentStatus),
        },
      };
    },
  };
}

module.exports = { createOrderReadService };
