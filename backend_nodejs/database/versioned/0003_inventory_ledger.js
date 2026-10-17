async function tableExists(db, table) {
  return (await db.execute('SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', [table]))[0].length > 0;
}
async function ownCategoryFk(db) {
  return (await db.execute("SELECT CONSTRAINT_NAME FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND CONSTRAINT_NAME = 'fk_inventory_category_ledger'"))[0].length > 0;
}
async function preflight(db) {
  if (await tableExists(db, 'inventory_ledger_0003_archive'))
    throw new Error('Ledger rollback archive exists. Reconcile legacy writes with a new reviewed migration; do not overwrite history.');
  for (const table of ['products', 'inventory_items']) {
    const [bad] = await db.execute(`SELECT 1 FROM ${table} t LEFT JOIN categories c ON c.category_id = t.category_id
      WHERE t.stock IS NULL OR t.stock < 0 OR t.stock <> FLOOR(t.stock) OR t.stock > 2147483647
        OR c.category_id IS NULL OR t.barcode IS NULL OR TRIM(t.barcode) = '' LIMIT 1`);
    if (bad.length) throw new Error('Invalid stock/barcode/category in ' + table + '; reconcile before migration');
    const [duplicates] = await db.execute(`SELECT barcode FROM ${table} GROUP BY barcode HAVING COUNT(*) > 1 LIMIT 1`);
    if (duplicates.length) throw new Error('Duplicate barcode in ' + table);
  }
  const [mismatch] = await db.execute(`SELECT ii.inventory_item_id FROM inventory_items ii
    JOIN products p ON p.barcode = ii.barcode
    WHERE NOT (ii.unit <=> p.unit) OR ii.category_id <> p.category_id LIMIT 1`);
  if (mismatch.length) throw new Error('Warehouse/shelf unit or category mismatch; reconcile before migration');
  const [badItems] = await db.execute(`SELECT oi.order_item_id FROM order_items oi
    JOIN orders o ON o.order_id = oi.order_id WHERE o.status IN ('pending','confirmed','shipping')
    AND (oi.quantity IS NULL OR oi.quantity <= 0 OR oi.quantity <> FLOOR(oi.quantity)) LIMIT 1`);
  if (badItems.length) throw new Error('Invalid active order quantities');
}
async function reconcile(db, write = false) {
  for (const [table, id, location] of [['products', 'product_id', 'shelf'], ['inventory_items', 'inventory_item_id', 'warehouse']]) {
    const join = `LEFT JOIN (SELECT ${id}, SUM(delta) AS quantity FROM inventory_ledger WHERE location = '${location}' GROUP BY ${id}) l ON l.${id} = t.${id}`;
    const [invalid] = await db.execute(`SELECT t.${id} FROM ${table} t ${join} WHERE COALESCE(l.quantity,0) < 0 OR COALESCE(l.quantity,0) > 2147483647 LIMIT 1`);
    if (invalid.length) throw new Error('Invalid ledger balance');
    if (write) await db.query(`UPDATE ${table} t ${join} SET t.stock = COALESCE(l.quantity,0)`);
    else {
      const [diff] = await db.execute(`SELECT t.${id} FROM ${table} t ${join} WHERE t.stock <> COALESCE(l.quantity,0) LIMIT 1`);
      if (diff.length) throw new Error('Stock projection differs from ledger: ' + table);
    }
  }
}
async function up(db, step) {
  await step('preflight', () => preflight(db));
  await step('create-ledger', () => db.query(`CREATE TABLE IF NOT EXISTS inventory_ledger (
    ledger_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_key VARCHAR(120) CHARACTER SET ascii COLLATE ascii_bin NOT NULL UNIQUE,
    operation_id VARCHAR(100) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    location VARCHAR(20) NOT NULL, inventory_item_id INT NULL, product_id INT NULL,
    delta BIGINT NOT NULL, kind VARCHAR(30) NOT NULL,
    actor_id INT NULL, order_id INT NULL, note VARCHAR(255) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ledger_warehouse (inventory_item_id, location, ledger_id),
    INDEX idx_ledger_shelf (product_id, location, ledger_id),
    INDEX idx_ledger_order (order_id, kind),
    CONSTRAINT fk_ledger_inventory FOREIGN KEY (inventory_item_id) REFERENCES inventory_items(inventory_item_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_product FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,
    CONSTRAINT fk_ledger_actor FOREIGN KEY (actor_id) REFERENCES users(user_id) ON DELETE SET NULL,
    CONSTRAINT fk_ledger_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE RESTRICT,
    CONSTRAINT ck_ledger_account CHECK (
      (location = 'warehouse' AND inventory_item_id IS NOT NULL AND product_id IS NULL) OR
      (location = 'shelf' AND product_id IS NOT NULL AND inventory_item_id IS NULL))
  ) ENGINE=InnoDB`));
  await step('category-foreign-key', async () => {
    if (!(await ownCategoryFk(db))) await db.query('ALTER TABLE inventory_items ADD CONSTRAINT fk_inventory_category_ledger FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE RESTRICT ON UPDATE CASCADE');
  });
  await step('opening-balances-and-active-reservations', async () => {
    await db.beginTransaction();
    try {
      await db.query(`INSERT INTO inventory_ledger (event_key,operation_id,location,inventory_item_id,delta,kind)
        SELECT CONCAT('opening:warehouse:',i.inventory_item_id),'migration0003','warehouse',i.inventory_item_id,i.stock,'opening'
        FROM inventory_items i WHERE NOT EXISTS (SELECT 1 FROM inventory_ledger l WHERE l.event_key = CONCAT('opening:warehouse:',i.inventory_item_id))`);
      // Current shelf stock already excludes active orders. Add their deductions
      // to the opening credit, then record sales so future rejection can reverse.
      await db.query(`INSERT INTO inventory_ledger (event_key,operation_id,location,product_id,delta,kind)
        SELECT CONCAT('opening:shelf:',p.product_id),'migration0003','shelf',p.product_id,p.stock + COALESCE(r.quantity,0),'opening'
        FROM products p LEFT JOIN (SELECT oi.product_id,SUM(oi.quantity) AS quantity FROM order_items oi
        JOIN orders o ON o.order_id=oi.order_id WHERE o.status IN ('pending','confirmed','shipping') GROUP BY oi.product_id) r ON r.product_id=p.product_id
        WHERE NOT EXISTS (SELECT 1 FROM inventory_ledger l WHERE l.event_key = CONCAT('opening:shelf:',p.product_id))`);
      await db.query(`INSERT INTO inventory_ledger (event_key,operation_id,location,product_id,delta,kind,order_id)
        SELECT CONCAT('sale:',o.order_id,':',oi.product_id),'migration0003','shelf',oi.product_id,-SUM(oi.quantity),'sale',o.order_id
        FROM order_items oi JOIN orders o ON o.order_id=oi.order_id
        WHERE o.status IN ('pending','confirmed','shipping') AND NOT EXISTS
        (SELECT 1 FROM inventory_ledger l WHERE l.event_key = CONCAT('sale:',o.order_id,':',oi.product_id))
        GROUP BY o.order_id,oi.product_id`);
      await reconcile(db);
      await db.commit();
    } catch (error) { await db.rollback(); throw error; }
  });
}
async function down(db, step) {
  await step('preserve-projections-and-archive-ledger', async () => {
    if (await tableExists(db, 'inventory_ledger')) {
      if (await tableExists(db, 'inventory_ledger_0003_archive')) throw new Error('Archive already exists; refusing overwrite');
      await reconcile(db, true);
      await db.query('RENAME TABLE inventory_ledger TO inventory_ledger_0003_archive');
    } else if (!(await tableExists(db, 'inventory_ledger_0003_archive'))) {
      throw new Error('Both ledger and archive missing');
    }
  });
  await step('remove-added-category-constraint', async () => {
    if (await ownCategoryFk(db)) await db.query('ALTER TABLE inventory_items DROP FOREIGN KEY fk_inventory_category_ledger');
  });
}
module.exports = { version: '0003', name: 'inventory_ledger', up, down, preflight, reconcile };
