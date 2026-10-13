const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createInventoryService } = require("../src/services/inventory.service");
const {
  createInventoryRepository,
} = require("../src/repositories/inventory.repository");
const { ApplicationError } = require("../src/errors/application-error");

function fixture(overrides = {}) {
  const calls = [];
  const row = {
    inventory_item_id: 7,
    barcode: "ABC",
    item_name: "Táo",
    price: "100",
    import_price: "50",
    category_id: "2",
    stock: 10,
    status: "active",
  };
  const methods = {
    list: async () => [row],
    logs: async () => [{ log_id: 1 }],
    latestCost: async () => ({ import_price: "40" }),
    create: async () => 7,
    update: async () => {},
    findById: async () => row,
    findByKey: async () => row,
    lockItem: async () => row,
    importStock: async () => {},
    adjustStock: async () => {},
    exportStock: async () => {},
    logImport: async () => {},
    logAdjustment: async () => {},
    logExport: async () => {},
    ...overrides,
  };
  const repository = Object.fromEntries(
    Object.entries(methods).map(([name, fn]) => [
      name,
      async (...args) => {
        calls.push([name, ...args]);
        return fn(...args);
      },
    ]),
  );
  repository.transaction = async (work) => {
    calls.push(["begin"]);
    try {
      const result = await work(repository);
      calls.push(["commit"]);
      return result;
    } catch (error) {
      calls.push(["rollback"]);
      throw error;
    }
  };
  return { service: createInventoryService({ repository }), calls };
}
const input = {
  inventory_item_id: "ABC",
  employee_id: 2,
  quantity: 3,
  importPrice: 50,
};
const fails = (promise, kind) =>
  assert.rejects(
    promise,
    (e) => e instanceof ApplicationError && e.kind === kind,
  );

test("inventory reads preserve aliases, numeric values, logs and missing costs", async () => {
  const { service } = fixture();
  const item = (await service.list()).data[0];
  assert.equal(item.id, "ABC");
  assert.equal(item.name, "Táo");
  assert.equal(item.price, 100);
  assert.equal(item.importPrice, 50);
  assert.equal(item.categoryId, 2);
  assert.equal(item.stockQuantity, 10);
  assert.equal(item.unit, "sp");
  assert.equal((await service.logs()).data[0].log_id, 1);
  assert.deepEqual(await service.cost({ key: "ABC" }), {
    success: true,
    data: { import_price: 40 },
  });
  for (const row of [null, { import_price: null }])
    assert.equal(
      (
        await fixture({ latestCost: async () => row }).service.cost({
          key: "ABC",
        })
      ).data.import_price,
      null,
    );
});

test("create/update map both naming conventions and preserve omitted-image behavior", async () => {
  const { service, calls } = fixture();
  await service.create({
    input: {
      barcode: "ABC",
      name: "Táo",
      price: "100",
      importPrice: "50",
      stockQuantity: 0,
      categoryId: 2,
    },
  });
  assert.deepEqual(calls[0], [
    "create",
    {
      barcode: "ABC",
      name: "Táo",
      price: 100,
      importPrice: 50,
      stock: 0,
      unit: "sp",
      categoryId: 2,
      imageUrl: null,
    },
  ]);
  await service.update({ id: "ABC", input: { stock: 0 } });
  const change = calls.find((c) => c[0] === "update")[2];
  assert.equal(change.stock, 0);
  assert.equal(change.imageUrl, null);
  assert.equal(change.price, null);
  await fails(
    fixture({ findByKey: async () => null }).service.update({
      id: 9,
      input: {},
    }),
    "not_found",
  );
});

test("invalid item inputs never write and duplicate-key errors retain 409 category", async () => {
  for (const value of [
    {},
    { barcode: "ABC", name: "Táo", price: 1 },
    { barcode: "ABC", name: "Táo", price: 1, categoryId: 2, importPrice: 0 },
  ]) {
    const { service, calls } = fixture();
    await fails(service.create({ input: value }), "invalid");
    assert.equal(calls.length, 0);
  }
  const duplicate = async () => {
    throw Object.assign(new Error("PRIVATE SQL"), { code: "ER_DUP_ENTRY" });
  };
  await fails(
    fixture({ create: duplicate }).service.create({
      input: { barcode: "ABC", name: "Táo", price: 1, categoryId: 2 },
    }),
    "conflict",
  );
  await fails(
    fixture({ update: duplicate }).service.update({ id: 7, input: {} }),
    "conflict",
  );
});

test("import locks first and atomically updates stock/cost and log", async () => {
  const { service, calls } = fixture();
  assert.deepEqual(await service.importStock({ input }), {
    success: true,
    message: "Đã nhập kho",
  });
  assert.deepEqual(
    calls.map((c) => c[0]),
    ["begin", "lockItem", "importStock", "logImport", "commit"],
  );
  assert.deepEqual(calls[2], ["importStock", 7, 3, 50]);
  assert.deepEqual(calls[3][1], {
    itemId: 7,
    employeeId: 2,
    quantity: 3,
    importPrice: 50,
    note: null,
  });
});

test("adjustment records signed difference, including zero actual stock", async () => {
  for (const actual of [0, 10, 15]) {
    const { service, calls } = fixture();
    const response = await service.adjust({
      input: { ...input, actual_quantity: actual },
    });
    assert.deepEqual(response.data, {
      beforeStock: 10,
      actualQuantity: actual,
      difference: actual - 10,
    });
    const log = calls.find((c) => c[0] === "logAdjustment")[1];
    assert.equal(log.quantity, actual - 10);
    assert.equal(log.note, `Kiểm kê: 10 -> ${actual}`);
    assert.equal(calls.at(-1)[0], "commit");
  }
});

test("export reduces inventory only, records negative quantity and optional product", async () => {
  const { service, calls } = fixture();
  await service.exportStock({ input: { ...input, product_id: 4 } });
  assert.deepEqual(
    calls.map((c) => c[0]),
    ["begin", "lockItem", "exportStock", "logExport", "commit"],
  );
  assert.deepEqual(calls[3][1], {
    itemId: 7,
    productId: 4,
    employeeId: 2,
    quantity: -3,
    note: "Đưa hàng lên kệ",
  });
});

test("validation before transaction; missing item, insufficient stock and log failures roll back", async () => {
  for (const [action, bad] of [
    ["importStock", { ...input, importPrice: 0 }],
    ["exportStock", { ...input, quantity: 0 }],
    ["adjust", { ...input, actual_quantity: -1 }],
    ["importStock", { ...input, employee_id: null }],
  ]) {
    const { service, calls } = fixture();
    await fails(service[action]({ input: bad }), "invalid");
    assert.equal(calls.length, 0);
  }
  for (const action of ["importStock", "adjust", "exportStock"]) {
    const { service, calls } = fixture({ lockItem: async () => null });
    await assert.rejects(
      service[action]({ input: { ...input, actual_quantity: 5 } }),
    );
    assert.deepEqual(
      calls.map((c) => c[0]),
      ["begin", "lockItem", "rollback"],
    );
  }
  const stock = fixture();
  await assert.rejects(
    stock.service.exportStock({ input: { ...input, quantity: 11 } }),
    /Không đủ tồn kho/,
  );
  assert.deepEqual(
    stock.calls.map((c) => c[0]),
    ["begin", "lockItem", "rollback"],
  );
  for (const [action, log] of [
    ["importStock", "logImport"],
    ["adjust", "logAdjustment"],
    ["exportStock", "logExport"],
  ]) {
    const { service, calls } = fixture({
      [log]: async () => {
        throw new Error("log failed");
      },
    });
    await assert.rejects(
      service[action]({ input: { ...input, actual_quantity: 5 } }),
      /log failed/,
    );
    assert.equal(calls.at(-1)[0], "rollback");
    assert.ok(!calls.some((c) => c[0] === "commit"));
  }
});

test("repository uses bound parameters and the same SQL connection throughout movements", async () => {
  const calls = [];
  const connection = {
    execute: async (sql, params) => {
      calls.push({ sql, params });
      return [[]];
    },
    beginTransaction: async () => calls.push("begin"),
    commit: async () => calls.push("commit"),
    rollback: async () => calls.push("rollback"),
    release: () => calls.push("release"),
  };
  const pool = {
    getConnection: async () => connection,
    execute: async () => {
      throw new Error("Global pool used");
    },
  };
  const repository = createInventoryRepository(pool);
  const hostile = "x' OR 1=1 --";
  await repository.transaction(async (tx) => {
    await tx.lockItem(hostile);
    await tx.importStock(7, 3, 50);
    await tx.logImport({
      itemId: 7,
      employeeId: 2,
      quantity: 3,
      importPrice: 50,
      note: hostile,
    });
  });
  assert.equal(calls[0], "begin");
  assert.equal(calls.at(-2), "commit");
  assert.equal(calls.at(-1), "release");
  assert.match(calls[1].sql, /FOR UPDATE/);
  assert.deepEqual(calls[1].params, [hostile, hostile]);
  assert.ok(!calls[3].sql.includes(hostile));
  assert.equal(calls[3].params.at(-1), hostile);
});
