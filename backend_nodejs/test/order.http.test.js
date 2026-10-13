const { test } = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const jwt = require("jsonwebtoken");
const { once } = require("node:events");
const { createHash } = require("node:crypto");
const {
  createOrderController,
} = require("../src/controllers/order.controller");
const { ApplicationError } = require("../src/errors/application-error");
const {
  configureSecurity,
  securityErrorHandler,
} = require("../src/middlewares/security");

process.env.JWT_SECRET = "order-http-test-only-secret";
const roles = { 1: "customer", 2: "employee", 3: "admin" };
require.cache[require.resolve("../src/config/db")] = {
  exports: {
    execute: async (_sql, [id]) => [
      [
        ...(roles[id]
          ? [
              {
                user_id: id,
                role_name: roles[id],
                password: "test",
                credential_hash: createHash("sha256")
                  .update("test")
                  .digest("hex"),
              },
            ]
          : []),
      ],
    ],
  },
};
const calls = [];
let failure;
const actions = [
  "list",
  "online",
  "pending",
  "confirm",
  "reject",
  "received",
  "checkout",
  "history",
  "statusByCode",
  "paymentStatus",
  "get",
  "updateStatus",
  "create",
  "myOrders",
];
const controller = createOrderController(
  Object.fromEntries(
    actions.map((action) => [
      action,
      async (input) => {
        calls.push({ action, input });
        if (failure) throw failure;
        return { success: true, data: { action } };
      },
    ]),
  ),
);
require.cache[require.resolve("../src/composition/order")] = {
  exports: controller,
};
const routes = require("../src/routes/order.routes");
const mine = require("../src/routes/myOrder.routes");

test("all existing paths, aliases, role guards and input adapters are retained", async (t) => {
  const app = express();
  configureSecurity(app, { env: {}, auditSink: () => {} });
  app.use("/api/orders", routes);
  app.use("/orders", routes);
  app.use("/my-orders", mine);
  app.use(securityErrorHandler);
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(
    () =>
      new Promise((resolve) => {
        server.close(resolve);
        server.closeAllConnections();
      }),
  );
  const base = `http://127.0.0.1:${server.address().port}`;
  async function request(method, path, id, body) {
    return fetch(base + path, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(id
          ? {
              Authorization:
                "Bearer " +
                jwt.sign(
                  { user_id: id, purpose: "access", sid: "test-session" },
                  process.env.JWT_SECRET,
                ),
            }
          : {}),
      },
      ...(method === "GET" ? {} : { body: JSON.stringify(body || {}) }),
    });
  }
  const endpoints = [
    ["GET", "/", "list", "staff"],
    ["GET", "/online", "online", "staff"],
    ["GET", "/pending", "pending", "staff"],
    ["PUT", "/9/confirm", "confirm", "staff"],
    ["PUT", "/9/reject", "reject", "staff"],
    ["PUT", "/9/received", "received", "any"],
    ["POST", "/checkout", "checkout", "customer"],
    ["GET", "/history", "history", "any"],
    ["GET", "/history/1", "history", "any"],
    ["GET", "/status/DH9", "statusByCode", "any"],
    ["GET", "/9/payment-status", "paymentStatus", "any"],
    ["GET", "/9", "get", "any"],
    ["PATCH", "/9/status", "updateStatus", "staff"],
    ["POST", "/", "create", "staff"],
  ];
  for (const prefix of ["/api/orders", "/orders"]) {
    for (const [method, path, action, role] of endpoints) {
      assert.equal(
        (await request(method, prefix + path)).status,
        401,
        `${method} ${path} anonymous`,
      );
      for (const id of [1, 2, 3]) {
        const allowed =
          role === "any" || (role === "staff" ? id !== 1 : id === 1);
        const previousCalls = calls.length;
        const response = await request(method, prefix + path, id, {
          employee_id: 99,
          reason: "test",
          status: "completed",
        });
        assert.equal(
          response.status,
          allowed ? (["checkout", "create"].includes(action) ? 201 : 200) : 403,
          `${prefix}${path} ${roles[id]}`,
        );
        if (allowed) {
          assert.equal((await response.json()).data.action, action);
          assert.equal(calls.at(-1).action, action);
          if (calls.at(-1).input.actor)
            assert.equal(calls.at(-1).input.actor.user_id, id);
        } else assert.equal(calls.length, previousCalls);
      }
    }
  }
  assert.equal((await request("GET", "/my-orders")).status, 401);
  assert.equal((await request("GET", "/my-orders", 1)).status, 200);
  assert.equal(calls.at(-1).action, "myOrders");
  for (const [kind, status] of Object.entries({
    invalid: 400,
    unauthorized: 401,
    forbidden: 403,
    not_found: 404,
    conflict: 409,
  })) {
    failure = new ApplicationError(kind, "Thông báo nghiệp vụ");
    const response = await request("GET", "/orders/9", 1);
    assert.equal(response.status, status);
    assert.equal((await response.json()).message, "Thông báo nghiệp vụ");
  }
  failure = new Error("SQL PRIVATE_INTERNAL");
  const response = await request("GET", "/orders/9", 1);
  assert.equal(response.status, 500);
  assert.ok(!(await response.text()).includes("PRIVATE_INTERNAL"));
});
