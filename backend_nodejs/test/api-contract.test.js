const test = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const express = require("express");
const { apiContract, mapFields } = require("../src/middlewares/api-contract");

async function serve(t, app) {
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(
    () =>
      new Promise((resolve) => {
        server.close(resolve);
        server.closeAllConnections();
      }),
  );
  return "http://127.0.0.1:" + server.address().port;
}
const plain = (value) => JSON.parse(JSON.stringify(value));

test("wire serializer recursively emits snake_case, preserves dates/null and prefers canonical aliases", () => {
  assert.deepEqual(
    plain(
      mapFields({
        orderId: 1,
        order_id: 2,
        createdAt: new Date("2026-10-15T00:00:00Z"),
        items: [{ importPrice: null, stockQuantity: 0 }],
        paymentURL: "https://example.test",
      }),
    ),
    {
      order_id: 2,
      created_at: "2026-10-15T00:00:00.000Z",
      items: [{ import_price: null, stock_quantity: 0 }],
      payment_url: "https://example.test",
    },
  );
});

test("request adapter supports snake_case and deprecated camelCase but rejects ambiguous/unsafe fields", async (t) => {
  const app = express();
  app.use(express.json());
  app.use("/api", apiContract);
  app.post("/api/echo", (req, res) =>
    res.json({
      orderTotal: req.body.orderTotal,
      nestedItems: req.body.items,
      amountAfterVoucher: req.query.amountAfterVoucher,
    }),
  );
  const base = await serve(t, app);
  const post = (body) =>
    fetch(base + "/api/echo?amount_after_voucher=7", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  const canonical = await post({ order_total: 10, items: [{ product_id: 4 }] });
  assert.equal(canonical.status, 200);
  assert.equal(canonical.headers.get("deprecation"), null);
  assert.deepEqual(await canonical.json(), {
    order_total: 10,
    nested_items: [{ product_id: 4 }],
    amount_after_voucher: "7",
  });
  const old = await post({ orderTotal: 10 });
  assert.ok(old.headers.get("deprecation"));
  assert.equal((await old.json()).order_total, 10);
  for (const body of [
    { orderTotal: 10, order_total: 11 },
    { items: [{ productId: 1, product_id: 1 }] },
    JSON.parse('{"__proto__":{"polluted":true}}'),
    { constructor: {} },
  ])
    assert.equal((await post(body)).status, 400);
  assert.equal({}.polluted, undefined);
});

test("provider callback payloads/query/response keep exact casing, including trailing slash", async (t) => {
  const app = express();
  app.use(express.json());
  app.use("/api", apiContract);
  for (const prefix of ["/payments", "/webhook"]) {
    app.all("/api" + prefix + "/vnpay-ipn", (req, res) => {
      assert.equal(req.query.vnp_SecureHash, "ABC");
      assert.equal(req.query.vnp_secure_hash, undefined);
      assert.equal(req.body.transferAmount, 10);
      res.json({ RspCode: "00", Message: "OK" });
    });
  }
  const base = await serve(t, app);
  for (const prefix of ["payments", "webhook"]) {
    const response = await fetch(
      base + "/api/" + prefix + "/vnpay-ipn/?vnp_SecureHash=ABC",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ transferAmount: 10 }),
      },
    );
    assert.deepEqual(await response.json(), { RspCode: "00", Message: "OK" });
  }
});

test("actual app exposes canonical URLs, retires app aliases without DB work, keeps provider-only alias", async (t) => {
  Object.assign(process.env, {
    NODE_ENV: "test",
    REQUIRE_HTTPS: "false",
    TRUSTED_PROXIES: "",
    CORS_ORIGINS: "",
    JWT_SECRET: "contract-test-only",
    VNP_TMN_CODE: "test",
    VNP_HASH_SECRET: "test-only-secret",
    VNP_URL: "https://example.test/pay",
    VNP_RETURN_URL: "https://example.test/return",
    VNP_IPN_URL: "https://example.test/ipn",
  });
  let calls = 0;
  require.cache[require.resolve("../src/config/db")] = {
    exports: {
      execute: async () => {
        calls++;
        return [
          [
            {
              voucher_id: 1,
              code: "TEST",
              discount_type: "fixed",
              discount_value: 10,
              min_order_amount: 0,
              status: "active",
            },
          ],
        ];
      },
    },
  };
  const app = require("../src/server");
  const base = await serve(t, app);
  assert.equal((await fetch(base + "/api/health")).status, 200);
  for (const path of ["/api/carts", "/api/orders", "/api/my-orders"]) {
    assert.equal((await fetch(base + path)).status, 401, path);
  }
  for (const [path, replacement] of [
    ["/cart/add", "/api/carts/add"],
    ["/api/cart/update", "/api/carts/update"],
    ["/orders/checkout", "/api/orders/checkout"],
    ["/my-orders", "/api/my-orders/"],
    ["/api/webhook/vnpay/create", "/api/payments/vnpay/create"],
  ]) {
    const response = await fetch(base + path, { method: "POST" });
    assert.equal(response.status, 410, path);
    assert.equal((await response.json()).replacement, replacement);
  }
  const callback = await fetch(
    base + "/api/webhook/vnpay-ipn?vnp_SecureHash=invalid",
  );
  assert.ok(callback.headers.get("deprecation"));
  const body = await callback.json();
  assert.ok(Object.hasOwn(body, "RspCode"));
  assert.equal(Object.hasOwn(body, "rsp_code"), false);
  assert.equal(calls, 0);
  const voucher = await fetch(base + "/api/vouchers/validate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code: "TEST", order_total: 100, user_id: 1 }),
  });
  assert.equal(voucher.status, 200);
  const data = (await voucher.json()).voucher;
  assert.equal(data.discount_amount, 10);
  assert.equal(data.final_total, 90);
  assert.equal(data.discountAmount, undefined);
});
