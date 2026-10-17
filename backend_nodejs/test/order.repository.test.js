const { test } = require("node:test");
const assert = require("node:assert/strict");
const { withTransaction } = require("../src/repositories/transaction");
const {
  createOrderRepository,
} = require("../src/repositories/order.repository");

test("transaction releases once on success, work failure, BEGIN failure and COMMIT failure", async () => {
  for (const failure of [null, "work", "begin", "commit", "rollback"]) {
    const calls = [];
    const connection = {
      beginTransaction: async () => {
        calls.push("begin");
        if (failure === "begin") throw new Error("begin");
      },
      commit: async () => {
        calls.push("commit");
        if (failure === "commit") throw new Error("commit");
      },
      rollback: async () => {
        calls.push("rollback");
        if (failure === "rollback") throw new Error("secondary");
      },
      release: () => calls.push("release"),
    };
    const operation = withTransaction(
      { getConnection: async () => connection },
      async (tx) => {
        assert.equal(tx, connection);
        calls.push("work");
        if (failure === "work" || failure === "rollback")
          throw new Error("work");
        return 9;
      },
    );
    if (failure)
      await assert.rejects(
        operation,
        new RegExp(failure === "rollback" ? "work" : failure),
      );
    else assert.equal(await operation, 9);
    assert.equal(calls.filter((c) => c === "release").length, 1);
    assert.equal(calls.at(-1), "release");
    assert.equal(
      calls.includes("rollback"),
      Boolean(failure && failure !== "begin"),
    );
  }
});

function mockPool(fields = []) {
  const calls = [];
  const execute = async (sql, params) => {
    calls.push({ sql, params });
    if (sql.includes("information_schema"))
      return [fields.map((COLUMN_NAME) => ({ COLUMN_NAME }))];
    return [{ affectedRows: 1, insertId: 9 }];
  };
  return { calls, execute };
}

test("dynamic identifiers are internal allowlists and values remain bound parameters", async () => {
  const pool = mockPool(["order_status", "transfer_content"]);
  const repository = createOrderRepository(pool);
  const malicious = "x'); DROP TABLE orders; --";
  assert.equal(
    await repository.insertOrder({
      customer_id: 1,
      note: malicious,
      status: "pending",
      shift_id: 7,
    }),
    9,
  );
  const insert = pool.calls.find((c) => c.sql.startsWith("INSERT"));
  assert.ok(!insert.sql.includes(malicious));
  assert.ok(insert.params.includes(malicious));
  assert.ok(insert.sql.includes("shift_id"));
  await assert.rejects(
    repository.insertOrder({ bad_column: 1 }),
    /Unsupported order column/,
  );
  await assert.rejects(
    repository.insertPayment({ bad_column: 1 }),
    /Unsupported payment column/,
  );
});

test("canonical status updates write required columns without schema probes", async () => {
  const pool = mockPool(["note", "employee_id"]);
  await createOrderRepository(pool).updateStatus(9, {
    status: "rejected",
    reason: "Hết hàng",
    confirmation: true,
    employeeId: 2,
    assignEmployee: true,
  });
  const update = pool.calls.find((c) => c.sql.startsWith("UPDATE"));
  assert.match(update.sql, /rejection_reason = \?/);
  assert.doesNotMatch(update.sql, /order_status|information_schema/);
  assert.deepEqual(update.params, ["rejected", 2, 2, "Hết hàng", 9]);
  const modern = mockPool(["order_status", "confirmed_by", "confirmed_at"]);
  await createOrderRepository(modern).updateStatus(9, {
    status: "confirmed",
    confirmation: true,
    employeeId: 2,
    onlyMissingConfirmation: true,
  });
  assert.match(
    modern.calls.at(-1).sql,
    /confirmed_by = COALESCE\(confirmed_by, \?\)/,
  );
});

test("repository transaction binds writes to acquired connection", async () => {
  const tx = mockPool(["order_status"]);
  const connection = {
    ...tx,
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
  };
  const pool = {
    getConnection: async () => connection,
    execute: async () => {
      throw new Error("Global pool used inside transaction");
    },
  };
  await createOrderRepository(pool).transaction(async (repository, raw) => {
    assert.equal(raw, connection);
    await repository.insertOrder({ status: "pending" });
    await repository.insertItemsAndReduceStock(9, [
      { productId: 3, quantity: 1, price: 100, subtotal: 100 },
    ]);
    await repository.insertPayment({
      order_id: 9,
      method: "cash",
      amount: 100,
      status: "pending",
    });
    await repository.clearCart(5);
  });
  assert.equal(tx.calls.length, 5);
});

test("query errors propagate without acquiring a leaked connection", async () => {
  let acquired = 0;
  const pool = {
    getConnection: async () => {
      acquired++;
    },
    execute: async () => {
      throw new Error("query unavailable");
    },
  };
  await assert.rejects(
    createOrderRepository(pool).listOnline(),
    /query unavailable/,
  );
  assert.equal(acquired, 0);
});
