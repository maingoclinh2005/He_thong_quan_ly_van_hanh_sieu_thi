const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const bcrypt = require("bcrypt");
const { loadMigrations, plan, run } = require("../scripts/migration-runner");
const baseline = require("../database/versioned/0001_baseline");
const canonical = require("../database/versioned/0002_canonical_columns");
const { assertSchemaVersion } = require("../src/schema-version");

function fakeDatabase() {
  const db = {
    ledger: [],
    events: [],
    lock: null,
    calls: [],
    users: [],
    orders: [],
    columns: new Map(
      Object.entries(baseline.required).map(([table, names]) => [
        table,
        new Set(names),
      ]),
    ),
    async query(sql) {
      this.calls.push(sql);
      const match = sql.match(/ALTER TABLE (\w+) (ADD|DROP) COLUMN (\w+)/);
      if (match) {
        const [, table, action, column] = match;
        if (action === "ADD") this.columns.get(table).add(column);
        else {
          this.columns.get(table).delete(column);
          for (const row of this[table]) delete row[column];
        }
      }
      return [{}];
    },
    async execute(sql, params = []) {
      this.calls.push(sql);
      if (sql.startsWith("INSERT INTO schema_migration_lock")) {
        if (this.lock)
          throw Object.assign(new Error("locked"), { code: "ER_DUP_ENTRY" });
        this.lock = params[0];
        return [{}];
      }
      if (sql.startsWith("DELETE FROM schema_migration_lock")) {
        if (this.lock === params[0]) this.lock = null;
        return [{}];
      }
      if (sql.startsWith("SELECT") && sql.includes("FROM schema_migrations"))
        return [this.ledger.map((row) => ({ ...row }))];
      if (sql.startsWith("INSERT INTO schema_migrations")) {
        const [version, name, checksum, direction] = params;
        let row = this.ledger.find((row) => row.version === version);
        if (!row) {
          row = { version, name, checksum };
          this.ledger.push(row);
        }
        Object.assign(row, { state: "running", direction });
        return [{}];
      }
      if (sql.startsWith("UPDATE schema_migrations")) {
        const failed = sql.includes("'failed'");
        const row = this.ledger.find(
          (row) => row.version === params[failed ? 0 : 1],
        );
        row.state = failed ? "failed" : params[0];
        return [{}];
      }
      if (sql.startsWith("INSERT INTO schema_migration_events")) {
        this.events.push(params);
        return [{}];
      }
      if (sql.includes("information_schema")) {
        const [table, column] = params;
        return [
          [...(this.columns.get(table) || [])]
            .filter((name) => !column || column === name)
            .map((COLUMN_NAME) => ({ COLUMN_NAME })),
        ];
      }
      if (sql.startsWith("SELECT * FROM users"))
        return [
          this.users
            .filter((row) => row.user_id > params[0])
            .slice(0, 500)
            .map((row) => ({ ...row })),
        ];
      if (sql.startsWith("SELECT * FROM orders"))
        return [
          this.orders
            .filter((row) => row.order_id > params[0])
            .slice(0, 500)
            .map((row) => ({ ...row })),
        ];
      if (sql.startsWith("UPDATE users SET password_hash"))
        this.users.find((row) => row.user_id === params[1]).password_hash =
          params[0];
      else if (sql === "UPDATE users SET password = password_hash")
        this.users.forEach((row) => (row.password = row.password_hash));
      else if (sql === "UPDATE orders SET order_status = status")
        this.orders.forEach((row) => (row.order_status = row.status));
      else if (sql.startsWith("UPDATE orders SET status"))
        this.orders.find((row) => row.order_id === params[1]).status =
          params[0];
      else throw new Error("Unmocked SQL: " + sql);
      return [{}];
    },
  };
  db.columns.get("users").add("password");
  db.columns.get("orders").add("order_status");
  return db;
}
const options = { actor: "unit-test", log: () => {} };

test("version catalog, checksum drift, unknown versions, gaps and dirty direction fail closed", async () => {
  const migrations = await loadMigrations();
  assert.deepEqual(
    migrations.map((m) => m.version),
    ["0001", "0002", "0003", "0004"],
  );
  assert.equal(plan(migrations, [], "up").length, 4);
  const row = { ...migrations[0], state: "applied", direction: "up" };
  assert.throws(
    () => plan(migrations, [{ ...row, checksum: "changed" }], "up"),
    /drift/,
  );
  assert.throws(
    () => plan(migrations, [{ ...row, version: "9999" }], "up"),
    /Unknown/,
  );
  assert.throws(
    () => plan(migrations, [{ ...migrations[1], state: "applied" }], "up"),
    /gap/,
  );
  assert.throws(
    () => plan(migrations, [{ ...row, state: "failed" }], "up"),
    /Incomplete/,
  );
  assert.throws(
    () => plan(migrations, [{ ...row, state: "failed" }], "down", "0001"),
    /Incomplete/,
  );
  assert.equal(
    plan(migrations, [{ ...row, state: "failed" }], "up", "0001")[0].version,
    "0001",
  );
});

test("up is logged and repeat-safe; down restores current data including new rows; re-up works", async () => {
  const db = fakeDatabase();
  const migrations = (await loadMigrations()).filter(m => m.version <= "0002");
  db.users.push({ user_id: 1, password: "old-plaintext", password_hash: null });
  db.orders.push({
    order_id: 1,
    status: "waiting_confirm",
    order_status: "pending",
  });
  await run(db, migrations, options);
  assert.equal(
    await bcrypt.compare("old-plaintext", db.users[0].password_hash),
    true,
  );
  assert.equal("password" in db.users[0], false);
  assert.equal("order_status" in db.orders[0], false);
  assert.equal(db.orders[0].status, "pending");
  assert.equal(db.lock, null);
  await assert.rejects(assertSchemaVersion(db), /migration required/);
  const events = db.events.length;
  await run(db, migrations, options);
  assert.equal(db.events.length, events);
  db.users.push({
    user_id: 2,
    password_hash: await bcrypt.hash("new-user", 4),
  });
  db.orders.push({ order_id: 2, status: "completed" });
  await run(db, migrations, { ...options, direction: "down" });
  assert.equal(db.users[1].password, db.users[1].password_hash);
  assert.equal(db.orders[1].order_status, "completed");
  await assert.rejects(assertSchemaVersion(db), /migration required/);
  await run(db, migrations, options);
  assert.equal(db.ledger[1].state, "applied");
  assert.ok(db.events.every((event) => event[5] === "unit-test"));
  assert.ok(!JSON.stringify(db.events).includes("old-plaintext"));
});

test("conflicting states/credentials and missing baseline stop before business writes", async () => {
  for (const problem of [
    "status",
    "credential",
    "baseline",
    "unknown-status",
  ]) {
    const db = fakeDatabase();
    if (problem === "status")
      db.orders.push({
        order_id: 1,
        status: "completed",
        order_status: "pending",
      });
    if (problem === "unknown-status")
      db.orders.push({ order_id: 1, status: "mystery" });
    if (problem === "credential")
      db.users.push({
        user_id: 1,
        password: "wrong",
        password_hash: await bcrypt.hash("right", 4),
      });
    if (problem === "baseline") db.columns.get("orders").delete("shift_id");
    await assert.rejects(canonical.up(db, async (_, work) => work()));
    assert.ok(!db.calls.some((sql) => /^(UPDATE|ALTER)/.test(sql)));
  }
});

test("DDL interruption is recorded; no blind retry, explicit same-direction resume succeeds", async () => {
  const db = fakeDatabase();
  const migrations = (await loadMigrations()).filter(m => m.version <= "0002");
  const query = db.query.bind(db);
  let fail = true;
  db.query = async (sql) => {
    if (fail && sql.includes("DROP COLUMN password"))
      throw Object.assign(new Error("private SQL"), { code: "DDL_FAILED" });
    return query(sql);
  };
  await assert.rejects(run(db, migrations, options), /private SQL/);
  assert.equal(db.ledger[1].state, "failed");
  assert.equal(db.columns.get("orders").has("order_status"), false);
  assert.equal(db.lock, null);
  await assert.rejects(run(db, migrations, options), /Incomplete/);
  fail = false;
  await run(db, migrations, { ...options, resume: "0002" });
  assert.equal(db.ledger[1].state, "applied");
  assert.ok(!JSON.stringify(db.events).includes("private SQL"));
});

test("concurrent runner cannot take over persistent lock", async () => {
  const db = fakeDatabase();
  db.lock = "other-runner";
  await assert.rejects(run(db, await loadMigrations(), options), /locked/);
  assert.equal(db.lock, "other-runner");
  assert.equal(db.ledger.length, 0);
});

test("runtime code cannot probe schema or query/write removed columns", () => {
  function scan(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) scan(file);
      else if (file.endsWith(".js")) {
        const source = fs.readFileSync(file, "utf8");
        assert.doesNotMatch(
          source,
          /information_schema|columnExists|tableExists|SHOW COLUMNS/i,
          file,
        );
        assert.doesNotMatch(
          source,
          /\bu\.password\b|\bo\.order_status\b|SET password =|SET order_status =/,
          file,
        );
      }
    }
  }
  scan(path.join(__dirname, "../src"));
});
