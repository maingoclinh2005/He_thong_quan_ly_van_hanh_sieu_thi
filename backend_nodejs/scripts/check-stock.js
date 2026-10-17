// Read-only reconciliation. Never rebuild projections while application writers run.
const { reconcile } = require('../database/versioned/0003_inventory_ledger');
const { assertSchemaVersion } = require('../src/schema-version');
async function main() {
  const pool = require('../src/config/db');
  let db;
  try {
    db = await pool.getConnection();
    await db.query('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ');
    await db.query('START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY');
    await assertSchemaVersion(db);
    await reconcile(db);
    await db.commit();
    console.log('Stock projections match inventory ledger.');
  } finally {
    if (db) { await db.rollback(); db.release(); }
    await pool.end();
  }
}
main().catch(() => { console.error('Stock reconciliation failed. Check migration state and ledger balances; no data changed.'); process.exitCode = 1; });
