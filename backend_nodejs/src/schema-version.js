const REQUIRED_VERSION = "0002";
async function assertSchemaVersion(db) {
  const [rows] = await db.execute(
    "SELECT version, state FROM schema_migrations ORDER BY version",
  );
  if (
    rows.length !== 2 ||
    rows[0].version !== "0001" ||
    rows[1].version !== REQUIRED_VERSION ||
    rows.some((row) => row.state !== "applied")
  ) {
    throw new Error(
      "Database migration required; run migration status/up before starting this release",
    );
  }
}
module.exports = { REQUIRED_VERSION, assertSchemaVersion };
