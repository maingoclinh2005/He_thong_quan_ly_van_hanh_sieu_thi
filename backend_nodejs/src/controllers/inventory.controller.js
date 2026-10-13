const { ApplicationError } = require("../errors/application-error");
const statusByKind = { invalid: 400, not_found: 404, conflict: 409 };

function createInventoryController(service) {
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
        next(error);
      }
    };
  const body = (req) => ({ input: req.body });
  return {
    list: handle("list", () => ({})),
    logs: handle("logs", () => ({})),
    cost: handle("cost", (req) => ({ key: req.params.barcode })),
    create: handle("create", body, 201),
    update: handle("update", (req) => ({ id: req.params.id, input: req.body })),
    importStock: handle("importStock", body),
    adjust: handle("adjust", body),
    exportStock: handle("exportStock", body),
  };
}

module.exports = { createInventoryController };
