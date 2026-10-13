const { ApplicationError } = require("../../errors/application-error");

function toInventoryItem(row) {
  const importPrice =
    row.import_price == null ? null : Number(row.import_price);
  const categoryId = row.category_id == null ? null : Number(row.category_id);
  return {
    id: row.barcode,
    inventory_item_id: row.inventory_item_id,
    barcode: row.barcode,
    name: row.item_name,
    item_name: row.item_name,
    image_url: row.image_url,
    price: Number(row.price),
    import_price: importPrice,
    importPrice,
    unit: row.unit || "sp",
    stockQuantity: row.stock,
    stock: row.stock,
    category_id: categoryId,
    categoryId,
    status: row.status,
  };
}

function createInventoryItemService(repository) {
  function validateImportPrice(value) {
    if (value != null && Number(value) <= 0)
      throw new ApplicationError("invalid", "Giá nhập phải lớn hơn 0");
  }
  return {
    async list() {
      return {
        success: true,
        data: (await repository.list()).map(toInventoryItem),
      };
    },
    async logs() {
      return { success: true, data: await repository.logs() };
    },
    async cost({ key }) {
      const row = await repository.latestCost(key);
      return {
        success: true,
        data: {
          import_price:
            row?.import_price == null ? null : Number(row.import_price),
        },
      };
    },
    async create({ input }) {
      const name = input.item_name || input.name;
      if (!input.barcode || !name || input.price == null)
        throw new ApplicationError(
          "invalid",
          "Vui lòng nhập barcode, item_name, price",
        );
      const importPrice = input.import_price ?? input.importPrice;
      validateImportPrice(importPrice);
      if (input.category_id == null && input.categoryId == null)
        throw new ApplicationError("invalid", "Vui lòng nhập category_id");
      try {
        const id = await repository.create({
          barcode: input.barcode,
          name,
          imageUrl: input.image_url || null,
          price: Number(input.price),
          importPrice: importPrice == null ? null : Number(importPrice),
          unit: input.unit || "sp",
          stock: Number(input.stock ?? input.stockQuantity ?? 0),
          categoryId: Number(input.category_id ?? input.categoryId),
        });
        return {
          success: true,
          message: "Đã thêm hàng vào kho",
          data: toInventoryItem(await repository.findById(id)),
        };
      } catch (error) {
        if (error.code === "ER_DUP_ENTRY")
          throw new ApplicationError("conflict", "Lỗi thêm hàng vào kho");
        throw error;
      }
    },
    async update({ id, input }) {
      const importPrice = input.import_price ?? input.importPrice;
      validateImportPrice(importPrice);
      try {
        await repository.update(id, {
          barcode: input.barcode || null,
          name: input.item_name || input.name || null,
          imageUrl: input.image_url ?? null,
          price: input.price == null ? null : Number(input.price),
          importPrice: importPrice == null ? null : Number(importPrice),
          unit: input.unit || null,
          stock:
            input.stock == null && input.stockQuantity == null
              ? null
              : Number(input.stock ?? input.stockQuantity),
          categoryId:
            input.category_id == null && input.categoryId == null
              ? null
              : Number(input.category_id ?? input.categoryId),
          status: input.status || null,
        });
        const row = await repository.findByKey(id);
        if (!row)
          throw new ApplicationError(
            "not_found",
            "Không tìm thấy hàng trong kho",
          );
        return {
          success: true,
          message: "Đã cập nhật hàng trong kho",
          data: toInventoryItem(row),
        };
      } catch (error) {
        if (error.code === "ER_DUP_ENTRY")
          throw new ApplicationError("conflict", "Lỗi cập nhật hàng trong kho");
        throw error;
      }
    },
  };
}

module.exports = { createInventoryItemService, toInventoryItem };
