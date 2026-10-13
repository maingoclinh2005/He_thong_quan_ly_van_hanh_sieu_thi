const { ApplicationError } = require("../errors/application-error");
const statusByKind = {
  invalid: 400,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
};

function createOrderController(service) {
  const handle =
    (action, input, status = 200) =>
    async (req, res, next) => {
      try {
        res.status(status).json(await service[action](input(req)));
      } catch (error) {
        if (error instanceof ApplicationError && statusByKind[error.kind]) {
          return res
            .status(statusByKind[error.kind])
            .json({ success: false, message: error.message });
        }
        next(error); // Existing security handler masks internal errors and keeps request IDs.
      }
    };
  const identity = (req) => ({ id: req.params.id, actor: req.user });
  return {
    list: handle("list", () => ({})),
    online: handle("online", () => ({})),
    pending: handle("pending", () => ({})),
    myOrders: handle("myOrders", (req) => ({ actor: req.user })),
    confirm: handle("confirm", identity),
    received: handle("received", identity),
    reject: handle("reject", (req) => ({
      ...identity(req),
      reason: req.body.reason || req.body.rejection_reason,
    })),
    checkout: handle(
      "checkout",
      (req) => ({ input: req.body, actor: req.user }),
      201,
    ),
    history: handle("history", (req) => ({
      customerId: req.params.customerId,
      actor: req.user,
    })),
    statusByCode: handle("statusByCode", (req) => ({
      code: req.params.orderCode,
      actor: req.user,
    })),
    paymentStatus: handle("paymentStatus", identity),
    get: handle("get", identity),
    updateStatus: handle("updateStatus", (req) => ({
      ...identity(req),
      status: req.body.status,
    })),
    create: handle(
      "create",
      (req) => ({ input: req.body, actor: req.user }),
      201,
    ),
  };
}

module.exports = { createOrderController };
