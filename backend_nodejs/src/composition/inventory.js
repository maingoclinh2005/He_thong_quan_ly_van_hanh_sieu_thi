const pool = require("../config/db");
const {
  createInventoryRepository,
} = require("../repositories/inventory.repository");
const { createInventoryService } = require("../services/inventory.service");
const {
  createInventoryController,
} = require("../controllers/inventory.controller");

module.exports = createInventoryController(
  createInventoryService({ repository: createInventoryRepository(pool) }),
);
