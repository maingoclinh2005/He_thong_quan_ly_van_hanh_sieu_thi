const { loadMigrations, readState, plan, run } = require("./migration-runner");

async function main() {
  const [command = "plan", ...args] = process.argv.slice(2);
  const migrations = await loadMigrations();
  if (command === "plan") {
    console.log(
      migrations.map((m) => ({
        version: m.version,
        name: m.name,
        checksum: m.checksum,
      })),
    );
    console.log(
      "Offline catalog only. Use status to compare database history.",
    );
    return;
  }
  if (!["status", "up", "down", "unlock"].includes(command))
    throw new Error("Use plan, status, up, down or unlock");
  if (
    command !== "status" &&
    (!args.includes("--maintenance") || !args.includes("--backup-confirmed"))
  ) {
    throw new Error(
      "Stop ALL application writers and back up DB, then pass --maintenance --backup-confirmed",
    );
  }
  const pool = require("../src/config/db");
  let db;
  try {
    db = await pool.getConnection();
    if (command === "status") {
      const rows = await readState(db);
      console.table(rows);
      const pending = plan(migrations, rows, "up");
      console.log("Pending: " + pending.map((m) => m.version).join(", "));
    } else if (command === "unlock") {
      const owner = args.find((arg) => arg.startsWith("--owner="))?.slice(8);
      if (!owner || !/^[a-f0-9-]{36}$/.test(owner))
        throw new Error(
          "Provide exact --owner from lock table after verifying old process stopped",
        );
      const [result] = await db.execute(
        "DELETE FROM schema_migration_lock WHERE lock_id = 1 AND owner = ?",
        [owner],
      );
      if (result.affectedRows !== 1)
        throw new Error("Lock owner did not match");
      console.log("Stale lock released; migration history was not changed.");
    } else {
      await run(db, migrations, {
        direction: command,
        actor: process.env.MIGRATION_ACTOR,
        resume: args.find((arg) => arg.startsWith("--resume="))?.slice(9),
      });
    }
  } finally {
    if (db) db.release();
    await pool.end();
  }
}
main().catch((error) => {
  console.error(
    error.code
      ? "Migration failed (" +
          error.code +
          "); inspect schema_migration_events."
      : error.message,
  );
  process.exitCode = 1;
});
