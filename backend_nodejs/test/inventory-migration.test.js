const test = require('node:test');
const assert = require('node:assert/strict');
const migration = require('../database/versioned/0003_inventory_ledger');
const { assertSchemaVersion } = require('../src/schema-version');
const step = async (_name, fn) => fn();
function fake(respond = () => []) {
  const calls = [];
  return { calls,
    execute: async (sql,p=[]) => { calls.push(sql); return [respond(sql,p)]; },
    query: async sql => { calls.push(sql); return [{}]; },
    beginTransaction: async () => calls.push('BEGIN'),
    commit: async () => calls.push('COMMIT'),
    rollback: async () => calls.push('ROLLBACK'),
  };
}
test('0003 refuses bad opening stock/category before DDL', async () => {
  const db=fake(sql=>sql.includes('SELECT 1 FROM products')?[{bad:1}]:[]);
  await assert.rejects(migration.up(db,step), /Invalid stock/);
  assert.ok(!db.calls.some(sql=>sql.startsWith('CREATE')));
});
test('0003 refuses warehouse/shelf metadata mismatch', async () => {
  const db=fake(sql=>sql.includes('SELECT ii.inventory_item_id')?[{id:1}]:[]);
  await assert.rejects(migration.preflight(db), /mismatch/);
});
test('0003 creates constrained ledger and seeds active order deductions atomically', async () => {
  const db=fake(); await migration.up(db,step);
  assert.ok(db.calls.some(sql=>sql.includes('fk_ledger_product')&&sql.includes('ck_ledger_account')));
  assert.ok(db.calls.some(sql=>sql.includes('ADD CONSTRAINT fk_inventory_category_ledger')));
  assert.ok(db.calls.some(sql=>sql.includes("-SUM(oi.quantity),'sale'")));
  assert.ok(db.calls.some(sql=>sql.includes("p.stock + COALESCE(r.quantity,0)")));
  assert.ok(db.calls.indexOf('BEGIN')<db.calls.indexOf('COMMIT'));
  assert.ok(!db.calls.includes('ROLLBACK'));
});
test('0003 projection mismatch rolls back seed transaction', async () => {
  const db=fake(sql=>sql.includes('t.stock <> COALESCE')?[{id:2}]:[]);
  await assert.rejects(migration.up(db,step), /projection differs/);
  assert.ok(db.calls.includes('ROLLBACK')); assert.ok(!db.calls.includes('COMMIT'));
});
test('0003 rollback archives history, rebuilds projections and never drops ledger', async () => {
  const db=fake((sql,p)=> sql.includes('information_schema.TABLES')&&p[0]==='inventory_ledger'?[{}]:[]);
  await migration.down(db,step);
  assert.ok(db.calls.some(sql=>sql.startsWith('UPDATE products')));
  assert.ok(db.calls.some(sql=>sql.startsWith('RENAME TABLE inventory_ledger')));
  assert.ok(!db.calls.some(sql=>sql.startsWith('DROP TABLE')));
});
test('0003 refuses re-up after archived rollback', async () => {
  const db=fake((sql,p)=>p[0]==='inventory_ledger_0003_archive'?[{}]:[]);
  await assert.rejects(migration.up(db,step), /archive exists/);
});
test('startup requires all three applied migrations', async () => {
  await assertSchemaVersion({execute:async()=>[[...['0001','0002','0003'].map(version=>({version,state:'applied'}))]]});
  await assert.rejects(assertSchemaVersion({execute:async()=>[[{version:'0001',state:'applied'},{version:'0002',state:'applied'}]]}));
});
