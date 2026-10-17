const bcrypt = require("bcrypt");
const { validate } = require("./0001_baseline");
const validHash = (value) =>
  typeof value === "string" &&
  /^\$2[ab]\$\d{2}\$[./A-Za-z0-9]{53}$/.test(value);
const aliases = {
  waiting_confirm: "pending",
  preparing: "shipping",
  "Hoàn thành": "completed",
  "hoàn thành": "completed",
  cancelled: "rejected",
};
const statuses = new Set([
  "pending",
  "confirmed",
  "shipping",
  "completed",
  "rejected",
]);
function normalizeStatus(value) {
  const status = aliases[value] || value;
  if (!statuses.has(status))
    throw new Error("Unknown order status; reconcile data before migration");
  return status;
}
async function credential(user) {
  const current = user.password_hash;
  const old = user.password;
  if (current && !validHash(current))
    throw new Error("Invalid password_hash; reset credential before migration");
  if (current && old && current !== old) {
    if (validHash(old) || !(await bcrypt.compare(old, current))) {
      throw new Error(
        "Conflicting credentials; reconcile user " + user.user_id,
      );
    }
  }
  if (current) return current;
  if (!old) throw new Error("Missing credential; reset user " + user.user_id);
  return validHash(old) ? old : bcrypt.hash(old, 10);
}
async function hasColumn(db, table, column) {
  const [rows] = await db.execute(
    "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
    [table, column],
  );
  return rows.length > 0;
}
async function eachBatch(db, table, id, visit) {
  let last = 0;
  // Identifiers are literals supplied only by this migration.
  for (;;) {
    const [rows] = await db.execute(
      "SELECT * FROM " +
        table +
        " WHERE " +
        id +
        " > ? ORDER BY " +
        id +
        " LIMIT 500",
      [last],
    );
    if (!rows.length) return;
    for (const row of rows) await visit(row);
    last = rows.at(-1)[id];
  }
}
async function preflight(db) {
  await validate(db);
  await eachBatch(db, "users", "user_id", credential);
  await eachBatch(db, "orders", "order_id", (row) => {
    const status = normalizeStatus(row.status);
    if (row.order_status && normalizeStatus(row.order_status) !== status) {
      throw new Error(
        "Conflicting order states; reconcile order " + row.order_id,
      );
    }
  });
}
async function up(db, step) {
  await step("preflight-no-writes", () => preflight(db));
  await step("backfill-password-hash", () =>
    eachBatch(db, "users", "user_id", async (row) => {
      const hash = await credential(row);
      if (hash !== row.password_hash)
        await db.execute(
          "UPDATE users SET password_hash = ? WHERE user_id = ?",
          [hash, row.user_id],
        );
    }),
  );
  await step("normalize-order-status", () =>
    eachBatch(db, "orders", "order_id", async (row) => {
      const status = normalizeStatus(row.status);
      if (status !== row.status)
        await db.execute("UPDATE orders SET status = ? WHERE order_id = ?", [
          status,
          row.order_id,
        ]);
    }),
  );
  await step("drop-legacy-order-status", async () => {
    if (await hasColumn(db, "orders", "order_status"))
      await db.query("ALTER TABLE orders DROP COLUMN order_status");
  });
  await step("drop-legacy-password", async () => {
    if (await hasColumn(db, "users", "password"))
      await db.query("ALTER TABLE users DROP COLUMN password");
  });
}
async function down(db, step) {
  // Operational rollback: include accounts/orders created AFTER up. Never
  // restore stale snapshots over current passwords/status or resurrect plaintext.
  await step("restore-password-column", async () => {
    if (!(await hasColumn(db, "users", "password")))
      await db.query("ALTER TABLE users ADD COLUMN password VARCHAR(255) NULL");
    await db.execute("UPDATE users SET password = password_hash");
  });
  await step("restore-order-status-column", async () => {
    if (!(await hasColumn(db, "orders", "order_status")))
      await db.query(
        "ALTER TABLE orders ADD COLUMN order_status VARCHAR(50) NULL",
      );
    await db.execute("UPDATE orders SET order_status = status");
  });
}
module.exports = {
  version: "0002",
  name: "canonical_columns",
  up,
  down,
  preflight,
  normalizeStatus,
  credential,
};
