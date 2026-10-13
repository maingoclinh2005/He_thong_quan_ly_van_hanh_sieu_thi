const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const source = (name) =>
  fs.readFileSync(path.join(__dirname, "../src", name), "utf8");

test("order layers cannot regress into HTTP-aware services or SQL in routes/controllers", () => {
  for (const file of [
    "routes/order.routes.js",
    "routes/myOrder.routes.js",
    "controllers/order.controller.js",
  ]) {
    const text = source(file);
    assert.doesNotMatch(
      text,
      /config\/db|\.execute\(|\.query\(|beginTransaction|\bSELECT\b|\bINSERT INTO\b/,
    );
  }
  for (const file of [
    "services/order.service.js",
    ...fs
      .readdirSync(path.join(__dirname, "../src/services/order"))
      .map((name) => `services/order/${name}`),
  ]) {
    assert.doesNotMatch(
      source(file),
      /require\(['"]express|\breq\.|\bres\.|config\/db|\.execute\(|\bSELECT\b|\bINSERT INTO\b|\bUPDATE\s+\w+\s+SET\b/,
    );
  }
  assert.doesNotMatch(
    source("repositories/order.repository.js"),
    /services\/|controllers\/|\breq\.|\bres\./,
  );
  assert.ok(source("routes/order.routes.js").split("\n").length < 100);
});
