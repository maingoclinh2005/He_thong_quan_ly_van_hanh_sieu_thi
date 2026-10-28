const mysql = require("mysql2/promise"); // Đảm bảo đã require thư viện
require("dotenv").config();

// Khởi tạo biến pool
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT || 4000,
  // Enable SSL only when explicitly requested via DB_SSL env var.
  ...(process.env.DB_SSL === 'true'
    ? { ssl: { rejectUnauthorized: false } }
    : {}),
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

// Xuất biến pool ra để server.js sử dụng
module.exports = pool;
