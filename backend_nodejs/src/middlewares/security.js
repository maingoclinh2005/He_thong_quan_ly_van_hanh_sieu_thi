const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const { randomUUID, createHash } = require('node:crypto');
const { isIP } = require('node:net');
const { rateLimit } = require('express-rate-limit');

const internalMessage = 'Lỗi hệ thống. Vui lòng thử lại sau.';
const splitList = (value) => String(value || '').split(',').map(s => s.trim()).filter(Boolean);

function configureSecurity(app, { env = process.env, auditSink = record => console.log(JSON.stringify(record)) } = {}) {
  const production = env.NODE_ENV === 'production';
  const origins = splitList(env.CORS_ORIGINS);
  for (const origin of origins) {
    const url = new URL(origin);
    if (!['http:', 'https:'].includes(url.protocol) || url.origin !== origin || (production && url.protocol !== 'https:')) {
      throw new Error('CORS_ORIGINS must contain exact origins (HTTPS in production)');
    }
  }
  const proxies = splitList(env.TRUSTED_PROXIES);
  for (const proxy of proxies) {
    const [address, mask, extra] = proxy.split('/');
    const version = isIP(address);
    if (!version || extra !== undefined || (mask !== undefined && (!/^\d+$/.test(mask) || Number(mask) < 1 || Number(mask) > (version === 4 ? 32 : 128)))) {
      throw new Error('TRUSTED_PROXIES must contain explicit proxy IPs or restricted CIDRs');
    }
  }
  app.disable('x-powered-by');
  app.set('trust proxy', proxies.length ? proxies : false);
  app.use((req, res, next) => {
    req.requestId = randomUUID();
    res.setHeader('X-Request-ID', req.requestId);
    const started = process.hrtime.bigint();
    let logged = false;
    const log = (aborted = false) => {
      if (logged) return;
      logged = true;
      // Never record bodies, query strings, tokens, cookies or raw exception messages.
      auditSink({ timestamp: new Date().toISOString(), event: 'http_request', request_id: req.requestId,
        method: req.method, route: req.route ? `${req.baseUrl || ''}${req.route.path}` : 'unmatched',
        actor_id: req.user?.user_id || null, role: req.user?.role_name || null,
        ip: req.ip, status: res.statusCode, aborted,
        outcome: aborted || res.statusCode >= 400 ? 'denied_or_failed' : 'success',
        duration_ms: Number(process.hrtime.bigint() - started) / 1e6 });
    };
    res.once('finish', () => log());
    res.once('close', () => log(!res.writableFinished));
    // Protect legacy handlers as well as the centralized error handler.
    const json = res.json.bind(res);
    res.json = body => {
      if (res.statusCode >= 500) body = { success: false, message: internalMessage, request_id: req.requestId };
      else if (res.statusCode >= 400 && body && typeof body === 'object') {
        const { error, stack, ...safe } = body;
        body = { ...safe, request_id: req.requestId };
      }
      return json(body);
    };
    next();
  });
  app.use(helmet({
    strictTransportSecurity: production ? { maxAge: 31536000, includeSubDomains: false } : false,
    contentSecurityPolicy: { directives: { 'upgrade-insecure-requests': production ? [] : null } },
    // Product images are public resources, including on a separately hosted storefront.
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  }));
  app.use((req, res, next) => {
    if ((production || env.REQUIRE_HTTPS === 'true') && !req.secure) {
      return res.status(403).json({ success: false, message: 'Yêu cầu kết nối HTTPS.' });
    }
    next();
  });
  app.use(cors({
    origin(origin, callback) {
      if (!origin || origins.includes(origin)) return callback(null, true);
      callback(Object.assign(new Error('Origin denied'), { status: 403, securityCode: 'cors' }));
    },
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    exposedHeaders: ['X-Request-ID', 'RateLimit', 'RateLimit-Policy', 'Retry-After'],
    credentials: false, maxAge: 600,
  }));
  app.use(express.json({ limit: '100kb', inflate: false }));
  app.use(express.urlencoded({ extended: false, limit: '100kb', parameterLimit: 100, inflate: false }));
}

function limiter(limit, windowMs = 15 * 60 * 1000, keyGenerator) {
  return rateLimit({ limit, windowMs, ...(keyGenerator ? { keyGenerator } : {}),
    // Forwarded headers from untrusted peers are deliberately ignored, not a configuration error.
    validate: { xForwardedForHeader: false },
    standardHeaders: 'draft-8', legacyHeaders: false,
    message: { success: false, message: 'Quá nhiều yêu cầu. Vui lòng thử lại sau.' } });
}

function accountKey(req) {
  let value = String(req.body?.identifier || req.body?.email || req.body?.phone || '').trim().toLowerCase();
  if (!value.includes('@')) value = value.replace(/\D/g, '');
  return createHash('sha256').update(value).digest('hex');
}

function createAuthLimits() {
  return {
    login: [limiter(30), limiter(10, 15 * 60 * 1000, accountKey)],
    otpSend: [limiter(10), limiter(3, 15 * 60 * 1000, accountKey)],
    otpVerify: [limiter(30), limiter(5, 10 * 60 * 1000, accountKey)],
    reset: limiter(10), register: limiter(10),
  };
}

function securityErrorHandler(error, req, res, next) {
  if (res.headersSent) return next(error);
  const messages = {
    'entity.too.large': [413, 'Nội dung yêu cầu vượt giới hạn 100 KB.'],
    'parameters.too.many': [413, 'Quá nhiều tham số.'],
    'entity.parse.failed': [400, 'JSON không hợp lệ.'],
    'encoding.unsupported': [415, 'Không hỗ trợ nội dung nén.'],
    'charset.unsupported': [415, 'Bảng mã không được hỗ trợ.'],
    cors: [403, 'Origin không được phép.'],
  };
  const [status, message] = messages[error.securityCode || error.type] || [500, internalMessage];
  res.status(status).json({ success: false, message });
}

module.exports = { configureSecurity, securityErrorHandler, createAuthLimits, limiter };
