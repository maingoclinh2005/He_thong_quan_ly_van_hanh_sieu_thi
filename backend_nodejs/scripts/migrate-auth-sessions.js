const fs = require('node:fs/promises');
const path = require('node:path');
const pool = require('../src/config/db');

async function main() {
  // Requires the existing customer-auth migration (password_hash). No user data is rewritten.
  const [columns] = await pool.execute("SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'password_hash'");
  if (columns.length !== 1) throw new Error('Apply 2026-06-02-customer-auth-password-reset.sql first');
  const sql = await fs.readFile(path.join(__dirname, '../database/migrations/2026-10-08-auth-sessions.sql'), 'utf8');
  for (const statement of sql.split(';').map(value => value.trim()).filter(Boolean)) await pool.query(statement);
  console.log('Auth session tables are ready. Existing user data was not changed.');
}
main().catch(() => {
  console.error('Auth session migration failed. Check database connectivity, schema and DDL permissions.');
  process.exitCode = 1;
}).finally(() => pool.end());
