const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createOrderService } = require("../src/services/order.service");
const policy = require("../src/services/order/order-policy");
const { ApplicationError } = require("../src/errors/application-error");

const customer = { user_id: 1, role_name: "customer" };
const employee = { user_id: 2, role_name: "employee" };
function fixture(overrides = {}, loyaltyOverrides = {}) {
  const calls = [];
  let saved = {
    order_id: 9,
    customer_id: 1,
    status: "pending",
    order_type: "delivery",
    final_amount: "100000",
    payment_status: "pending",
  };
  const connection = { transaction: "same-connection" };
  const impl = {
    findById: async () => saved,
    findItems: async () => [
      {
        product_id: 3,
        product_name: "Táo",
        price: "50000",
        quantity: 2,
        subtotal: "100000",
      },
    ],
    listAll: async () => [saved],
    listOnline: async () => [saved],
    historyIds: async () => [{ order_id: 9 }],
    listForCustomer: async () => [saved],
    findCustomerItems: async () => [],
    lockOrder: async () => saved,
    updateStatus: async (id, change) => {
      saved = { ...saved, status: change.status };
      return 1;
    },
    findIdByCode: async () => 9,
    paymentAccess: async () => ({
      customer_id: 1,
      employee_id: 2,
      role_name: "employee",
    }),
    latestPayment: async () => ({}),
    lockCart: async () => ({ cart_id: 5 }),
    lockCartItems: async () => [
      {
        product_id: 3,
        quantity: 2,
        price: 50000,
        stock: 5,
        product_name: "Táo",
      },
    ],
    lockVoucher: async () => ({
      voucher_id: 4,
      code: "SALE",
      status: "active",
      discount_type: "percent",
      discount_value: 10,
      used_count: 0,
      usage_limit: 2,
    }),
    consumeVoucher: async () => {},
    activeShiftId: async () => 7,
    lockProduct: async () => ({
      product_id: 3,
      product_name: "Táo",
      price: 50000,
      stock: 5,
    }),
    insertOrder: async (values) => {
      saved = { ...values, order_id: 9 };
      return 9;
    },
    setTransferContent: async () => {},
    insertItemsAndReduceStock: async () => {},
    insertPayment: async () => {},
    clearCart: async () => {},
    ...overrides,
  };
  const repository = Object.fromEntries(
    Object.entries(impl).map(([name, fn]) => [
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
      const result = await work(repository, connection);
      calls.push(["commit"]);
      return result;
    } catch (error) {
      calls.push(["rollback"]);
      throw error;
    }
  };
  const loyalty = {
    normalizePhone: (value) => String(value || "").replace(/\D/g, ""),
    ensureCustomerByPhone: async (tx) => {
      assert.equal(tx, connection);
      return { user_id: 1, points: 200 };
    },
    validateRedeem: () => ({ pointsUsed: 100, pointsDiscount: 10000 }),
    finalizePaidOrderLoyalty: async (tx) => {
      assert.equal(tx, connection);
      calls.push(["loyalty"]);
    },
    ...loyaltyOverrides,
  };
  return { service: createOrderService({ repository, loyalty }), calls };
}
const rejectsKind = (promise, kind) =>
  assert.rejects(
    promise,
    (error) => error instanceof ApplicationError && error.kind === kind,
  );

test("policy preserves status aliases, voucher caps and numeric response mapping", () => {
  for (const [from, to] of [
    ["waiting_confirm", "pending"],
    ["preparing", "shipping"],
    ["Hoàn thành", "completed"],
    ["cancelled", "rejected"],
  ])
    assert.equal(policy.normalizeOrderStatus(from), to);
  assert.equal(policy.normalizeOrderStatus(null, "online"), "pending");
  assert.equal(policy.normalizeOrderStatus(null, "offline"), "completed");
  assert.equal(
    policy.calculateVoucherDiscount(
      { discount_type: "fixed", discount_value: 200 },
      100,
    ),
    100,
  );
  assert.equal(
    policy.calculateVoucherDiscount(
      { discount_type: "percent", discount_value: 50, max_discount: 20 },
      100,
    ),
    20,
  );
  const row = policy.normalizeOrder({
    order_id: 9,
    final_amount: "100",
    status: "pending",
    points_used: "20",
  });
  assert.equal(row.id, "9");
  assert.equal(row.totalAmount, 100);
  assert.equal(row.pointsUsed, 20);
});

test("customer cannot read another order or customer history; staff retains access", async () => {
  const { service, calls } = fixture();
  await rejectsKind(
    service.get({ id: 9, actor: { user_id: 7, role_name: "customer" } }),
    "forbidden",
  );
  await rejectsKind(
    service.history({ customerId: 7, actor: customer }),
    "forbidden",
  );
  assert.equal((await service.get({ id: 9, actor: employee })).data.id, "9");
  await service.history({ actor: customer });
  assert.deepEqual(
    calls.find((call) => call[0] === "historyIds"),
    ["historyIds", 1],
  );
  await rejectsKind(
    fixture({ findById: async () => null }).service.get({
      id: 404,
      actor: customer,
    }),
    "not_found",
  );
});

test("read endpoints preserve shapes, status-code normalization and narrow payment visibility", async () => {
  const { service, calls } = fixture();
  assert.equal((await service.list()).data[0].totalAmount, 100000);
  assert.equal((await service.online()).data.length, 1);
  assert.equal((await service.pending()).data[0].items[0].productId, "3");
  const status = (
    await service.statusByCode({ code: " dh-9 ", actor: customer })
  ).data;
  assert.equal(status.orderCode, "DH9");
  assert.equal(status.isPending, true);
  assert.deepEqual(
    calls.find((call) => call[0] === "findIdByCode"),
    ["findIdByCode", "DH9", 9],
  );
  assert.equal(
    (await service.paymentStatus({ id: "9", actor: employee })).data.orderId,
    9,
  );
  await rejectsKind(
    service.paymentStatus({
      id: 9,
      actor: { user_id: 8, role_name: "employee" },
    }),
    "forbidden",
  );
  await rejectsKind(
    service.statusByCode({ code: "", actor: customer }),
    "invalid",
  );
  assert.equal(
    (await service.myOrders({ actor: customer })).data[0].payment_status,
    "pending",
  );
  await rejectsKind(service.myOrders({ actor: null }), "unauthorized");
});

test("confirm/reject/received transitions run under transaction and read only after commit", async () => {
  const { service, calls } = fixture();
  assert.equal(
    (await service.confirm({ id: 9, actor: employee })).data.status,
    "shipping",
  );
  assert.ok(
    calls.findIndex((c) => c[0] === "commit") <
      calls.findIndex((c) => c[0] === "findById"),
  );
  assert.equal(
    (await service.received({ id: 9, actor: customer })).data.status,
    "completed",
  );
  const rejected = fixture();
  await rejected.service.reject({
    id: 9,
    actor: employee,
    reason: "  Hết hàng  ",
  });
  assert.equal(
    rejected.calls.find((c) => c[0] === "updateStatus")[2].reason,
    "Hết hàng",
  );
  const pickup = fixture({
    lockOrder: async () => ({ status: "pending", order_type: "store_pickup" }),
  });
  await pickup.service.confirm({ id: 9, actor: employee });
  assert.equal(
    pickup.calls.find((c) => c[0] === "updateStatus")[2].status,
    "completed",
  );
});

test("invalid transitions rollback without update; repeated confirmation is rejected", async () => {
  const { service, calls } = fixture();
  await service.confirm({ id: 9, actor: employee });
  await rejectsKind(service.confirm({ id: 9, actor: employee }), "conflict");
  assert.equal(calls.filter((c) => c[0] === "updateStatus").length, 1);
  assert.equal(calls.at(-1)[0], "rollback");
  const foreign = fixture({
    lockOrder: async () => ({
      customer_id: 7,
      status: "shipping",
      order_type: "delivery",
    }),
  });
  await rejectsKind(
    foreign.service.received({ id: 9, actor: customer }),
    "forbidden",
  );
  assert.ok(!foreign.calls.some((c) => c[0] === "updateStatus"));
  await rejectsKind(
    fixture({ lockOrder: async () => null }).service.confirm({
      id: 9,
      actor: employee,
    }),
    "not_found",
  );
  await rejectsKind(
    service.updateStatus({ id: 9, status: "bad", actor: employee }),
    "invalid",
  );
  await rejectsKind(
    fixture({ updateStatus: async () => 0 }).service.updateStatus({
      id: 9,
      status: "completed",
      actor: employee,
    }),
    "not_found",
  );
});

test("checkout calculates from server cart, consumes voucher, stock/payment/cart share transaction", async () => {
  const { service, calls } = fixture();
  const result = await service.checkout({
    input: {
      deliveryMethod: "delivery",
      shippingAddress: "Hà Nội",
      paymentMethod: "vnpay",
      voucherCode: "sale",
      total_amount: 1,
    },
    actor: customer,
  });
  assert.equal(result.data.finalAmount, 90000);
  assert.equal(result.data.discountAmount, 10000);
  assert.equal(result.data.requiresVnpayPayment, true);
  assert.equal(result.data.paymentStatus, "pending");
  const order = calls.find((c) => c[0] === "insertOrder")[1];
  assert.equal(order.total_amount, 100000);
  assert.equal(order.customer_id, 1);
  assert.equal(order.order_type, "delivery");
  assert.deepEqual(
    calls.find((c) => c[0] === "consumeVoucher"),
    ["consumeVoucher", 4, 1],
  );
  const sequence = calls.map((c) => c[0]);
  assert.ok(sequence.indexOf("clearCart") < sequence.indexOf("commit"));
  assert.ok(sequence.indexOf("commit") < sequence.indexOf("findById"));
});

test("checkout validation and failures do not leave partial writes", async () => {
  for (const input of [
    { delivery_method: "invalid" },
    { delivery_method: "delivery" },
    { payment_method: "bad" },
  ]) {
    const { service, calls } = fixture();
    await rejectsKind(service.checkout({ input, actor: customer }), "invalid");
    assert.equal(calls.length, 0);
  }
  for (const overrides of [
    { lockCart: async () => null },
    { lockCartItems: async () => [] },
    {
      lockCartItems: async () => [
        { product_id: 3, quantity: 2, stock: 0, price: 50000 },
      ],
    },
    {
      insertPayment: async () => {
        throw new Error("payment write failed");
      },
    },
  ]) {
    const { service, calls } = fixture(overrides);
    await assert.rejects(service.checkout({ input: {}, actor: customer }));
    assert.equal(calls.at(-1)[0], "rollback");
    assert.ok(!calls.some((c) => c[0] === "commit"));
    assert.ok(!calls.some((c) => c[0] === "clearCart"));
  }
});

test("checkout voucher expiry/usage/minimum and existing ewallet response remain unchanged", async () => {
  for (const voucher of [
    null,
    { expiry_date: "2000-01-01" },
    { usage_limit: 1, used_count: 1 },
    { min_order_amount: 200000 },
  ]) {
    const { service, calls } = fixture({ lockVoucher: async () => voucher });
    await assert.rejects(
      service.checkout({ input: { voucher_id: 4 }, actor: customer }),
    );
    assert.ok(!calls.some((c) => c[0] === "insertOrder"));
  }
  const result = await fixture().service.checkout({
    input: { payment_method: "ewallet" },
    actor: customer,
  });
  assert.equal(result.data.fakeQrContent, "FAKE_QR_ORDER_9_100000");
  assert.equal(result.data.paymentStatus, "paid");
});

test("staff creation uses authenticated employee, handles bank content and preserves payment semantics", async () => {
  const { service, calls } = fixture();
  const result = await service.create({
    actor: employee,
    input: {
      employee_id: 99,
      items: [{ productId: 3, quantity: 2 }],
      payment_method: "bank_transfer",
      payment_status: "unpaid",
      discount_amount: 10000,
    },
  });
  assert.equal(result.data.totalAmount, 90000);
  const order = calls.find((c) => c[0] === "insertOrder")[1];
  assert.equal(order.employee_id, 2);
  assert.equal(order.shift_id, 7);
  assert.equal(order.payment_status, "pending");
  assert.deepEqual(
    calls.find((c) => c[0] === "setTransferContent"),
    ["setTransferContent", 9, "DH9"],
  );
  assert.ok(!calls.some((c) => c[0] === "loyalty"));
});

test("loyalty redemption and award use the same transaction; failures prevent commit", async () => {
  const input = {
    items: [{ product_id: 3, quantity: 2 }],
    customer_phone: "090 123 4567",
    use_points: true,
    points_to_use: 100,
  };
  const { service, calls } = fixture();
  const result = await service.create({ actor: employee, input });
  assert.equal(result.data.pointsUsed, 100);
  assert.equal(result.data.pointsDiscount, 10000);
  assert.equal(result.data.totalAmount, 90000);
  assert.ok(
    calls.findIndex((c) => c[0] === "loyalty") <
      calls.findIndex((c) => c[0] === "commit"),
  );
  const failure = fixture(
    {},
    {
      finalizePaidOrderLoyalty: async () => {
        throw new Error("loyalty failure");
      },
    },
  );
  await assert.rejects(
    failure.service.create({ input, actor: employee }),
    /loyalty failure/,
  );
  assert.equal(failure.calls.at(-1)[0], "rollback");
  await rejectsKind(
    service.create({ input: { items: [] }, actor: employee }),
    "invalid",
  );
});
