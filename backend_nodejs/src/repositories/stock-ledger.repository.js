const { randomUUID } = require('node:crypto');
const { ApplicationError } = require('../errors/application-error');
const accounts = {
  warehouse: { table: 'inventory_items', id: 'inventory_item_id' },
  shelf: { table: 'products', id: 'product_id' },
};
const { quantity } = require("../domain/stock");

// All methods MUST run on the caller's transaction connection, never the pool.
function createStockLedger(connection) {
  async function balance(location, id) {
    const account = accounts[location];
    if (!account) throw new Error('Unknown stock location');
    const [rows] = await connection.execute(
      `SELECT * FROM ${account.table} WHERE ${account.id} = ? FOR UPDATE`, [id]);
    if (!rows[0]) throw new ApplicationError('not_found', 'Không tìm thấy mặt hàng');
    // Locking reads see latest committed entries even under REPEATABLE READ.
    const [entries] = await connection.execute(
      `SELECT delta FROM inventory_ledger WHERE ${account.id} = ? AND location = ? FOR UPDATE`, [id, location]);
    const total = quantity(entries.reduce((sum, row) => sum + Number(row.delta), 0));
    return { row: rows[0], total };
  }
  async function post({ location, id, delta, kind, eventKey = randomUUID(),
    operationId = randomUUID(), actorId = null, orderId = null, note = null }) {
    delta = quantity(delta, { signed: true });
    const { total } = await balance(location, id);
    const account = accounts[location];
    const [existing] = await connection.execute(
      'SELECT * FROM inventory_ledger WHERE event_key = ? FOR UPDATE', [eventKey]);
    if (existing.length) {
      const entry = existing[0];
      if (entry.location !== location || Number(entry[account.id]) !== Number(id) ||
          Number(entry.delta) !== delta || entry.kind !== kind || Number(entry.order_id || 0) !== Number(orderId || 0))
        throw new ApplicationError('conflict', 'Mã biến động tồn kho đã được dùng cho thao tác khác');
      return total;
    }
    const next = total + delta;
    if (next < 0) throw new ApplicationError('conflict', 'Không đủ tồn kho');
    quantity(next);
    await connection.execute(
      `INSERT INTO inventory_ledger
        (event_key, operation_id, location, inventory_item_id, product_id, delta, kind, actor_id, order_id, note)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [eventKey, operationId, location, location === 'warehouse' ? id : null,
        location === 'shelf' ? id : null, delta, kind, actorId, orderId, note]);
    // Projections, never independent sources. Rebuilt from current ledger balance.
    await connection.execute(`UPDATE ${account.table} SET stock = ? WHERE ${account.id} = ?`, [next, id]);
    return next;
  }
  async function set(location, id, target, actorId, kind = 'adjustment') {
    target = quantity(target);
    const { total } = await balance(location, id);
    if (target !== total) await post({ location, id, delta: target - total, actorId, kind });
    return target;
  }
  async function reverseOrder(orderId, actorId) {
    const [sales] = await connection.execute(
      "SELECT * FROM inventory_ledger WHERE order_id = ? AND kind = 'sale' ORDER BY product_id, ledger_id FOR UPDATE", [orderId]);
    for (const sale of sales) await post({
      location: 'shelf', id: sale.product_id, delta: -Number(sale.delta),
      kind: 'sale_reversal', orderId, actorId, eventKey: 'reverse:' + sale.ledger_id,
    });
  }
  return { balance, post, set, reverseOrder };
}
module.exports = { createStockLedger, quantity };
