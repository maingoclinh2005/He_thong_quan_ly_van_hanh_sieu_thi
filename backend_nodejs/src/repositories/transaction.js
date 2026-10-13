// One connection per use case, including failures during BEGIN/COMMIT.
async function withTransaction(pool, work) {
  const connection = await pool.getConnection();
  let begun = false;
  try {
    await connection.beginTransaction();
    begun = true;
    const result = await work(connection);
    await connection.commit();
    begun = false;
    return result;
  } catch (error) {
    if (begun) {
      try {
        await connection.rollback();
      } catch {
        /* Keep the original failure. */
      }
    }
    throw error;
  } finally {
    connection.release();
  }
}

module.exports = { withTransaction };
