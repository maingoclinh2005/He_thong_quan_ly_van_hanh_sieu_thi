const pool = require("../config/db");
const loyalty = require("./loyalty.service");

async function insertPaymentRecord(
  connection,
  { orderId, method, amount, status, transactionId, paidAt },
) {
  const insertColumns = ["order_id", "method", "amount", "status"];
  const params = [orderId, method, amount, status];
  insertColumns.push("transaction_id");
  params.push(transactionId || null);
  insertColumns.push("paid_at");
  params.push(paidAt);
  await connection.execute(
    `INSERT INTO payments (${insertColumns.join(", ")})
     VALUES (${insertColumns.map(() => "?").join(", ")})`,
    params,
  );
}

async function getOrderForPayment(orderId, connection = pool) {
  const [rows] = await connection.execute(
    `SELECT order_id, customer_id, employee_id, order_type, delivery_method,
      total_amount, discount_amount, final_amount, payment_method, payment_status,
      status, transaction_id, transfer_content, paid_at, points_used, points_earned,
      points_discount, created_at FROM orders WHERE order_id = ? LIMIT 1`,
    [orderId],
  );
  return rows[0] || null;
}

async function markOrderPaid(
  connection,
  orderId,
  { transactionId, gateway = "vnpay" },
) {
  const order = await getOrderForPayment(orderId, connection);
  if (!order) {
    return {
      ok: false,
      code: "ORDER_NOT_FOUND",
      message: "Không tìm thấy đơn hàng",
    };
  }

  if (
    ["paid", "success"].includes(
      String(order.payment_status || "").toLowerCase(),
    )
  ) {
    return { ok: true, alreadyPaid: true, order };
  }

  const isOffline = String(order.order_type || "").toLowerCase() === "offline";
  const nextStatus = isOffline ? "completed" : order.status || "pending";

  const setParts = ["payment_status = 'paid'"];
  const params = [];

  setParts.push("payment_method = ?");
  params.push(gateway);
  setParts.push("status = ?");
  params.push(nextStatus);

  setParts.push("transaction_id = ?");
  params.push(transactionId);
  setParts.push("paid_at = NOW()");
  setParts.push("updated_at = NOW()");

  params.push(orderId);
  await connection.execute(
    `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
    params,
  );

  await insertPaymentRecord(connection, {
    orderId,
    method: gateway,
    amount: Number(order.final_amount),
    status: "paid",
    transactionId,
    paidAt: new Date(),
  });

  await loyalty.finalizePaidOrderLoyalty(connection, orderId);

  return { ok: true, alreadyPaid: false, order };
}

async function findPendingOrderByTransferContent(connection, transferContent) {
  const normalizedCode = String(transferContent || "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
  const orderIdFromCode = Number(normalizedCode.replace(/^DH/, "")) || 0;
  const whereTransfer =
    "(UPPER(transfer_content) = ? OR note LIKE ? OR order_id = ?)";
  const params = [normalizedCode, `%${normalizedCode}%`, orderIdFromCode];
  const [rows] = await connection.execute(
    `SELECT order_id
     FROM orders
     WHERE ${whereTransfer}
       AND LOWER(COALESCE(payment_status, 'pending')) NOT IN ('paid', 'success')
     ORDER BY created_at DESC, order_id DESC
     LIMIT 1`,
    params,
  );
  return rows[0]?.order_id || null;
}

async function markOrderFailed(
  connection,
  orderId,
  { transactionId, gateway = "vnpay" },
) {
  const order = await getOrderForPayment(orderId, connection);
  if (!order) {
    return {
      ok: false,
      code: "ORDER_NOT_FOUND",
      message: "Không tìm thấy đơn hàng",
    };
  }

  if (
    ["paid", "success"].includes(
      String(order.payment_status || "").toLowerCase(),
    )
  ) {
    return { ok: true, alreadyPaid: true, order };
  }

  const setParts = ["payment_status = 'failed'"];
  const params = [];

  if (transactionId) {
    setParts.push("transaction_id = ?");
    params.push(transactionId);
  }
  setParts.push("updated_at = NOW()");

  params.push(orderId);
  await connection.execute(
    `UPDATE orders SET ${setParts.join(", ")} WHERE order_id = ?`,
    params,
  );

  await insertPaymentRecord(connection, {
    orderId,
    method: gateway,
    amount: Number(order.final_amount),
    status: "failed",
    transactionId,
    paidAt: null,
  });

  return { ok: true, order };
}

module.exports = {
  getOrderForPayment,
  findPendingOrderByTransferContent,
  markOrderPaid,
  markOrderFailed,
};
