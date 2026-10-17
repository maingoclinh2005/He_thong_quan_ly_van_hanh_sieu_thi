const { ApplicationError } = require("../../errors/application-error");
const { currentUserId, normalizeOrderStatus } = require("./order-policy");

function createOrderStatusService(repository, read) {
  const isDelivery = (order) =>
    order.delivery_method === "delivery" || order.order_type === "delivery";
  async function transition({ id, actor, reason }, action) {
    await repository.transaction(async (tx) => {
      const order = await tx.lockOrder(id);
      if (!order)
        throw new ApplicationError("not_found", "Không tìm thấy đơn hàng");
      const current = normalizeOrderStatus(
        order.status,
        order.order_type,
      );
      if (action === "received") {
        if (Number(order.customer_id) !== currentUserId(actor))
          throw new ApplicationError(
            "forbidden",
            "Bạn chỉ được xác nhận đơn hàng của mình",
          );
        if (current !== "shipping")
          throw new ApplicationError(
            "conflict",
            "Chỉ đơn đang giao mới có thể xác nhận đã nhận hàng",
          );
        if (!isDelivery(order))
          throw new ApplicationError(
            "conflict",
            "Chỉ đơn giao tận nhà mới cần xác nhận đã nhận hàng",
          );
        await tx.updateStatus(id, { status: "completed" });
      } else {
        if (current !== "pending")
          throw new ApplicationError(
            "conflict",
            "Đơn hàng không còn ở trạng thái chờ xác nhận",
          );
        if (action === "reject") await tx.reverseStock(id, currentUserId(actor));
        await tx.updateStatus(id, {
          status:
            action === "reject"
              ? "rejected"
              : isDelivery(order)
                ? "shipping"
                : "completed",
          employeeId: currentUserId(actor),
          confirmation: true,
          assignEmployee: true,
          ...(action === "reject"
            ? { reason: String(reason || "").trim() }
            : { clearReason: true }),
        });
      }
    });
    const messages = {
      confirm: "Đã xác nhận đơn hàng",
      reject: "Đã từ chối đơn hàng",
      received: "Đã xác nhận nhận hàng",
    };
    return {
      success: true,
      message: messages[action],
      data: await read.detail(id),
    };
  }
  return {
    confirm: (input) => transition(input, "confirm"),
    reject: (input) => transition(input, "reject"),
    received: (input) => transition(input, "received"),
    async updateStatus({ id, status, actor }) {
      const value = String(status || "").trim();
      if (
        ![
          "waiting_confirm",
          "pending",
          "confirmed",
          "rejected",
          "shipping",
          "preparing",
          "completed",
          "cancelled",
        ].includes(value)
      ) {
        throw new ApplicationError(
          "invalid",
          "Trạng thái đơn hàng không hợp lệ",
        );
      }
      const normalized = normalizeOrderStatus(value, "online");
      await repository.transaction(async tx => {
        const order = await tx.lockOrder(id);
        if (!order) throw new ApplicationError("not_found", "Không tìm thấy đơn hàng");
        const current = normalizeOrderStatus(order.status, order.order_type);
        if (current === normalized) return;
        const allowed = { pending: ["confirmed", "shipping", "completed", "rejected"],
          confirmed: ["shipping", "completed", "rejected"], shipping: ["completed", "rejected"],
          completed: [], rejected: [] };
        if (!allowed[current]?.includes(normalized))
          throw new ApplicationError("conflict", "Không thể mở lại hoặc lùi trạng thái đơn đã xử lý");
        if (normalized === "rejected") await tx.reverseStock(id, currentUserId(actor));
        await tx.updateStatus(id, {
          status: normalized, employeeId: currentUserId(actor) || null,
          confirmation: ["confirmed", "rejected"].includes(normalized), onlyMissingConfirmation: true,
        });
      });
      return {
        success: true,
        message: "Đã cập nhật trạng thái đơn hàng",
        data: await read.detail(id),
      };
    },
  };
}

module.exports = { createOrderStatusService };
