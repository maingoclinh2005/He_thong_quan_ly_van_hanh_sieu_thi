# Bảo vệ HTTP API

Chạy `npm ci` và restart backend sau khi cập nhật. Không commit `.env`.

- Helmet đặt CSP, nosniff và các header bảo vệ; HSTS bật ở production (1 năm, không áp dụng tự động cho subdomain).
- `CORS_ORIGINS` là danh sách origin chính xác, cách bằng dấu phẩy, ví dụ `https://shop.example.com,https://admin.example.com`. Không dùng wildcard, `null`, path hoặc dấu `/` cuối. Production chỉ chấp nhận HTTPS. Để trống sẽ từ chối request browser có Origin. App Flutter native và webhook không có Origin vẫn hoạt động; CORS không thay thế xác thực.
- JSON và form-urlencoded tối đa 100 KB; form tối đa 100 tham số; từ chối body nén. Multipart upload vẫn có giới hạn riêng 5 MB, một file.
- Login: 30 lần/IP và 10 lần/định danh trong 15 phút, tính cả thành công. Gửi OTP: 10/IP và 3/định danh trong 15 phút (chia sẻ email/SMS). Xác minh OTP: 30/IP trong 15 phút và 5/định danh trong 10 phút. Reset mật khẩu và đăng ký: 10/IP trong 15 phút. Định danh được chuẩn hóa rồi hash, không lưu bản rõ trong rate store.
- Upload: 60/IP/5 phút trước xác thực, cộng 20/tài khoản/5 phút sau xác thực; chỉ admin/employee. Quá giới hạn trả 429 với Retry-After.
- Rate store hiện ở RAM: reset khi restart và không chia sẻ giữa các process. Triển khai nhiều replica phải thêm shared store (Redis) hoặc giới hạn tập trung tại gateway. Đây không phải chống DDoS; vẫn cần giới hạn kết nối/body/timeouts ở reverse proxy.
- Audit JSON ra stdout cho mỗi request: thời gian, request ID do server tạo, route template, method, actor/role đã xác thực, IP, status, kết quả và thời lượng. Không ghi body/query/token/password/OTP. Thu stdout bằng trình quản lý dịch vụ vào kho log có phân quyền, rotation, retention và bảo vệ khỏi chỉnh sửa. Log này ghi hoạt động HTTP, không thay thế sổ lịch sử thay đổi dữ liệu trong transaction.
- Lỗi 5xx JSON dùng thông báo chung + request ID; lỗi 4xx không trả trường error/stack. Callback thanh toán không trả exception nội bộ. Lỗi parser và async chưa xử lý đi qua handler cuối. `/api/test-db` chỉ dành cho admin.
- OTP demo console bị vô hiệu hóa trong production dù cờ fallback bật.

## HTTPS production

Đặt `NODE_ENV=production`. HTTP bị từ chối 403, không thể tắt bằng `REQUIRE_HTTPS=false`. Development vẫn dùng HTTP cho USB; có thể bật `REQUIRE_HTTPS=true` để kiểm thử.

Node chạy sau reverse proxy TLS (Nginx/Caddy/load balancer). Cần tên miền và chứng chỉ hợp lệ; mã nguồn không tự cấp chứng chỉ hoặc triển khai HTTPS. Chỉ cho proxy truy cập cổng Node bằng firewall/private network. `TRUSTED_PROXIES` chứa chính xác IP hoặc CIDR hẹp của proxy; không dùng mạng khách hàng hay toàn Internet. Proxy phải **ghi đè** X-Forwarded-Proto từ kết nối TLS thật và X-Forwarded-For từ IP thật, không chuyển nguyên giá trị do khách gửi. Không dùng `trust proxy=true` hoặc số hop.

Ví dụ proxy cùng máy: `TRUSTED_PROXIES=127.0.0.1,::1`, upstream `127.0.0.1:3000`. Nginx trong server TLS:

```nginx
client_max_body_size 6m;
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $remote_addr;
}
```

Chỉ mở 443 cho API; cổng 80 có thể phục vụ ACME/redirect GET tại proxy, không chuyển tiếp API HTTP. App phải dùng `https://...` làm API_BASE_URL; callback VNPay và webhook cũng dùng HTTPS. Kiểm tra endpoint qua mạng bên ngoài trước khi phát hành. Cấu hình proxy tham khảo [Express](https://expressjs.com/en/guide/behind-proxies/), header tham khảo [Helmet](https://helmetjs.github.io/).

## Kiểm thử

`npm run test:security` và `npm run test:upload` dùng DB giả, không truy cập database thật.

Đã cập nhật các bản vá dependency tương thích, gồm proxy-addr 2.0.8. Audit ngày 07/10/2026 còn cảnh báo high ở Nodemailer (production) và chuỗi nodemon/chokidar/braces (development). Chưa dùng `npm audit fix --force`: cần nâng major Nodemailer và kiểm thử SMTP riêng; không coi bản vá HTTP này là đã giải quyết toàn bộ cảnh báo dependency.
