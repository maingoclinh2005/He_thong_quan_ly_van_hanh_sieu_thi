const OWNER = "migration:0004_query_indexes";
const indexes = [
  { table: "orders", name: "idx_0004_orders_created_status_customer", columns: ["created_at", "status", "customer_id"] },
  { table: "inventory_logs", name: "idx_0004_logs_created_item", columns: ["created_at", "inventory_item_id"] },
  { table: "products", name: "idx_0004_products_category_status", columns: ["category_id", "status"], fkColumn: "category_id" },
  { table: "payments", name: "idx_0004_payments_order_status", columns: ["order_id", "status"], fkColumn: "order_id" },
];

// Schema inspection is restricted to migration time, never request handling.
async function readIndexes(db, table) {
  const [rows] = await db.execute(
    "SELECT INDEX_NAME, SEQ_IN_INDEX, COLUMN_NAME, SUB_PART, COLLATION, INDEX_TYPE, INDEX_COMMENT FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY INDEX_NAME, SEQ_IN_INDEX",
    [table],
  );
  const grouped = new Map();
  for (const row of rows) {
    if (!grouped.has(row.INDEX_NAME)) grouped.set(row.INDEX_NAME, []);
    grouped.get(row.INDEX_NAME).push(row);
  }
  return grouped;
}
function covers(rows, columns) {
  return rows && columns.every((column, i) =>
    rows[i]?.COLUMN_NAME === column && rows[i].SUB_PART == null &&
    rows[i].COLLATION === "A" && rows[i].INDEX_TYPE === "BTREE");
}
function exact(rows, spec) {
  return rows?.length === spec.columns.length && covers(rows, spec.columns);
}
async function validateNames(db) {
  for (const spec of indexes) {
    const rows = (await readIndexes(db, spec.table)).get(spec.name);
    if (rows && !exact(rows, spec)) throw new Error("Index name conflicts with expected definition: " + spec.name);
  }
}
async function up(db, step) {
  await step("preflight-index-names", () => validateNames(db));
  for (const spec of indexes) await step("add-" + spec.name, async () => {
    const existing = await readIndexes(db, spec.table);
    if ([...existing.values()].some(rows => covers(rows, spec.columns))) return;
    // Identifiers and comment are fixed constants, never user input.
    await db.query(`ALTER TABLE ${spec.table} ADD INDEX ${spec.name} (${spec.columns.join(", ")}) COMMENT '${OWNER}'`);
  });
}
async function down(db, step) {
  await step("preflight-index-names", () => validateNames(db));
  for (const spec of [...indexes].reverse()) await step("drop-" + spec.name, async () => {
    const existing = await readIndexes(db, spec.table);
    const own = existing.get(spec.name);
    // Preserve pre-existing equivalent indexes, even when their name matches.
    if (!own || own[0].INDEX_COMMENT !== OWNER) return;
    // MySQL can discard an implicit FK index when a wider index replaces it.
    // Restore a narrow supporting index before dropping our composite index.
    if (spec.fkColumn && ![...existing.entries()].some(([name, rows]) =>
      name !== spec.name && covers(rows, [spec.fkColumn]))) {
      const fallback = "idx_0004_" + spec.table + "_fk_support";
      if (existing.has(fallback)) throw new Error("FK fallback index name conflict: " + fallback);
      await db.query(`ALTER TABLE ${spec.table} ADD INDEX ${fallback} (${spec.fkColumn})`);
    }
    await db.query(`ALTER TABLE ${spec.table} DROP INDEX ${spec.name}`);
  });
}
module.exports = { version: "0004", name: "query_indexes", up, down, indexes, OWNER };
