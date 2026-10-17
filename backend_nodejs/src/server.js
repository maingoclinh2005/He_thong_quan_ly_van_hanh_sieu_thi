const express = require("express");
require("dotenv").config();
const { configureSecurity, securityErrorHandler } = require('./middlewares/security');
const { requireAuth, requireRoles } = require('./middlewares/auth.middleware');
const path = require("path");

const pool = require("./config/db");

const app = express();

configureSecurity(app);
const { apiContract, retiredEndpoint } = require('./middlewares/api-contract');
app.use('/api', apiContract);

const authRoutes = require("./routes/auth.routes");
const userRoutes = require("./routes/user.routes");
const categoryRoutes = require("./routes/category.routes");
const productRoutes = require("./routes/product.routes");
const cartRoutes = require("./routes/cart.routes");
const orderRoutes = require("./routes/order.routes");
const inventoryRoutes = require("./routes/inventory.routes");
const uploadRoutes = require("./routes/upload.routes");
const reportRoutes = require("./routes/report.routes");
const performanceRoutes = require("./routes/performance.routes");
const reviewRoutes = require("./routes/review.routes");
const workShiftRoutes = require("./routes/workShift.routes");
const employeeScheduleRoutes = require("./routes/employeeSchedule.routes");
const voucherRoutes = require("./routes/voucher.routes");
const myOrderRoutes = require("./routes/myOrder.routes");
const paymentRoutes = require("./routes/payment.routes");
const pointRoutes = require("./routes/point.routes");

app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/categories", categoryRoutes);
app.use("/api/products", productRoutes);
app.use("/cart", retiredEndpoint("/api/carts"));
app.use("/api/cart", retiredEndpoint("/api/carts"));
app.use("/api/carts", cartRoutes);
app.use("/api/orders", orderRoutes);
app.use("/orders", retiredEndpoint("/api/orders"));
app.use("/my-orders", retiredEndpoint("/api/my-orders"));
app.use("/api/my-orders", myOrderRoutes);
app.use("/api/inventory", inventoryRoutes);
app.use("/api/uploads", uploadRoutes);
app.use("/api/reports", reportRoutes);
app.use("/api/performance", performanceRoutes);
app.use("/api/reviews", reviewRoutes);
app.use("/api/work-shifts", workShiftRoutes);
app.use("/api/employee-schedules", employeeScheduleRoutes);
app.use("/api/vouchers", voucherRoutes);
app.use("/api/payments", paymentRoutes);
// Temporary provider-only compatibility: never expose authenticated payment
// actions through this duplicate mount. Remove after providers migrate URLs.
app.use("/api/webhook", (req, res, next) => {
  if (!/^\/(bank-webhook|sepay|vnpay-return|vnpay-ipn)\/?$/i.test(req.path)) {
    return retiredEndpoint("/api/payments")(req, res);
  }
  res.setHeader('Deprecation', '@1792026000');
  res.setHeader('Link', '</api/payments' + req.path + '>; rel="successor-version"');
  next();
}, paymentRoutes);
app.use("/api/points", pointRoutes);
app.use("/uploads", express.static(path.join(__dirname, "..", "uploads"), {
  dotfiles: 'deny',
  setHeaders: (res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");
  },
}));

app.get("/api/health", (req, res) => {
  res.json({
    success: true,
    message: "Mini Market API is running",
  });
});

app.get("/api/test-db", requireAuth, requireRoles('admin'), async (req, res) => {
  try {
    const [rows] = await pool.execute("SELECT * FROM roles");

    res.json({
      success: true,
      message: "Kết nối database thành công",
      data: rows,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: "Không kết nối được database",
      error: error.message,
    });
  }
});

app.use((req, res) => res.status(404).json({ success: false, message: 'Không tìm thấy API.' }));
app.use(securityErrorHandler);

const PORT = process.env.PORT || 3000;

if (require.main === module) require("./schema-version").assertSchemaVersion(pool).then(() => app.listen(PORT, "0.0.0.0", () => {
  if (process.env.NODE_ENV === 'production' || process.env.REQUIRE_HTTPS === 'true') {
    console.log(`API upstream port ${PORT}; chỉ nhận HTTPS qua reverse proxy tin cậy.`);
    return;
  }
  console.log(`Server đang chạy tại http://localhost:${PORT}`);
  console.log(
    "Điện thoại thật (cùng Wi-Fi): dùng IP máy tính, ví dụ http://192.168.x.x:" +
      PORT,
  );
})).catch(async () => {
  console.error("Backend not started: database unavailable or migration version incompatible. Run npm run migrate:status.");
  process.exitCode = 1;
  await pool.end();
});

module.exports = app;
