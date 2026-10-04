const express = require("express");
const router = express.Router();
const voucherController = require("../controllers/voucher.controller");
const { requireAuth, requireRoles, requireSelfOrRoles } = require("../middlewares/auth.middleware");

// PUBLIC ROUTES (khách hàng)
// Validate voucher khi thanh toán
router.post("/validate", voucherController.validateVoucher);

// Lấy danh sách vouchers khả dụng
router.get("/available", voucherController.getAvailableVouchers);

// Lấy chi tiết voucher theo code
router.get("/code/:code", voucherController.getVoucherByCode);

// Lấy danh sách vouchers của user
router.get("/user/:userId", requireAuth, requireSelfOrRoles('admin'), voucherController.getUserVouchers);

router.post("/:id/claim", requireAuth, voucherController.claimVoucher);

// ===== ADMIN ROUTES =====

// Tạo voucher mới (Admin only)
router.post(
  "/",
  requireAuth,
  requireRoles('admin'),
  voucherController.createVoucher,
);

// Lấy tất cả vouchers (Admin only)
router.get(
  "/",
  requireAuth,
  requireRoles('admin'),
  voucherController.getAllVouchers,
);

// Cập nhật voucher (Admin only)
router.put(
  "/:id",
  requireAuth,
  requireRoles('admin'),
  voucherController.updateVoucher,
);

// Xóa voucher (Admin only)
router.delete(
  "/:id",
  requireAuth,
  requireRoles('admin'),
  voucherController.deleteVoucher,
);

// Xem lịch sử sử dụng voucher (Admin only)
router.get(
  "/:id/usage",
  requireAuth,
  requireRoles('admin'),
  voucherController.getVoucherUsage,
);

module.exports = router;
