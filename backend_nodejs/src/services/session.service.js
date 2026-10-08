const { randomBytes, randomUUID, createHash } = require('node:crypto');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const ACCESS_SECONDS = 15 * 60;
const REFRESH_SECONDS = 30 * 24 * 60 * 60;
const hash = value => createHash('sha256').update(String(value)).digest('hex');
const credentialHash = user => hash(user.password_hash || user.password);
const invalid = () => Object.assign(new Error('Phiên đăng nhập hết hạn hoặc đã bị thu hồi. Vui lòng đăng nhập lại.'), { status: 401 });

function accessToken(userId, sessionId) {
  const secret = String(process.env.JWT_SECRET || '').trim();
  if (!secret) throw new Error('JWT_SECRET is required');
  return jwt.sign({ user_id: userId, sid: sessionId, purpose: 'access' }, secret, {
    algorithm: 'HS256', expiresIn: ACCESS_SECONDS,
  });
}

function tokenPair(userId, sessionId, refreshToken) {
  return { token: accessToken(userId, sessionId), refresh_token: refreshToken,
    token_type: 'Bearer', expires_in: ACCESS_SECONDS };
}

async function createSession(user) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [rows] = await connection.execute('SELECT * FROM users WHERE user_id = ? FOR UPDATE', [user.user_id]);
    if (!rows[0] || rows[0].status !== 'active' || credentialHash(rows[0]) !== credentialHash(user)) throw invalid();
    const sid = randomUUID();
    const refresh = randomBytes(32).toString('base64url');
    const pair = tokenPair(user.user_id, sid, refresh);
    await connection.execute('INSERT INTO auth_sessions (session_id, user_id, credential_hash, expires_at) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))',
      [sid, user.user_id, credentialHash(user), REFRESH_SECONDS]);
    await connection.execute('INSERT INTO auth_refresh_tokens (token_hash, session_id) VALUES (?, ?)', [hash(refresh), sid]);
    await connection.commit();
    return pair;
  } catch (error) { await connection.rollback(); throw error; }
  finally { connection.release(); }
}

async function refreshSession(rawToken) {
  if (typeof rawToken !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(rawToken)) throw invalid();
  const digest = hash(rawToken);
  const [matches] = await pool.execute('SELECT s.user_id, s.session_id FROM auth_refresh_tokens t JOIN auth_sessions s ON s.session_id = t.session_id WHERE t.token_hash = ?', [digest]);
  if (!matches[0]) throw invalid();
  const { user_id: userId, session_id: sid } = matches[0];
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    // All session mutations lock the user first, serializing refresh/login/logout-all.
    const [users] = await connection.execute('SELECT * FROM users WHERE user_id = ? FOR UPDATE', [userId]);
    const [sessions] = await connection.execute('SELECT *, expires_at > NOW() AS unexpired FROM auth_sessions WHERE session_id = ? FOR UPDATE', [sid]);
    const [tokens] = await connection.execute('SELECT * FROM auth_refresh_tokens WHERE token_hash = ? FOR UPDATE', [digest]);
    const session = sessions[0];
    if (!users[0] || users[0].status !== 'active' || !session || session.revoked_at || !session.unexpired || session.credential_hash !== credentialHash(users[0]) || !tokens[0]) throw invalid();
    if (tokens[0].consumed_at) {
      // Retain consumed hashes until the session expires to detect replay of ANY ancestor.
      await connection.execute('UPDATE auth_sessions SET revoked_at = NOW() WHERE session_id = ?', [sid]);
      await connection.commit();
      throw invalid();
    }
    const refresh = randomBytes(32).toString('base64url');
    const pair = tokenPair(userId, sid, refresh);
    await connection.execute('UPDATE auth_refresh_tokens SET consumed_at = NOW() WHERE token_hash = ?', [digest]);
    await connection.execute('INSERT INTO auth_refresh_tokens (token_hash, session_id) VALUES (?, ?)', [hash(refresh), sid]);
    await connection.commit();
    return pair;
  } catch (error) { await connection.rollback(); throw error; }
  finally { connection.release(); }
}

async function revokeSessions(userId, sid = null) {
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    await connection.execute('SELECT user_id FROM users WHERE user_id = ? FOR UPDATE', [userId]);
    await connection.execute('UPDATE auth_sessions SET revoked_at = NOW() WHERE user_id = ?' + (sid ? ' AND session_id = ?' : ''), sid ? [userId, sid] : [userId]);
    await connection.commit();
  } catch (error) { await connection.rollback(); throw error; }
  finally { connection.release(); }
}

module.exports = { createSession, refreshSession, revokeSessions, credentialHash };
