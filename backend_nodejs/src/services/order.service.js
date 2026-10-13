const { createOrderReadService } = require("./order/read.service");
const { createOrderStatusService } = require("./order/status.service");
const { createOrderCheckoutService } = require("./order/checkout.service");
const { createOrderCreateService } = require("./order/create.service");

// Explicit dependencies let unit tests use an in-memory repository without Express/MySQL.
function createOrderService({ repository, loyalty }) {
  const read = createOrderReadService(repository);
  return {
    ...read,
    ...createOrderStatusService(repository, read),
    ...createOrderCheckoutService(repository, read),
    ...createOrderCreateService(repository, read, loyalty),
  };
}

module.exports = { createOrderService };
