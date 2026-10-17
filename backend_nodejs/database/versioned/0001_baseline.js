// Adopt an EXISTING, fully bootstrapped installation. Never silently claim that
// historical SQL files ran: validate the schema the application actually needs.
const required = {
  users: ["user_id", "password_hash", "employment_type"],
  orders: [
    "order_id",
    "status",
    "payment_status",
    "shift_id",
    "order_type",
    "delivery_method",
    "payment_method",
    "confirmed_by",
    "confirmed_at",
    "rejection_reason",
    "transfer_content",
    "transaction_id",
    "paid_at",
    "points_used",
    "points_earned",
    "points_discount",
    "updated_at",
  ],
  payments: ["payment_id", "transaction_id", "qr_content", "paid_at"],
  work_shifts: ["shift_id", "status"],
  employee_day_overrides: ["employee_id", "work_date", "day_status"],
  auth_sessions: ["session_id", "credential_hash", "expires_at", "revoked_at"],
  auth_refresh_tokens: ["token_hash", "session_id"],
  password_reset_tokens: ["user_id", "otp_code", "used"],
  loyalty_transactions: ["order_id", "type"],
};

async function validate(db) {
  for (const [table, names] of Object.entries(required)) {
    const [rows] = await db.execute(
      "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?",
      [table],
    );
    const columns = new Set(rows.map((row) => row.COLUMN_NAME));
    const missing = names.filter((name) => !columns.has(name));
    if (missing.length)
      throw new Error(
        "Baseline incomplete: " + table + "." + missing.join(","),
      );
  }
}
module.exports = {
  version: "0001",
  name: "baseline",
  required,
  validate,
  up: async (db, step) => step("validate-existing-schema", () => validate(db)),
  down: async () => {
    throw new Error(
      "Baseline cannot be rolled back; restore a database backup instead",
    );
  },
};
