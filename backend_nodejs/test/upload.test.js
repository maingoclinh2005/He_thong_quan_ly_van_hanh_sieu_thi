const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const express = require('express');
const jwt = require('jsonwebtoken');
const sharp = require('sharp');

// Stub only database lookup; exercise real JWT auth, role guard and multipart parser.
// Never connect to the configured cloud database during tests.
process.env.JWT_SECRET = 'upload-test-only-secret';
const users = { 1: 'admin', 2: 'employee', 3: 'customer' };
require.cache[require.resolve('../src/config/db')] = { exports: {
  execute: async (_sql, [id]) => [[users[id] ? { user_id: id, role_name: users[id], status: 'active' } : undefined].filter(Boolean)],
} };
const { createUploadRouter } = require('../src/routes/upload.routes');

test('upload boundary and sanitized output', async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'upload-test-'));
  const app = express();
  app.use('/api/uploads', createUploadRouter({ uploadDir: dir, requestLimit: 50 }));
  app.use('/limited', createUploadRouter({ uploadDir: dir, requestLimit: 1 }));
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  const png = await sharp({ create: { width: 4, height: 4, channels: 3, background: 'red' } }).png().toBuffer();
  const send = (data = png, name = 'test.png', type = 'image/png', id = 1, prefix = '/api/uploads', extra = false, headers = {}) => {
    const form = new FormData();
    if (data) form.append('image', new Blob([data], { type }), name);
    if (extra) form.append('image', new Blob([png], { type: 'image/png' }), 'second.png');
    return fetch(base + prefix + '/product-image', {
      method: 'POST', body: form, headers: {
        ...(id ? { Authorization: 'Bearer ' + jwt.sign({ id }, process.env.JWT_SECRET) } : {}), ...headers,
      },
    });
  };
  try {
    await t.test('anonymous and forged header denied', async () => {
      assert.equal((await send(png, 'x.png', 'image/png', null, '/api/uploads', false, { 'x-user-id': '1' })).status, 401);
    });
    await t.test('customer and inactive user denied', async () => {
      assert.equal((await send(png, 'x.png', 'image/png', 3)).status, 403);
      assert.equal((await send(png, 'x.png', 'image/png', 4)).status, 401);
    });
    await t.test('bad extension, MIME, signature, truncated pixels, SVG rejected', async () => {
      for (const [bytes, name, type] of [
        [png, 'x.html', 'image/png'], [png, 'x.png', 'text/html'],
        [png, 'x.jpg', 'image/jpeg'], [Buffer.from('<script>alert(1)</script>'), 'x.png', 'image/png'],
        [png.subarray(0, 40), 'x.png', 'image/png'], [Buffer.from('<svg/>'), 'x.svg', 'image/svg+xml'],
      ]) assert.equal((await send(bytes, name, type)).status, 400);
      assert.equal((await fs.readdir(dir)).length, 0);
    });
    await t.test('missing, extra, oversize files rejected without disk writes', async () => {
      assert.equal((await send(null)).status, 400);
      assert.equal((await send(png, 'x.png', 'image/png', 1, '/api/uploads', true)).status, 400);
      assert.equal((await send(Buffer.alloc(5 * 1024 * 1024 + 1))).status, 413);
      assert.equal((await fs.readdir(dir)).length, 0);
    });
    await t.test('pixel bomb rejected', async () => {
      const huge = await sharp({ create: { width: 5000, height: 5000, channels: 3, background: 'white' } }).png().toBuffer();
      assert.equal((await send(huge)).status, 400);
    });
    await t.test('admin and employee: all supported formats become clean webp', async () => {
      for (const format of ['png', 'jpeg', 'gif', 'webp']) {
        const bytes = await sharp(png).toFormat(format).toBuffer();
        const payload = Buffer.from('<script>untrusted-appended-payload</script>');
        const res = await send(Buffer.concat([bytes, payload]), 'photo.' + format, 'image/' + format, format === 'png' ? 1 : 2);
        assert.equal(res.status, 201);
        const body = await res.json();
        assert.match(body.data.url, /^\/uploads\/products\/[a-f0-9-]+\.webp$/);
        const stored = await fs.readFile(path.join(dir, path.basename(body.data.url)));
        assert.equal(stored.includes(payload), false);
        const meta = await sharp(stored).metadata();
        assert.equal(meta.format, 'webp');
        assert.equal(meta.exif, undefined);
      }
    });
    await t.test('rate limit by verified user', async () => {
      assert.equal((await send(png, 'x.png', 'image/png', 1, '/limited')).status, 201);
      assert.equal((await send(png, 'x.png', 'image/png', 1, '/limited')).status, 429);
    });
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await fs.rm(dir, { recursive: true, force: true });
  }
});
