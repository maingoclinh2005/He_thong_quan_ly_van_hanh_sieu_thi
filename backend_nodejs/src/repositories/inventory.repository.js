const { withTransaction } = require("./transaction");
const { createStockLedger, quantity } = require("./stock-ledger.repository");
const { ApplicationError } = require("../errors/application-error");
const { randomUUID } = require("node:crypto");

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
      if (executor === pool) return withTransaction(pool, tx => createInventoryRepository(pool, tx).create(item));
      quantity(item.stock);
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
          0,
          item.categoryId,
        ],
      );
      await createStockLedger(executor).set("warehouse", result.insertId, item.stock, item.actorId, "opening");
      return result.insertId;
    },
    async update(key, item) {
      if (executor === pool) return withTransaction(pool, tx => createInventoryRepository(pool, tx).update(key, item));
      const current = await this.lockItem(key);
      if (!current) throw new ApplicationError("not_found", "Không tìm thấy hàng trong kho");
      if ((item.barcode && item.barcode !== current.barcode) || (item.unit && item.unit !== current.unit))
        throw new ApplicationError("conflict", "Không đổi mã hàng/đơn vị của tài khoản tồn kho");
      if (item.stock != null) await createStockLedger(executor).set("warehouse", current.inventory_item_id, item.stock, item.actorId);
      return rows(
        `UPDATE inventory_items SET barcode = COALESCE(?, barcode), item_name = COALESCE(?, item_name),
        image_url = ?, price = COALESCE(?, price), import_price = COALESCE(?, import_price), unit = COALESCE(?, unit),
        category_id = COALESCE(?, category_id), status = COALESCE(?, status)
        WHERE inventory_item_id = ?`,
        [
          item.barcode,
          item.name,
          item.imageUrl,
          item.price,
          item.importPrice,
          item.unit,
          item.categoryId,
          item.status,
          current.inventory_item_id,
        ],
      );
    },
    logs: () => rows(`SELECT l.ledger_id AS log_id, l.inventory_item_id, l.actor_id AS employee_id,
      CASE l.kind WHEN 'receipt' THEN 'import' WHEN 'opening' THEN 'import' WHEN 'transfer' THEN 'export' ELSE 'adjust' END AS action,
      l.delta AS quantity, l.note, l.created_at, ii.item_name, ii.barcode, ii.unit, u.full_name AS employee_name
      FROM inventory_ledger l JOIN inventory_items ii ON ii.inventory_item_id = l.inventory_item_id
      LEFT JOIN users u ON u.user_id = l.actor_id WHERE l.location = 'warehouse' ORDER BY l.ledger_id DESC`),
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
      const found = (await rows("SELECT * FROM inventory_items WHERE barcode = ? OR inventory_item_id = ? ORDER BY (barcode = ?) DESC LIMIT 1 FOR UPDATE", [key, key, key]))[0];
      if (!found) return null;
      const { total } = await createStockLedger(executor).balance("warehouse", found.inventory_item_id);
      return { ...found, stock: total };
    },
    async importStock(id, amount, cost, actorId) {
      await createStockLedger(executor).post({ location: "warehouse", id, delta: amount, kind: "receipt", actorId });
      return rows("UPDATE inventory_items SET import_price = ? WHERE inventory_item_id = ?", [cost, id]);
    },
    adjustStock: (id, target, actorId) => createStockLedger(executor).set("warehouse", id, target, actorId),
    async exportStock(id, amount, productId, actorId, requestKey) {
      quantity(amount);
      const { row: item } = await createStockLedger(executor).balance("warehouse", id);
      const [products] = await executor.execute("SELECT * FROM products WHERE barcode = ? FOR UPDATE", [item.barcode]);
      let product = products[0];
      if (productId && (!product || Number(productId) !== Number(product.product_id)))
        throw new ApplicationError("conflict", "Sản phẩm trên kệ không khớp mã hàng trong kho");
      if (product && (product.unit !== item.unit || Number(product.category_id) !== Number(item.category_id)))
        throw new ApplicationError("conflict", "Đơn vị hoặc danh mục kho/kệ không khớp");
      if (!product) {
        const [created] = await executor.execute(
          "INSERT INTO products (product_name, barcode, image_url, price, unit, stock, min_stock, category_id, status) VALUES (?, ?, ?, ?, ?, 0, 10, ?, 'active')",
          [item.item_name, item.barcode, item.image_url, item.price, item.unit, item.category_id]);
        product = { product_id: created.insertId };
      }
      const operationId = requestKey || randomUUID();
      const ledger = createStockLedger(executor);
      await ledger.post({ location: "warehouse", id, delta: -amount, kind: "transfer", actorId,
        operationId, eventKey: operationId + ":warehouse" });
      await ledger.post({ location: "shelf", id: product.product_id, delta: amount, kind: "transfer", actorId,
        operationId, eventKey: operationId + ":shelf" });
      return (await rows("SELECT * FROM products WHERE product_id = ?", [product.product_id]))[0];
    },
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
