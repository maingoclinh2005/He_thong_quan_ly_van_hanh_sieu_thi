const { ApplicationError } = require("../../errors/application-error");
const { quantity } = require("../../domain/stock");

function createInventoryMovementService(repository) {
  function validate(input, adjustment = false) {
    quantity(adjustment ? input.actual_quantity : input.quantity);
    const invalidQuantity = adjustment
      ? Number(input.actual_quantity) < 0
      : Number(input.quantity) <= 0;
    if (!input.inventory_item_id || !input.employee_id || invalidQuantity) {
      throw new ApplicationError(
        "invalid",
        adjustment
          ? "Vui lòng nhập inventory_item_id, employee_id, actual_quantity"
          : "Vui lòng nhập inventory_item_id, employee_id, quantity",
      );
    }
  }
  async function lock(tx, key) {
    const item = await tx.lockItem(key);
    if (!item) throw new Error("Không tìm thấy hàng trong kho");
    return item;
  }
  return {
    async importStock({ input }) {
      validate(input);
      const cost = input.import_price ?? input.importPrice;
      if (cost == null || !Number.isFinite(Number(cost)) || Number(cost) <= 0)
        throw new ApplicationError("invalid", "Giá nhập phải lớn hơn 0");
      await repository.transaction(async (tx) => {
        const item = await lock(tx, input.inventory_item_id);
        const itemId = Number(item.inventory_item_id);
        await tx.importStock(itemId, Number(input.quantity), Number(cost), Number(input.employee_id));
        await tx.logImport({
          itemId,
          employeeId: Number(input.employee_id),
          quantity: Number(input.quantity),
          importPrice: Number(cost),
          note: input.note || null,
        });
      });
      return { success: true, message: "Đã nhập kho" };
    },
    async adjust({ input }) {
      validate(input, true);
      const data = await repository.transaction(async (tx) => {
        const item = await lock(tx, input.inventory_item_id);
        const beforeStock = Number(item.stock),
          actualQuantity = Number(input.actual_quantity),
          difference = actualQuantity - beforeStock;
        const itemId = Number(item.inventory_item_id);
        await tx.adjustStock(itemId, actualQuantity, Number(input.employee_id));
        await tx.logAdjustment({
          itemId,
          employeeId: Number(input.employee_id),
          quantity: difference,
          note: input.note || `Kiểm kê: ${beforeStock} -> ${actualQuantity}`,
        });
        return { beforeStock, actualQuantity, difference };
      });
      return { success: true, message: "Đã điều chỉnh tồn kho", data };
    },
    async exportStock({ input }) {
      validate(input);
      if (input.request_key != null && !/^[a-zA-Z0-9_-]{16,80}$/.test(input.request_key)) throw new ApplicationError("invalid", "request_key không hợp lệ");
      const product = await repository.transaction(async (tx) => {
        const item = await lock(tx, input.inventory_item_id);
        const itemId = Number(item.inventory_item_id);
        const product = await tx.exportStock(itemId, Number(input.quantity), input.product_id, Number(input.employee_id), input.request_key);
        return product;
      });
      return { success: true, message: "Đã chuyển hàng từ kho lên kệ", data: product };
    },
  };
}

module.exports = { createInventoryMovementService };
