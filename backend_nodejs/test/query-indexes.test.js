const test = require("node:test");
const assert = require("node:assert/strict");
const migration = require("../database/versioned/0004_query_indexes");
const step = async (_name, work) => work();
function fixture() {
  const tables = new Map(migration.indexes.map(s => [s.table, new Map()]));
  const ddl = [];
  function add(table, name, columns, comment = "", options = {}) {
    tables.get(table).set(name, columns.map((column, i) => ({
      INDEX_NAME: name, SEQ_IN_INDEX: i + 1, COLUMN_NAME: column,
      SUB_PART: null, COLLATION: "A", INDEX_TYPE: "BTREE",
      INDEX_COMMENT: comment, ...options,
    })));
  }
  const db = {
    execute: async (_sql, [table]) => [[...tables.get(table).values()].flat()],
    query: async sql => {
      ddl.push(sql);
      const addMatch = sql.match(/^ALTER TABLE (\w+) ADD INDEX (\w+) \(([^)]+)\)(?: COMMENT '([^']+)')?$/);
      const dropMatch = sql.match(/^ALTER TABLE (\w+) DROP INDEX (\w+)$/);
      if (addMatch) add(addMatch[1], addMatch[2], addMatch[3].split(", "), addMatch[4]);
      else if (dropMatch) tables.get(dropMatch[1]).delete(dropMatch[2]);
      else throw new Error("Unexpected DDL: " + sql);
      return [{}];
    },
  };
  return { db, tables, ddl, add };
}
test("0004 creates exactly requested indexes; repeat up and up/down/up are safe", async () => {
  const f = fixture();
  await migration.up(f.db, step);
  assert.equal(f.ddl.length, 4);
  for (const spec of migration.indexes)
    assert.deepEqual(f.tables.get(spec.table).get(spec.name).map(r=>r.COLUMN_NAME), spec.columns);
  await migration.up(f.db, step); assert.equal(f.ddl.length, 4);
  await migration.down(f.db, step);
  for (const spec of migration.indexes) assert.ok(!f.tables.get(spec.table).has(spec.name));
  const before=f.ddl.length;
  await migration.down(f.db, step); assert.equal(f.ddl.length,before);
  await migration.up(f.db, step);
  assert.equal(f.ddl.length,before+4);
});
test("0004 preserves equivalent pre-existing indexes, including matching names", async () => {
  const f=fixture();
  for (const spec of migration.indexes) f.add(spec.table,spec.name,spec.columns);
  await migration.up(f.db,step); await migration.down(f.db,step);
  assert.equal(f.ddl.length,0);
});
test("0004 skips covering left-prefix index but not reversed or truncated columns", async () => {
  const f=fixture();
  const [orders, logs, products]=migration.indexes;
  f.add(orders.table,"covering",[...orders.columns,"order_id"]);
  f.add(logs.table,"reversed",[...logs.columns].reverse());
  f.add(products.table,"truncated",products.columns,"",{SUB_PART:3});
  await migration.up(f.db,step);
  assert.equal(f.ddl.length,3);
  assert.ok(!f.tables.get(orders.table).has(orders.name));
});
test("0004 name conflict fails before any DDL", async () => {
  const f=fixture(); const spec=migration.indexes.at(-1);
  f.add(spec.table,spec.name,["status"]);
  await assert.rejects(migration.up(f.db,step),/conflicts/);
  assert.equal(f.ddl.length,0);
});
test("0004 resumes partial DDL without duplicating successful indexes", async () => {
  const f=fixture(); const query=f.db.query; let count=0;
  f.db.query=async sql=>{ if (++count===3) throw new Error("DDL failure"); return query(sql); };
  await assert.rejects(migration.up(f.db,step),/DDL failure/);
  f.db.query=query;
  await migration.up(f.db,step);
  assert.equal(f.ddl.length,4);
});
test("0004 rollback retains FK support and unrelated indexes", async () => {
  const f=fixture();
  f.add("products","existing_category",["category_id"]);
  await migration.up(f.db,step); await migration.down(f.db,step);
  assert.ok(f.tables.get("products").has("existing_category"));
  assert.ok(!f.tables.get("products").has("idx_0004_products_fk_support"));
  assert.ok(f.tables.get("payments").has("idx_0004_payments_fk_support"));
  assert.ok(f.ddl.findIndex(s=>s.includes("ADD INDEX idx_0004_payments_fk_support")) <
    f.ddl.findIndex(s=>s.includes("DROP INDEX idx_0004_payments_order_status")));
});
test("0004 rollback refuses changed definitions without dropping them", async () => {
  const f=fixture(); await migration.up(f.db,step);
  const spec=migration.indexes[0];
  f.add(spec.table,spec.name,["status"],migration.OWNER);
  const before=f.ddl.length;
  await assert.rejects(migration.down(f.db,step),/conflicts/);
  assert.equal(f.ddl.length,before);
});

test("release gate rejects missing, failed or rolled-back 0004", async () => {
  const { assertSchemaVersion } = require("../src/schema-version");
  const base = ["0001","0002","0003"].map(version=>({version,state:"applied"}));
  for (const extra of [[], [{version:"0004",state:"failed"}], [{version:"0004",state:"rolled_back"}]])
    await assert.rejects(assertSchemaVersion({execute:async()=>[[...base,...extra]]}),/migration required/);
});
