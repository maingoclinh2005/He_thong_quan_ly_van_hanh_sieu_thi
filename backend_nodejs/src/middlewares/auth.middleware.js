const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const { credentialHash } = require('../services/session.service');

function getJwtSecret() {
  const secret = String(process.env.JWT_SECRET || '').trim();
  if (!secret) {
    throw new Error('JWT_SECRET chưa được cấu hình');
  }
  return secret;
}

async function loadUser(userId, sessionId) {
  const [users] = await pool.execute(
    `SELECT u.user_id, u.full_name, u.email, u.phone, u.address, u.points,
            u.membership_code, u.status, u.created_at, r.role_name,
            u.password, u.password_hash, s.credential_hash
     FROM users u
     JOIN roles r ON r.role_id = u.role_id
     JOIN auth_sessions s ON s.user_id = u.user_id
     WHERE u.user_id = ? AND u.status = 'active'
       AND s.session_id = ? AND s.revoked_at IS NULL AND s.expires_at > NOW()
     LIMIT 1`,
    [userId, sessionId]
  );
  const user = users[0] || null;
  if (user) {
    if (credentialHash(user) !== user.credential_hash) return null;
    delete user.password;
    delete user.password_hash;
    delete user.credential_hash;
    user.id = user.user_id;
  }
  return user;
}

async function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const [scheme, token] = authHeader.split(' ');

  if (scheme === 'Bearer' && token) {
    try {
      const payload = jwt.verify(token, getJwtSecret(), { algorithms: ['HS256'] });
      if (payload.purpose !== 'access' || typeof payload.sid !== 'string' || !Number.isInteger(payload.user_id)) {
        return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập lại' });
      }
      const user = await loadUser(payload.user_id, payload.sid);
      if (!user) {
        return res.status(401).json({ success: false, message: 'Tài khoản không hợp lệ' });
      }
      req.user = user;
      req.sessionId = payload.sid;
      return next();
    } catch (error) {
      if (!(error instanceof jwt.JsonWebTokenError)) return next(error);
      return res.status(401).json({ success: false, message: 'Token không hợp lệ hoặc đã hết hạn' });
    }
  }

  return res.status(401).json({ success: false, message: 'Vui lòng đăng nhập bằng Bearer token hợp lệ' });
}

function requireRoles(...roles) {
  return (req, res, next) => {
    if (!req.user || !roles.includes(req.user.role_name)) {
      return res.status(403).json({ success: false, message: 'Bạn không có quyền thực hiện thao tác này' });
    }
    next();
  };
}

function requireSelfOrRoles(...roles) {
  return (req, res, next) => {
    const requestedId = Number(req.params.userId || req.params.employeeId || req.params.id);
    const currentUserId = Number(req.user?.user_id || req.user?.id);
    if (roles.includes(req.user?.role_name) || (requestedId && requestedId === currentUserId)) {
      return next();
    }
    return res.status(403).json({ success: false, message: 'Bạn không có quyền truy cập dữ liệu của người dùng này' });
  };
}

module.exports = { requireAuth, requireRoles, requireSelfOrRoles };
