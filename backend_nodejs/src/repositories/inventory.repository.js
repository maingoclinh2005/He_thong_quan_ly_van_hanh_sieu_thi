const { withTransaction } = require("./transaction");

function createInventoryRepository(pool, executor = pool) {
  const rows = async (sql, params = []) =>
    (await executor.execute(sql, params))[0];
  return {
    transaction: (work) =>
      withTransaction(pool, (connection) =>
        work(createInventoryRepository(pool, connection)),
      ),
    list: () =>
      rows(
        "SELECT * FROM inventory_items WHERE status <> 'deleted' ORDER BY inventory_item_id DESC",
      ),
    async findById(id) {
      return (
        (
          await rows(
            "SELECT * FROM inventory_items WHERE inventory_item_id = ?",
            [id],
          )
        )[0] || null
      );
    },
    async findByKey(key) {
      return (
        (
          await rows(
            "SELECT * FROM inventory_items WHERE inventory_item_id = ? OR barcode = ?",
            [key, key],
          )
        )[0] || null
      );
    },
    async create(item) {
      const result = await rows(
        `INSERT INTO inventory_items (barcode, item_name, image_url, price, import_price, unit, stock, category_id, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active')`,
        [
          item.barcode,
          item.name,
          item.imageUrl,
          item.price,
          item.importPrice,
          item.unit,
          item.stock,
          item.categoryId,
        ],
      );
      return result.insertId;
    },
    update(key, item) {
      return rows(
        `UPDATE inventory_items SET barcode = COALESCE(?, barcode), item_name = COALESCE(?, item_name),
        image_url = ?, price = COALESCE(?, price), import_price = COALESCE(?, import_price), unit = COALESCE(?, unit),
        stock = COALESCE(?, stock), category_id = COALESCE(?, category_id), status = COALESCE(?, status)
        WHERE inventory_item_id = ? OR barcode = ?`,
        [
          item.barcode,
          item.name,
          item.imageUrl,
          item.price,
          item.importPrice,
          item.unit,
          item.stock,
          item.categoryId,
          item.status,
          key,
          key,
        ],
      );
    },
    logs: () =>
      rows(`SELECT il.*, ii.item_name, ii.barcode, ii.unit, p.product_name, u.full_name AS employee_name
      FROM inventory_logs il JOIN inventory_items ii ON ii.inventory_item_id = il.inventory_item_id
      LEFT JOIN products p ON p.product_id = il.product_id JOIN users u ON u.user_id = il.employee_id ORDER BY il.created_at DESC`),
    async latestCost(key) {
      return (
        (
          await rows(
            `SELECT ii.barcode, COALESCE((SELECT il.import_price FROM inventory_logs il
        WHERE il.inventory_item_id = ii.inventory_item_id AND il.action = 'import' AND il.import_price IS NOT NULL
        ORDER BY il.created_at DESC, il.log_id DESC LIMIT 1), ii.import_price) AS import_price
        FROM inventory_items ii WHERE ii.barcode = ? OR CAST(ii.inventory_item_id AS CHAR) = ? LIMIT 1`,
            [key, key],
          )
        )[0] || null
      );
    },
    async lockItem(key) {
      return (
        (
          await rows(
            "SELECT inventory_item_id, stock FROM inventory_items WHERE inventory_item_id = ? OR barcode = ? FOR UPDATE",
            [key, key],
          )
        )[0] || null
      );
    },
    importStock: (id, quantity, cost) =>
      rows(
        "UPDATE inventory_items SET stock = stock + ?, import_price = ? WHERE inventory_item_id = ?",
        [quantity, cost, id],
      ),
    adjustStock: (id, quantity) =>
      rows("UPDATE inventory_items SET stock = ? WHERE inventory_item_id = ?", [
        quantity,
        id,
      ]),
    exportStock: (id, quantity) =>
      rows(
        "UPDATE inventory_items SET stock = stock - ? WHERE inventory_item_id = ?",
        [quantity, id],
      ),
    logImport: (entry) =>
      rows(
        `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, import_price, note)
      VALUES (?, NULL, ?, 'import', ?, ?, ?)`,
        [
          entry.itemId,
          entry.employeeId,
          entry.quantity,
          entry.importPrice,
          entry.note,
        ],
      ),
    logAdjustment: (entry) =>
      rows(
        `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, note)
      VALUES (?, NULL, ?, 'adjust', ?, ?)`,
        [entry.itemId, entry.employeeId, entry.quantity, entry.note],
      ),
    logExport: (entry) =>
      rows(
        `INSERT INTO inventory_logs (inventory_item_id, product_id, employee_id, action, quantity, note)
      VALUES (?, ?, ?, 'export', ?, ?)`,
        [
          entry.itemId,
          entry.productId,
          entry.employeeId,
          entry.quantity,
          entry.note,
        ],
      ),
  };
}

module.exports = { createInventoryRepository };
