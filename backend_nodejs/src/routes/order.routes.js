const express = require("express");
const { requireAuth, requireRoles } = require("../middlewares/auth.middleware");
const controller = require("../composition/order");
const router = express.Router();

// Specific paths stay before /:id. Middleware order and aliases are unchanged.
router.get(
  "/",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.list,
);
router.get(
  "/online",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.online,
);
router.get(
  "/pending",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.pending,
);
router.put(
  "/:id/confirm",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.confirm,
);
router.put(
  "/:id/reject",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.reject,
);
router.put("/:id/received", requireAuth, controller.received);
router.post(
  "/checkout",
  requireAuth,
  requireRoles("customer"),
  controller.checkout,
);
router.get("/history", requireAuth, controller.history);
router.get("/history/:customerId", requireAuth, controller.history);
router.get("/status/:orderCode", requireAuth, controller.statusByCode);
router.get("/:id/payment-status", requireAuth, controller.paymentStatus);
router.get("/:id", requireAuth, controller.get);
router.patch(
  "/:id/status",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.updateStatus,
);
router.post(
  "/",
  requireAuth,
  requireRoles("employee", "admin"),
  controller.create,
);

module.exports = router;
