const express = require('express');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const multer = require('multer');
const sharp = require('sharp');
const { rateLimit } = require('express-rate-limit');
const { requireAuth, requireRoles } = require('../middlewares/auth.middleware');

const formats = {
  '.jpg': ['image/jpeg', 'jpeg'], '.jpeg': ['image/jpeg', 'jpeg'],
  '.png': ['image/png', 'png'], '.gif': ['image/gif', 'gif'],
  '.webp': ['image/webp', 'webp'],
};
const invalidImage = 'Ảnh không hợp lệ. Chọn ảnh JPG, PNG, GIF hoặc WebP tối đa 5 MB và 20 megapixel.';

function createUploadRouter({
  uploadDir = path.join(__dirname, '..', '..', 'uploads', 'products'),
  requestLimit = 20,
} = {}) {
  const router = express.Router();
  let activeUploads = 0;
  const upload = multer({
    // Untrusted bytes never reach the publicly served directory.
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024, files: 1, fields: 0, parts: 2 },
    fileFilter: (req, file, cb) => {
      const expected = formats[path.extname(file.originalname).toLowerCase()];
      if (!expected || file.mimetype !== expected[0]) return cb(new Error(invalidImage));
      cb(null, true);
    },
  }).single('image');

  router.post('/product-image', requireAuth, requireRoles('employee', 'admin'), rateLimit({
    windowMs: 5 * 60 * 1000,
    limit: requestLimit,
    keyGenerator: (req) => String(req.user.user_id),
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    message: { success: false, message: 'Bạn tải ảnh quá nhanh. Vui lòng thử lại sau.' },
  }), (req, res) => {
    if (activeUploads >= 4) {
      return res.status(503).json({ success: false, message: 'Hệ thống đang xử lý ảnh. Vui lòng thử lại.' });
    }
    activeUploads++;
    const run = async () => {
      try {
        await new Promise((resolve, reject) => upload(req, res, (error) => error ? reject(error) : resolve()));
      } catch (error) {
        return res.status(error.code === 'LIMIT_FILE_SIZE' ? 413 : 400)
          .json({ success: false, message: invalidImage });
      }
      if (!req.file) return res.status(400).json({ success: false, message: 'Vui lòng chọn một file ảnh' });

      let cleanImage;
      try {
        const bytes = req.file.buffer;
        const signature = bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255])) ? 'jpeg'
          : bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ? 'png'
          : ['GIF87a', 'GIF89a'].includes(bytes.toString('ascii', 0, 6)) ? 'gif'
          : bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP' ? 'webp' : null;
        const expected = formats[path.extname(req.file.originalname).toLowerCase()];
        if (signature !== expected[1]) throw new Error('Invalid image signature');
        const decoder = sharp(req.file.buffer, { limitInputPixels: 20_000_000, failOn: 'warning' });
        const metadata = await decoder.metadata();
        if (metadata.format !== expected[1]) throw new Error('Content does not match declaration');
        // Decode/re-encode the first frame; strip metadata and appended payloads.
        cleanImage = await decoder.rotate().resize({ width: 2048, height: 2048, fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 85 }).timeout({ seconds: 10 }).toBuffer();
      } catch {
        return res.status(400).json({ success: false, message: invalidImage });
      }
      const filename = `${randomUUID()}.webp`;
      const destination = path.join(uploadDir, filename);
      await fs.mkdir(uploadDir, { recursive: true });
      try {
        await fs.writeFile(destination, cleanImage, { flag: 'wx' });
      } catch (error) {
        if (error.code !== 'EEXIST') await fs.unlink(destination).catch(() => {});
        throw error;
      }
      // Do not trust Host / X-Forwarded-Host for stored image URLs.
      const url = `/uploads/products/${filename}`;
      res.status(201).json({ success: true, message: 'Upload ảnh thành công', data: { url, image_url: url } });
    };
    run().catch(() => {
      if (!res.headersSent) res.status(500).json({ success: false, message: 'Không lưu được ảnh. Vui lòng thử lại.' });
    }).finally(() => { activeUploads--; });
  });
  return router;
}

module.exports = createUploadRouter();
module.exports.createUploadRouter = createUploadRouter;
