const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const { once } = require('node:events');
const { configureSecurity, securityErrorHandler, createAuthLimits } = require('../src/middlewares/security');

async function serve(t, env = {}, mount = () => {}) {
  const app = express();
  const audit = [];
  configureSecurity(app, { env, auditSink: row => audit.push(row) });
  app.all('/echo', (req, res) => res.json({ success: true, ip: req.ip }));
  mount(app);
  app.use(securityErrorHandler);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  return { url: `http://127.0.0.1:${server.address().port}`, audit };
}

test('Helmet headers and exact CORS allowlist, including preflight and native clients', async t => {
  const { url } = await serve(t, { CORS_ORIGINS: 'https://shop.example.com' });
  const response = await fetch(url + '/echo', { headers: { Origin: 'https://shop.example.com' } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('access-control-allow-origin'), 'https://shop.example.com');
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(response.headers.get('x-powered-by'), null);
  assert.equal(response.headers.get('strict-transport-security'), null);
  assert.ok(!response.headers.get('content-security-policy').includes('upgrade-insecure-requests'));
  for (const origin of ['null', 'https://shop.example.com.evil.test', 'http://shop.example.com']) {
    assert.equal((await fetch(url + '/echo', { headers: { Origin: origin } })).status, 403);
  }
  const preflight = await fetch(url + '/echo', { method: 'OPTIONS', headers: {
    Origin: 'https://shop.example.com', 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'authorization,content-type',
  } });
  assert.equal(preflight.status, 204);
  assert.match(preflight.headers.get('access-control-allow-headers'), /Authorization/);
  assert.equal((await fetch(url + '/echo')).status, 200);
});

test('invalid security configuration fails closed', () => {
  for (const env of [{ CORS_ORIGINS: '*' }, { CORS_ORIGINS: 'null' }, { CORS_ORIGINS: 'https://test.com/' },
    { NODE_ENV: 'production', CORS_ORIGINS: 'http://test.com' }, { TRUSTED_PROXIES: 'true' }, { TRUSTED_PROXIES: '0.0.0.0/0' }]) {
    assert.throws(() => configureSecurity(express(), { env }));
  }
});

test('production requires HTTPS and ignores spoofed forwarding from untrusted clients', async t => {
  const { url } = await serve(t, { NODE_ENV: 'production', REQUIRE_HTTPS: 'false' });
  for (const headers of [{}, { 'X-Forwarded-Proto': 'https', 'X-Forwarded-For': '8.8.8.8' }]) {
    assert.equal((await fetch(url + '/echo', { headers })).status, 403);
  }
  const trusted = await serve(t, { NODE_ENV: 'production', TRUSTED_PROXIES: '127.0.0.1' });
  const secure = await fetch(trusted.url + '/echo', { headers: { 'X-Forwarded-Proto': 'https', 'X-Forwarded-For': '192.0.2.5' } });
  assert.equal(secure.status, 200);
  assert.match(secure.headers.get('strict-transport-security'), /max-age=31536000/);
  assert.equal((await secure.json()).ip, '192.0.2.5');
  assert.equal((await fetch(trusted.url + '/echo')).status, 403);
});

test('body limits, malformed JSON, compression and excess form fields return safe errors', async t => {
  const { url } = await serve(t);
  const cases = [
    ['application/json', JSON.stringify({ text: 'x'.repeat(103000) }), 413],
    ['application/json', '{bad secret body', 400],
    ['application/x-www-form-urlencoded', 'x=' + 'x'.repeat(103000), 413],
    ['application/x-www-form-urlencoded', Array.from({ length: 101 }, (_, i) => `a${i}=1`).join('&'), 413],
  ];
  for (const [type, body, status] of cases) {
    const response = await fetch(url + '/echo', { method: 'POST', headers: { 'Content-Type': type }, body });
    assert.equal(response.status, status);
    const data = await response.json();
    assert.ok(data.request_id);
    assert.ok(!JSON.stringify(data).includes('secret body'));
  }
  assert.equal((await fetch(url + '/echo', { method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Encoding': 'gzip' }, body: 'compressed' })).status, 415);
});

test('legacy errors, async exceptions and audit redact secrets and keep actor/request ID', async t => {
  const { url, audit } = await serve(t, {}, app => {
    app.get('/legacy', (req, res) => res.status(500).json({ message: 'SQL password SECRET', error: 'SECRET', stack: 'SECRET' }));
    app.get('/bad', (req, res) => res.status(400).json({ message: 'Invalid input', error: 'SECRET', stack: 'SECRET' }));
    app.get('/throw', async () => { throw new Error('SECRET'); });
    app.post('/actor/:id', (req, res) => { req.user = { user_id: 7, role_name: 'admin' }; res.json({ success: true }); });
  });
  for (const path of ['/legacy', '/bad', '/throw']) {
    const response = await fetch(url + path);
    assert.equal(response.status, path === '/bad' ? 400 : 500);
    assert.ok(!(await response.text()).includes('SECRET'));
  }
  const response = await fetch(url + '/actor/SECRET?token=SECRET', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer SECRET', 'X-Request-ID': 'SECRET' }, body: JSON.stringify({ password: 'SECRET', otp: 'SECRET' }) });
  await response.text();
  const row = audit.find(row => row.actor_id === 7);
  assert.equal(row.route, '/actor/:id');
  assert.equal(row.role, 'admin');
  assert.equal(row.request_id, response.headers.get('x-request-id'));
  assert.ok(!JSON.stringify(audit).includes('SECRET'));
});

test('login and OTP account limits are normalized and shared across send channels', async t => {
  const { url } = await serve(t, {}, app => {
    const limits = createAuthLimits();
    for (const [path, middleware] of [['login', limits.login], ['email', limits.otpSend], ['phone', limits.otpSend], ['verify', limits.otpVerify]]) {
      app.post('/' + path, ...middleware, (req, res) => res.json({ success: true }));
    }
  });
  async function post(path, body) {
    return fetch(url + '/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  }
  for (let i = 0; i < 10; i++) assert.equal((await post('login', { email: 'USER@example.com' })).status, 200);
  const blocked = await post('login', { identifier: ' user@EXAMPLE.com ' });
  assert.equal(blocked.status, 429);
  assert.ok(Number(blocked.headers.get('retry-after')) > 0);
  for (let i = 0; i < 3; i++) assert.equal((await post(i % 2 ? 'phone' : 'email', { identifier: '090-123-4567' })).status, 200);
  assert.equal((await post('phone', { phone: '0901234567' })).status, 429);
  for (let i = 0; i < 5; i++) assert.equal((await post('verify', { identifier: 'verify@example.com' })).status, 200);
  assert.equal((await post('verify', { identifier: 'verify@example.com' })).status, 429);
});

test('login IP limit catches identifier rotation and does not trust forged XFF', async t => {
  const { url } = await serve(t, {}, app => {
    app.post('/login', ...createAuthLimits().login, (req, res) => res.json({ success: true }));
  });
  for (let i = 0; i < 31; i++) {
    const response = await fetch(url + '/login', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': `192.0.2.${i + 1}` }, body: JSON.stringify({ email: `${i}@example.com` }) });
    assert.equal(response.status, i === 30 ? 429 : 200);
  }
});

test('real application wires guards, safe DB errors, login/OTP/upload limits', async t => {
  process.env.NODE_ENV = 'test';
  process.env.REQUIRE_HTTPS = 'false';
  process.env.TRUSTED_PROXIES = '';
  process.env.CORS_ORIGINS = '';
  process.env.JWT_SECRET = 'security-test-only-secret';
  let dbCalls = 0;
  require.cache[require.resolve('../src/config/db')] = { exports: {
    execute: async () => { dbCalls++; throw new Error('PRIVATE_SQL_PASSWORD'); },
  } };
  const logs = [];
  const originalLog = console.log;
  console.log = (...values) => logs.push(values.join(' '));
  t.after(() => { console.log = originalLog; });
  const app = require('../src/server');
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const url = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(url + '/api/test-db')).status, 401);
  assert.equal(dbCalls, 0);
  const failure = await fetch(url + '/api/categories');
  assert.equal(failure.status, 500);
  assert.ok(!(await failure.text()).includes('PRIVATE_SQL_PASSWORD'));
  assert.equal((await fetch(url + '/does-not-exist')).status, 404);
  for (const [path, limit, body] of [
    ['/api/auth/login', 10, { email: 'integration@example.com', password: 'PRIVATE_PASSWORD' }],
    ['/api/auth/forgot-password/email', 3, { email: 'otp@example.com' }],
    ['/api/auth/verify-otp', 5, { email: 'otp@example.com', otp: 'PRIVATE_OTP', type: 'EMAIL' }],
    ['/api/uploads/product-image', 60, {}],
  ]) {
    for (let i = 0; i <= limit; i++) {
      const response = await fetch(url + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      if (i === limit) assert.equal(response.status, 429, path);
      else assert.notEqual(response.status, 429, path);
      await response.text();
    }
  }
  assert.ok(!logs.join('').includes('PRIVATE_'));
  const records = logs.filter(line => line.startsWith('{')).map(line => JSON.parse(line));
  assert.ok(records.some(row => row.route === '/api/auth/login' && row.status === 429));
  assert.ok(records.some(row => row.route === '/api/uploads/product-image' && row.status === 401));
});
