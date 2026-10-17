const test = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const { createHash } = require("node:crypto");
const bcrypt = require("bcrypt");
const jwt = require("jsonwebtoken");
const express = require("express");

test("user create/profile/admin update and auth register only write password_hash", async (t) => {
  process.env.JWT_SECRET = "canonical-users-test-secret";
  const writes = [];
  const user = {
    user_id: 1,
    full_name: "Admin",
    role_name: "admin",
    status: "active",
    password_hash: await bcrypt.hash("secret123", 4),
  };
  const execute = async (sql, params = []) => {
    assert.doesNotMatch(sql, /information_schema|\bu\.password\b/);
    assert.equal((sql.match(/\?/g) || []).length, params.length, sql);
    if (sql.includes("JOIN auth_sessions"))
      return [
        [
          {
            ...user,
            credential_hash: createHash("sha256")
              .update(user.password_hash)
              .digest("hex"),
          },
        ],
      ];
    if (sql.startsWith("INSERT INTO users") || sql.startsWith("UPDATE users")) {
      writes.push({ sql, params });
      assert.match(sql, /password_hash/);
      assert.doesNotMatch(sql, /\bpassword\b/);
      assert.ok(
        await bcrypt.compare(
          "new-password",
          params.find(
            (value) => typeof value === "string" && value.startsWith("$2"),
          ),
        ),
      );
      return [{ insertId: 1, affectedRows: 1 }];
    }
    if (sql.includes("SELECT role_id")) return [[{ role_id: 1 }]];
    if (sql.includes("SELECT u.*")) return [[{ ...user }]];
    if (sql.includes("SELECT user_id")) return [[]];
    throw new Error("Unexpected SQL");
  };
  require.cache[require.resolve("../src/config/db")] = { exports: { execute } };
  const app = express();
  app.use(express.json());
  app.use("/users", require("../src/routes/user.routes"));
  app.use("/auth", require("../src/routes/auth.routes"));
  const server = app.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(
    () =>
      new Promise((resolve) => {
        server.close(resolve);
        server.closeAllConnections();
      }),
  );
  const token = jwt.sign(
    { user_id: 1, sid: "test", purpose: "access" },
    process.env.JWT_SECRET,
  );
  for (const [method, url, status] of [
    ["POST", "/users", 201],
    ["PUT", "/users/1/profile", 200],
    ["PUT", "/users/1", 200],
    ["POST", "/auth/register", 201],
  ]) {
    const response = await fetch(
      "http://127.0.0.1:" + server.address().port + url,
      {
        method,
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + token,
        },
        body: JSON.stringify({
          full_name: "Test",
          email: "test@example.test",
          phone: "0901234567",
          password: "new-password",
        }),
      },
    );
    assert.equal(response.status, status, await response.text());
  }
  assert.equal(writes.length, 4);
});
