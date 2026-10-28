const mysql = require('mysql2/promise');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

async function main() {
  const email = process.argv[2] || 'a@gmail.com';
  const newPass = process.argv[3] || '123456';
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || '127.0.0.1',
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    port: Number(process.env.DB_PORT || 3306),
    database: process.env.DB_NAME || 'mini_supermarket',
  });
  const [res] = await conn.execute(
    "UPDATE users SET password = ?, password_hash = NULL WHERE email = ?",
    [newPass, email]
  );
  console.log('Updated rows for', email + ':', res.affectedRows);
  await conn.end();
}

main().catch(e => { console.error(e && e.message ? e.message : e); process.exit(1); });
