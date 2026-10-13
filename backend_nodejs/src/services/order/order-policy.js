function normalizeOrder(row) {
  const orderStatus = row.order_status || row.status;
  return {
    ...row,
    id: String(row.order_id),
    orderDate: row.created_at,
    totalAmount: Number(row.final_amount),
    customerName: row.customer_name || "Khách lẻ",
    status: orderStatus,
    orderStatus,
    paymentStatus: row.payment_status || row.latest_payment_status,
    paymentMethod: row.payment_method || row.latest_payment_method || "cash",
    transferContent: row.transfer_content || null,
    pointsUsed: Number(row.points_used || 0),
    pointsEarned: Number(row.points_earned || 0),
    pointsDiscount: Number(row.points_discount || 0),
    deliveryMethod: row.delivery_method,
    shippingAddress: row.shipping_address,
    transactionId: row.transaction_id || null,
    paidAt: row.paid_at || null,
  };
}

function normalizeOrderStatus(status, orderType) {
  if (!status) return orderType === "online" ? "pending" : "completed";
  if (status === "waiting_confirm") return "pending";
  if (status === "preparing") return "shipping";
  if (["Hoàn thành", "hoàn thành"].includes(status)) return "completed";
  if (status === "cancelled") return "rejected";
  return status;
}

const currentUserId = (actor) => Number(actor?.id || actor?.user_id);
const isStaff = (actor) => ["admin", "employee"].includes(actor?.role_name);
const canAccessOrder = (actor, order) =>
  Boolean(
    currentUserId(actor) &&
      order &&
      (isStaff(actor) || Number(order.customer_id) === currentUserId(actor)),
  );

function calculateVoucherDiscount(voucher, total) {
  let discount = 0;
  if (voucher.discount_type === "fixed")
    discount = Number(voucher.discount_value);
  else if (voucher.discount_type === "percent") {
    discount = (total * Number(voucher.discount_value)) / 100;
    if (voucher.max_discount && discount > Number(voucher.max_discount))
      discount = Number(voucher.max_discount);
  }
  return Math.min(discount, total);
}

function paymentFlags(status) {
  return {
    isPaid: ["paid", "success"].includes(status),
    isFailed: status === "failed",
    isPending: !["paid", "success", "failed"].includes(status),
  };
}

module.exports = {
  normalizeOrder,
  normalizeOrderStatus,
  currentUserId,
  isStaff,
  canAccessOrder,
  calculateVoucherDiscount,
  paymentFlags,
};
