const fs = require("node:fs/promises");
const path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");

async function loadMigrations(
  directory = path.join(__dirname, "../database/versioned"),
) {
  const files = (await fs.readdir(directory))
    .filter((file) => /^\d{4}_[a-z_]+\.js$/.test(file))
    .sort();
  const migrations = [];
  for (const file of files) {
    const source = (
      await fs.readFile(path.join(directory, file), "utf8")
    ).replace(/\r\n/g, "\n");
    const migration = require(path.join(directory, file));
    if (
      migration.version !== file.slice(0, 4) ||
      migrations.some((m) => m.version === migration.version)
    )
      throw new Error("Invalid migration version");
    migrations.push({
      ...migration,
      checksum: createHash("sha256").update(source).digest("hex"),
    });
  }
  return migrations;
}

async function initialize(db) {
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version VARCHAR(20) PRIMARY KEY, name VARCHAR(100) NOT NULL, checksum CHAR(64) NOT NULL,
    state VARCHAR(20) NOT NULL, direction VARCHAR(4) NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migration_events (
    event_id BIGINT AUTO_INCREMENT PRIMARY KEY, run_id CHAR(36) NOT NULL,
    version VARCHAR(20) NOT NULL, direction VARCHAR(4) NOT NULL, step VARCHAR(100) NOT NULL,
    outcome VARCHAR(20) NOT NULL, actor VARCHAR(100) NOT NULL, error_code VARCHAR(100) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
  // A persistent mutex survives DDL auto-commit and works without GET_LOCK.
  // No timeout/automatic takeover: a crashed runner must be investigated first.
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migration_lock (
    lock_id INT PRIMARY KEY, owner CHAR(36) NOT NULL,
    acquired_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
  ) ENGINE=InnoDB`);
}
async function readState(db) {
  try {
    return (
      await db.execute("SELECT * FROM schema_migrations ORDER BY version")
    )[0];
  } catch (error) {
    if (error.code === "ER_NO_SUCH_TABLE") return [];
    throw error;
  }
}
function plan(migrations, rows, direction, resume) {
  for (const row of rows) {
    const migration = migrations.find((m) => m.version === row.version);
    if (!migration || migration.checksum !== row.checksum)
      throw new Error("Unknown version/checksum drift: " + row.version);
  }
  const dirty = rows.filter(
    (row) => !["applied", "rolled_back"].includes(row.state),
  );
  if (dirty.length) {
    if (
      dirty.length !== 1 ||
      dirty[0].version !== resume ||
      dirty[0].direction !== direction
    ) {
      throw new Error(
        "Incomplete migration; inspect event log and explicitly resume the same direction/version",
      );
    }
    return [migrations.find((m) => m.version === resume)];
  }
  if (resume) throw new Error("Nothing to resume");
  let gap = false;
  for (const migration of migrations) {
    const applied = rows.some(
      (row) => row.version === migration.version && row.state === "applied",
    );
    if (applied && gap) throw new Error("Migration history contains a gap");
    if (!applied) gap = true;
  }
  if (direction === "down") {
    const applied = migrations.filter((m) =>
      rows.some((r) => r.version === m.version && r.state === "applied"),
    );
    const latest = applied.at(-1);
    if (!latest || latest.version === "0001")
      throw new Error("No reversible migration above baseline");
    return [latest];
  }
  return migrations.filter(
    (m) => !rows.some((r) => r.version === m.version && r.state === "applied"),
  );
}
async function run(
  db,
  migrations,
  { direction = "up", actor, resume, log = console.log } = {},
) {
  if (!["up", "down"].includes(direction) || !actor || actor.length > 100)
    throw new Error("Direction and deployment actor required");
  await initialize(db);
  const owner = randomUUID();
  await db.execute(
    "INSERT INTO schema_migration_lock (lock_id, owner) VALUES (1, ?)",
    [owner],
  );
  log("Migration lock owner: " + owner);
  try {
    const queue = plan(migrations, await readState(db), direction, resume);
    for (const migration of queue) {
      const runId = randomUUID();
      const event = (step, outcome, code = null) =>
        db.execute(
          "INSERT INTO schema_migration_events (run_id, version, direction, step, outcome, actor, error_code) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [runId, migration.version, direction, step, outcome, actor, code],
        );
      await db.execute(
        `INSERT INTO schema_migrations (version, name, checksum, state, direction) VALUES (?, ?, ?, 'running', ?)
        ON DUPLICATE KEY UPDATE state = 'running', direction = VALUES(direction)`,
        [migration.version, migration.name, migration.checksum, direction],
      );
      try {
        await event("migration", "started");
        const step = async (name, work) => {
          await event(name, "started");
          await work();
          await event(name, "succeeded");
        };
        await migration[direction](db, step);
        await event("migration", "succeeded");
        await db.execute(
          "UPDATE schema_migrations SET state = ? WHERE version = ?",
          [direction === "up" ? "applied" : "rolled_back", migration.version],
        );
        log(migration.version + " " + direction + " succeeded");
      } catch (error) {
        // Do not store SQL, bind values, password hashes or connection strings.
        await event(
          "migration",
          "failed",
          String(error.code || "MIGRATION_FAILED").slice(0, 100),
        );
        await db.execute(
          "UPDATE schema_migrations SET state = 'failed' WHERE version = ?",
          [migration.version],
        );
        throw error;
      }
    }
  } finally {
    await db.execute(
      "DELETE FROM schema_migration_lock WHERE lock_id = 1 AND owner = ?",
      [owner],
    );
  }
}
module.exports = { loadMigrations, initialize, readState, plan, run };
