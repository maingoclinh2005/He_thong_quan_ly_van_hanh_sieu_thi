const pool = require("../config/db");
const loyalty = require("../services/loyalty.service");
const { createOrderRepository } = require("../repositories/order.repository");
const { createOrderService } = require("../services/order.service");
const { createOrderController } = require("../controllers/order.controller");

const repository = createOrderRepository(pool);
const service = createOrderService({ repository, loyalty });
module.exports = createOrderController(service);
