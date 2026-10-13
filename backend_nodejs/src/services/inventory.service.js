const { createInventoryItemService } = require("./inventory/item.service");
const {
  createInventoryMovementService,
} = require("./inventory/movement.service");

function createInventoryService({ repository }) {
  return {
    ...createInventoryItemService(repository),
    ...createInventoryMovementService(repository),
  };
}

module.exports = { createInventoryService };
