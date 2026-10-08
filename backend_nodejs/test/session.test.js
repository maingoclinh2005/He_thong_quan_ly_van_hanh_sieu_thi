const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const express = require('express');
const { once } = require('node:events');
const { createHash } = require('node:crypto');
process.env.JWT_SECRET = 'session-test-secret-not-for-production';
const digest = value => createHash('sha256').update(value).digest('hex');
const users = new Map([[1, { user_id: 1, password: 'hash1', password_hash: 'hash1', status: 'active', role_name: 'customer' }], [2, { user_id: 2, password: 'hash2', status: 'active', role_name: 'admin' }]]);
const sessions = new Map();
const tokens = new Map();
let transactionQueue = Promise.resolve();
async function execute(sql, p) {
  if (sql.startsWith('SELECT s.user_id')) {
    const token = tokens.get(p[0]); const session = token && sessions.get(token.session_id);
    return [[...(session ? [{ user_id: session.user_id, session_id: session.session_id }] : [])]];
  }
  if (sql.startsWith('SELECT * FROM users') || sql.startsWith('SELECT user_id FROM users')) return [[...(users.has(p[0]) ? [{ ...users.get(p[0]) }] : [])]];
  if (sql.startsWith('SELECT *, expires_at')) {
    const row = sessions.get(p[0]); return [[...(row ? [{ ...row, unexpired: row.expires_at > new Date() }] : [])]];
  }
  if (sql.startsWith('SELECT * FROM auth_refresh_tokens')) return [[...(tokens.has(p[0]) ? [{ ...tokens.get(p[0]) }] : [])]];
  if (sql.startsWith('INSERT INTO auth_sessions')) {
    sessions.set(p[0], { session_id: p[0], user_id: p[1], credential_hash: p[2], expires_at: new Date(Date.now() + p[3] * 1000), revoked_at: null }); return [{}];
  }
  if (sql.startsWith('INSERT INTO auth_refresh_tokens')) { tokens.set(p[0], { token_hash: p[0], session_id: p[1], consumed_at: null }); return [{}]; }
  if (sql.startsWith('UPDATE auth_refresh_tokens')) { tokens.get(p[0]).consumed_at = new Date(); return [{}]; }
  if (sql.startsWith('UPDATE auth_sessions')) {
    for (const row of sessions.values()) {
      const matches = sql.includes('WHERE user_id') ? row.user_id === p[0] && (!sql.includes('AND session_id') || row.session_id === p[1]) : row.session_id === p[0];
      if (matches) row.revoked_at = new Date();
    }
    return [{}];
  }
  if (sql.includes('JOIN auth_sessions s')) {
    const user = users.get(p[0]), session = sessions.get(p[1]);
    return [[...(user && user.status === 'active' && session?.user_id === user.user_id && !session.revoked_at && session.expires_at > new Date() ? [{ ...user, credential_hash: session.credential_hash }] : [])]];
  }
  throw new Error('Unexpected SQL in test: ' + sql);
}
require.cache[require.resolve('../src/config/db')] = { exports: {
  execute,
  getConnection: async () => {
    let unlock;
    return {
      beginTransaction: async () => {
        const previous = transactionQueue;
        transactionQueue = new Promise(resolve => { unlock = resolve; });
        await previous;
      },
      execute, commit: async () => {}, rollback: async () => {}, release: () => unlock?.(),
    };
  },
} };
const service = require('../src/services/session.service');
const { requireAuth } = require('../src/middlewares/auth.middleware');

test('rotating refresh sessions, replay defense, immediate revocation and credential binding', async t => {
  const app = express();
  app.use(express.json());
  app.use('/api/auth', require('../src/routes/auth.routes'));
  app.get('/private', requireAuth, (req, res) => res.json(req.user));
  const server = app.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const check = async token => fetch(`http://127.0.0.1:${server.address().port}/private`, { headers: { Authorization: 'Bearer ' + token } });
  const first = await service.createSession(users.get(1));
  const otherDevice = await service.createSession(users.get(1));
  const otherUser = await service.createSession(users.get(2));
  const endpoint = async (path, token, body = {}) => fetch(`http://127.0.0.1:${server.address().port}/api/auth/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: JSON.stringify(body),
  });
  assert.equal((await endpoint('logout-all', null, { user_id: 2 })).status, 401);
  const claims = jwt.verify(first.token, process.env.JWT_SECRET);
  assert.equal(claims.purpose, 'access'); assert.equal(claims.exp - claims.iat, 900);
  assert.equal(tokens.has(first.refresh_token), false); assert.ok(tokens.has(digest(first.refresh_token)));
  const profile = await check(first.token); assert.equal(profile.status, 200);
  assert.ok(!(await profile.text()).includes('hash1'));
  const rotated = await service.refreshSession(first.refresh_token);
  assert.notEqual(rotated.refresh_token, first.refresh_token);
  await assert.rejects(service.refreshSession(first.refresh_token), { status: 401 });
  assert.equal((await check(rotated.token)).status, 401);
  await assert.rejects(service.refreshSession(rotated.refresh_token), { status: 401 });
  assert.equal((await check(otherDevice.token)).status, 200);
  assert.equal((await endpoint('logout-all', otherDevice.token, { user_id: 2 })).status, 200);
  assert.equal((await check(otherDevice.token)).status, 401);
  await assert.rejects(service.refreshSession(otherDevice.refresh_token), { status: 401 });
  assert.equal((await check(otherUser.token)).status, 200);
  const passwordSession = await service.createSession(users.get(1));
  users.get(1).password_hash = 'changed-password';
  assert.equal((await check(passwordSession.token)).status, 401);
  await assert.rejects(service.refreshSession(passwordSession.refresh_token), { status: 401 });
  for (const payload of [{ user_id: 1 }, { user_id: 1, purpose: 'password_reset', sid: claims.sid }]) {
    assert.equal((await check(jwt.sign(payload, process.env.JWT_SECRET))).status, 401);
  }
  const single = await service.createSession(users.get(1));
  const retained = await service.createSession(users.get(1));
  assert.equal((await endpoint('logout', single.token)).status, 200);
  assert.equal((await check(single.token)).status, 401);
  assert.equal((await check(retained.token)).status, 200);
  sessions.get(jwt.decode(retained.token).sid).expires_at = new Date(0);
  await assert.rejects(service.refreshSession(retained.refresh_token), { status: 401 });
  assert.equal((await check(retained.token)).status, 401);
  const disabled = await service.createSession(users.get(1));
  users.get(1).status = 'inactive';
  await assert.rejects(service.refreshSession(disabled.refresh_token), { status: 401 });
  assert.equal((await check(disabled.token)).status, 401);
  users.get(1).status = 'active';
  const race = await service.createSession(users.get(1));
  const results = await Promise.allSettled([service.refreshSession(race.refresh_token), service.refreshSession(race.refresh_token)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal((await check(results.find(r => r.status === 'fulfilled').value.token)).status, 401);
  const logoutRace = await service.createSession(users.get(1));
  await Promise.allSettled([service.refreshSession(logoutRace.refresh_token), service.revokeSessions(1)]);
  assert.equal((await check(logoutRace.token)).status, 401);
  await assert.rejects(service.refreshSession('malformed'), { status: 401 });
  await assert.rejects(service.refreshSession('A'.repeat(43)), { status: 401 });
  const apiPair = await service.createSession(users.get(2));
  const response = await endpoint('refresh', null, { refresh_token: apiPair.refresh_token });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.ok((await response.json()).refresh_token);
});
