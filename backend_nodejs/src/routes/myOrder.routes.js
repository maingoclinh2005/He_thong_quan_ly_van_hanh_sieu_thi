const express = require("express");
const { requireAuth } = require("../middlewares/auth.middleware");
const controller = require("../composition/order");
const router = express.Router();

router.get("/", requireAuth, controller.myOrders);

module.exports = router;
