const express = require("express");
const { requireAuth, requireRoles } = require("../middlewares/auth.middleware");
const controller = require("../composition/inventory");
const router = express.Router();

// All inventory data remains restricted to employees and administrators.
router.use(requireAuth, requireRoles("employee", "admin"));
router.get("/items", controller.list);
router.post("/items", controller.create);
router.put("/items/:id", controller.update);
router.get("/logs", controller.logs);
router.get("/cost/:barcode", controller.cost);
router.post("/import", controller.importStock);
router.post("/adjust", controller.adjust);
router.post("/export", controller.exportStock);

module.exports = router;
