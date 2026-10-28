const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mysql = require('mysql2/promise');

async function main() {
  try {
    const sqlPath = path.resolve(__dirname, '../../database.sql');
    console.log('Reading', sqlPath);
    let sql = fs.readFileSync(sqlPath, 'utf8');

    // Strip BOM if present
    if (sql.charCodeAt(0) === 0xfeff) sql = sql.slice(1);

    // Remove single-line comments starting with -- and block comments /* */
    const lines = sql.split(/\r?\n/);
    let inBlock = false;
    const cleaned = [];
    for (let line of lines) {
      const t = line.trim();
      if (!inBlock) {
        if (t.startsWith('/*')) {
          inBlock = true;
          if (t.endsWith('*/')) inBlock = false;
          continue;
        }
        if (t.startsWith('--')) continue;
        cleaned.push(line);
      } else {
        if (t.endsWith('*/')) inBlock = false;
      }
    }
    sql = cleaned.join('\n');

    // Disable foreign key checks during import to avoid ordering issues
    sql = 'SET FOREIGN_KEY_CHECKS=0;\n' + sql + '\nSET FOREIGN_KEY_CHECKS=1;';

    const conn = await mysql.createConnection({
      host: process.env.DB_HOST || '127.0.0.1',
      user: process.env.DB_USER || 'root',
      password: process.env.DB_PASSWORD || '',
      port: Number(process.env.DB_PORT || 3306),
      multipleStatements: true,
      // optional SSL: only if DB_SSL=true
      ...(process.env.DB_SSL === 'true' ? { ssl: { rejectUnauthorized: false } } : {}),
    });

    console.log('Connected to MySQL, executing SQL...');
    await conn.query(sql);
    console.log('Database import completed successfully');
    await conn.end();
  } catch (err) {
    console.error('Import failed:', err && err.message ? err.message : err);
    process.exit(1);
  }
}

main();
