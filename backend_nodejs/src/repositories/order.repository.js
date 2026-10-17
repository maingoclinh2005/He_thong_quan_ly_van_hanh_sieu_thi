const { withTransaction } = require("./transaction");

const paymentJoinSql = `
  LEFT JOIN (
    SELECT p1.order_id, p1.method, p1.status
    FROM payments p1
    JOIN (
      SELECT order_id, MAX(payment_id) AS payment_id FROM payments GROUP BY order_id
    ) latest ON latest.payment_id = p1.payment_id
  ) pay ON pay.order_id = o.order_id`;
const orderSelect = `SELECT o.*, cu.full_name AS customer_name, eu.full_name AS employee_name,
  pay.method AS latest_payment_method, pay.status AS latest_payment_status
  FROM orders o
  LEFT JOIN users cu ON cu.user_id = o.customer_id
  LEFT JOIN users eu ON eu.user_id = o.employee_id ${paymentJoinSql}`;
const additionalOrderColumns = new Set([
  "shift_id",
  "delivery_method",
  "payment_method",
  "points_used",
  "points_earned",
  "points_discount",
  "transaction_id",
  "transfer_content",
  "paid_at",
]);
const orderInsertColumns = new Set([
  "customer_id",
  "employee_id",
  "voucher_id",
  "order_type",
  "total_amount",
  "discount_amount",
  "final_amount",
  "status",
  "payment_status",
  "shipping_address",
  "note",
  ...additionalOrderColumns,
]);

function createOrderRepository(pool, executor = pool) {
  const rows = async (sql, params = []) =>
    (await executor.execute(sql, params))[0];

  return {
    transaction(work) {
      return withTransaction(pool, (connection) =>
        work(createOrderRepository(pool, connection), connection),
      );
    },
    async findById(id) {
      return (
        (await rows(`${orderSelect} WHERE o.order_id = ?`, [id]))[0] || null
      );
    },
    findItems(id) {
      return rows(
        `SELECT oi.*, p.product_name, p.image_url FROM order_items oi
        JOIN products p ON p.product_id = oi.product_id
        WHERE oi.order_id = ? ORDER BY oi.order_item_id`,
        [id],
      );
    },
    listAll() {
      return rows(`${orderSelect} ORDER BY o.created_at DESC`);
    },
    listForCustomer(customerId) {
      return rows(
        `SELECT o.*, cu.full_name AS customer_name,
        pay.method AS latest_payment_method, pay.status AS latest_payment_status
        FROM orders o LEFT JOIN users cu ON cu.user_id = o.customer_id ${paymentJoinSql}
        WHERE o.customer_id = ? ORDER BY o.created_at DESC`,
        [customerId],
      );
    },
    findCustomerItems(id) {
      return rows(
        `SELECT oi.order_item_id, oi.product_id, oi.quantity, oi.price, oi.subtotal,
        p.product_name, p.image_url FROM order_items oi JOIN products p ON p.product_id = oi.product_id
        WHERE oi.order_id = ? ORDER BY oi.order_item_id`,
        [id],
      );
    },
    async listOnline({ includeHistory = false } = {}) {
      const statusWhere = includeHistory
        ? "o.status IN ('pending', 'confirmed', 'shipping', 'completed', 'rejected')"
        : "o.status IN ('pending', 'confirmed', 'shipping')";
      return rows(`${orderSelect} WHERE o.order_type IN ('online', 'store_pickup', 'delivery')
        AND ${statusWhere} ORDER BY o.created_at DESC, o.order_id DESC`);
    },
    historyIds(customerId) {
      return rows(
        `SELECT o.order_id FROM orders o
        WHERE o.status IN ('completed', 'Hoàn thành', 'hoàn thành')
        ${customerId ? "AND o.customer_id = ?" : ""} ORDER BY o.created_at DESC`,
        customerId ? [customerId] : [],
      );
    },
    async findIdByCode(code, id) {
      return (
        (
          await rows(
            `SELECT order_id FROM orders
        WHERE (UPPER(transfer_content) = ? OR order_id = ?)
        ORDER BY created_at DESC, order_id DESC LIMIT 1`,
            [code, id],
          )
        )[0]?.order_id || null
      );
    },
    async paymentAccess(userId, orderId) {
      return (
        (
          await rows(
            `SELECT o.customer_id, o.employee_id, r.role_name FROM orders o
        LEFT JOIN users u ON u.user_id = ? LEFT JOIN roles r ON r.role_id = u.role_id
        WHERE o.order_id = ? LIMIT 1`,
            [userId, orderId],
          )
        )[0] || {}
      );
    },
    async latestPayment(orderId) {
      return (
        (
          await rows(
            `SELECT * FROM payments WHERE order_id = ? ORDER BY payment_id DESC LIMIT 1`,
            [orderId],
          )
        )[0] || {}
      );
    },
    async lockOrder(id) {
      return (
        (
          await rows("SELECT * FROM orders WHERE order_id = ? FOR UPDATE", [id])
        )[0] || null
      );
    },
    async updateStatus(
      id,
      {
        status,
        employeeId,
        confirmation = false,
        reason,
        clearReason = false,
        assignEmployee = false,
        onlyMissingConfirmation = false,
      },
    ) {
      const setters = ["status = ?"];
      const params = [status];
      if (confirmation) {
        setters.push(
          onlyMissingConfirmation
            ? "confirmed_by = COALESCE(confirmed_by, ?)"
            : "confirmed_by = ?",
        );
        params.push(employeeId || null);
      }
      if (confirmation)
        setters.push(
          onlyMissingConfirmation
            ? "confirmed_at = COALESCE(confirmed_at, NOW())"
            : "confirmed_at = NOW()",
        );
      if (assignEmployee) {
        setters.push("employee_id = COALESCE(employee_id, ?)");
        params.push(employeeId || null);
      }
      if (clearReason) setters.push("rejection_reason = NULL");
      if (reason !== undefined) {
        const field = "rejection_reason";
        if (field) {
          setters.push(`${field} = ?`);
          params.push(reason || null);
        }
      }
      params.push(id);
      const result = await rows(
        `UPDATE orders SET ${setters.join(", ")} WHERE order_id = ?`,
        params,
      );
      return result.affectedRows;
    },
    async activeShiftId(employeeId) {
      if (!employeeId) return null;
      const result = await rows(
        `SELECT shift_id FROM work_shifts WHERE employee_id = ?
        AND end_time IS NULL AND status IN ('active', 'working')
        ORDER BY shift_date DESC, start_time DESC, shift_id DESC LIMIT 1`,
        [employeeId],
      );
      return result[0]?.shift_id || null;
    },
    async lockCart(userId) {
      return (
        (
          await rows(
            "SELECT cart_id FROM carts WHERE user_id = ? LIMIT 1 FOR UPDATE",
            [userId],
          )
        )[0] || null
      );
    },
    lockCartItems(cartId) {
      return rows(
        `SELECT ci.product_id, ci.quantity, p.product_name, p.price, p.stock
        FROM cart_items ci JOIN products p ON p.product_id = ci.product_id WHERE ci.cart_id = ? FOR UPDATE`,
        [cartId],
      );
    },
    async lockProduct(id) {
      return (
        (
          await rows(
            "SELECT product_id, product_name, price, stock FROM products WHERE product_id = ? FOR UPDATE",
            [id],
          )
        )[0] || null
      );
    },
    async lockVoucher({ id, code, activeOnly = false }) {
      return (
        (
          await rows(
            `SELECT * FROM vouchers WHERE ${id ? "voucher_id = ?" : "code = ?"}
        ${activeOnly ? "AND status = 'active'" : ""} FOR UPDATE`,
            [id || code],
          )
        )[0] || null
      );
    },
    async consumeVoucher(voucherId, userId) {
      await rows(
        "UPDATE vouchers SET used_count = used_count + 1 WHERE voucher_id = ?",
        [voucherId],
      );
      if (userId)
        await rows(
          `INSERT INTO user_vouchers (user_id, voucher_id, used_count, last_used_at)
        VALUES (?, ?, 1, NOW()) ON DUPLICATE KEY UPDATE used_count = used_count + 1, last_used_at = NOW()`,
          [userId, voucherId],
        );
    },
    async insertOrder(values) {
      const keys = Object.keys(values).filter((key) => {
        if (!orderInsertColumns.has(key))
          throw new Error("Unsupported order column");
        return true;
      });
      const result = await rows(
        `INSERT INTO orders (${keys.join(", ")}) VALUES (${keys.map(() => "?").join(", ")})`,
        keys.map((key) => values[key]),
      );
      return result.insertId;
    },
    async setTransferContent(id, content) {
      await rows("UPDATE orders SET transfer_content = ? WHERE order_id = ?", [
        content,
        id,
      ]);
    },
    async insertItemsAndReduceStock(orderId, items) {
      for (const item of items) {
        await rows(
          `INSERT INTO order_items (order_id, product_id, quantity, price, subtotal) VALUES (?, ?, ?, ?, ?)`,
          [orderId, item.productId, item.quantity, item.price, item.subtotal],
        );
        await rows(
          "UPDATE products SET stock = stock - ? WHERE product_id = ?",
          [item.quantity, item.productId],
        );
      }
    },
    async insertPayment(values) {
      const allowed = new Set([
        "order_id",
        "method",
        "amount",
        "status",
        "transaction_id",
        "qr_content",
        "paid_at",
      ]);
      const keys = Object.keys(values).filter((key) => {
        if (!allowed.has(key)) throw new Error("Unsupported payment column");
        return true;
      });
      await rows(
        `INSERT INTO payments (${keys.join(", ")}) VALUES (${keys.map(() => "?").join(", ")})`,
        keys.map((key) => values[key]),
      );
    },
    clearCart(cartId) {
      return rows("DELETE FROM cart_items WHERE cart_id = ?", [cartId]);
    },
  };
}

module.exports = { createOrderRepository };
