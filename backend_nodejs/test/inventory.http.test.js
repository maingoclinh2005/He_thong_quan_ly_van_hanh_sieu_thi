const { test } = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const jwt = require("jsonwebtoken");
const { createHash } = require("node:crypto");
const { once } = require("node:events");
const fs = require("node:fs");
const path = require("node:path");
const {
  createInventoryController,
} = require("../src/controllers/inventory.controller");
const { ApplicationError } = require("../src/errors/application-error");
const {
  configureSecurity,
  securityErrorHandler,
} = require("../src/middlewares/security");
process.env.JWT_SECRET = "inventory-http-tests-only";
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
                password_hash: "test",
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
let failure;
const calls = [];
const actions = [
  "list",
  "create",
  "update",
  "logs",
  "cost",
  "importStock",
  "adjust",
  "exportStock",
];
require.cache[require.resolve("../src/composition/inventory")] = {
  exports: createInventoryController(
    Object.fromEntries(
      actions.map((action) => [
        action,
        async (input) => {
          calls.push({ action, input });
          if (failure) throw failure;
          return { success: true, data: action };
        },
      ]),
    ),
  ),
};
const router = require("../src/routes/inventory.routes");

test("all inventory routes preserve role guards, adapters, status and masked errors", async (t) => {
  const app = express();
  configureSecurity(app, { env: {}, auditSink: () => {} });
  app.use("/api/inventory", router);
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
  const send = (method, url, id) =>
    fetch(`http://127.0.0.1:${server.address().port}/api/inventory${url}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(id
          ? {
              Authorization:
                "Bearer " +
                jwt.sign(
                  { user_id: id, sid: "test", purpose: "access" },
                  process.env.JWT_SECRET,
                ),
            }
          : { "x-user-id": "3" }),
      },
      ...(method === "GET"
        ? {}
        : { body: JSON.stringify({ quantity: 3, employee_id: 2 }) }),
    });
  for (const [method, url, action] of [
    ["GET", "/items", "list"],
    ["POST", "/items", "create"],
    ["PUT", "/items/ABC", "update"],
    ["GET", "/logs", "logs"],
    ["GET", "/cost/ABC", "cost"],
    ["POST", "/import", "importStock"],
    ["POST", "/adjust", "adjust"],
    ["POST", "/export", "exportStock"],
  ]) {
    for (const id of [null, 1, 2, 3]) {
      const previous = calls.length;
      const response = await send(method, url, id);
      assert.equal(
        response.status,
        !id ? 401 : id === 1 ? 403 : action === "create" ? 201 : 200,
      );
      if (id === 2 || id === 3) {
        assert.equal((await response.json()).data, action);
        if (action === "update") assert.equal(calls.at(-1).input.id, "ABC");
        if (action === "cost") assert.equal(calls.at(-1).input.key, "ABC");
        if (method !== "GET") assert.equal(calls.at(-1).input.input.employee_id, id);
      } else assert.equal(calls.length, previous);
    }
  }
  for (const [kind, status] of [
    ["invalid", 400],
    ["not_found", 404],
    ["conflict", 409],
  ]) {
    failure = new ApplicationError(kind, "Thông báo");
    assert.equal((await send("POST", "/items", 2)).status, status);
  }
  failure = new Error("PRIVATE_SQL_PASSWORD");
  const response = await send("GET", "/items", 2);
  assert.equal(response.status, 500);
  assert.ok(!(await response.text()).includes("PRIVATE_SQL_PASSWORD"));
});

test("inventory architecture keeps SQL out of controllers and HTTP out of services", () => {
  const source = (file) =>
    fs.readFileSync(path.join(__dirname, "../src", file), "utf8");
  for (const file of [
    "routes/inventory.routes.js",
    "controllers/inventory.controller.js",
    "services/inventory.service.js",
    "services/inventory/item.service.js",
    "services/inventory/movement.service.js",
  ]) {
    assert.doesNotMatch(
      source(file),
      /config\/db|\.execute\(|\bSELECT\b|\bINSERT INTO\b/,
    );
    if (file.startsWith("services/"))
      assert.doesNotMatch(source(file), /\breq\.|\bres\.|require\(['"]express/);
  }
  assert.doesNotMatch(
    source("repositories/inventory.repository.js"),
    /services\/|controllers\/|\breq\.|\bres\./,
  );
});
