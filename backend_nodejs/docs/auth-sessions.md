# Token bảo mật và phiên đăng nhập

## Triển khai

1. Sao lưu DB theo quy trình vận hành. Chạy migration customer-auth ngày 2026-06-02 nếu chưa có `users.password_hash`.
2. Trong backend chạy `npm ci` rồi `npm run migrate:auth`. Migration chỉ tạo thêm `auth_sessions` và `auth_refresh_tokens`, không xóa hay sửa user. Không tự chạy DDL mỗi lần server khởi động.
3. Restart backend, build và cập nhật app Flutter (`flutter pub get`). Các JWT cũ không có session bị từ chối: người dùng đăng nhập lại một lần. Không rollback riêng app/backend sang bản cũ vì không tương thích cơ chế xác thực.
4. Production bắt buộc HTTPS như `security.md`. JWT_SECRET vẫn là bí mật server; đổi secret sẽ vô hiệu access token nhưng refresh session chỉ bị thu hồi qua DB/logout-all/đổi mật khẩu.
   App release từ chối API HTTP trước khi gửi token/mật khẩu; truyền `--dart-define=API_BASE_URL=https://TEN_MIEN_API` khi build. Debug vẫn cho phép HTTP để chạy USB.

## Giao thức

- Login trả `token` (access JWT 15 phút), `refresh_token` (32 byte ngẫu nhiên, base64url), `expires_in=900`, `token_type=Bearer`, `user`.
- `POST /api/auth/refresh` với JSON `refresh_token`: cấp cặp mới, đánh dấu token cũ đã dùng. Thời hạn phiên tuyệt đối là 30 ngày từ login, không kéo dài vô hạn. Rate limit 60/IP/15 phút.
- `POST /api/auth/logout` + Bearer: thu hồi phiên hiện tại.
- `POST /api/auth/logout-all` + Bearer: thu hồi mọi phiên của chính người dùng, không nhận user_id từ client. Rate limit 10/IP/15 phút. Cần đăng nhập lại sau khi thực hiện.
- Mỗi API bảo vệ xác minh chữ ký HS256, purpose=access, session còn hiệu lực, tài khoản active và dấu vân tay mật khẩu hiện tại. Reset token không thể dùng làm access token. Đổi/reset mật khẩu khiến mọi phiên cũ không thể truy cập hoặc refresh, kể cả khi access JWT chưa hết hạn.
- Refresh chỉ lưu SHA-256 của token, không lưu token rõ. Giữ hash đã tiêu thụ để phát hiện dùng lại: replay thu hồi toàn bộ phiên liên quan (không ảnh hưởng thiết bị khác). Các mutation khóa row user trước để tránh refresh và logout-all tranh chấp.
- Thu hồi có hiệu lực cho lần kiểm tra xác thực kế tiếp; không hủy một giao dịch nghiệp vụ đã vượt qua xác thực và đang chạy.
- Có thể dọn **phiên đã hết hạn** định kỳ bằng `DELETE FROM auth_sessions WHERE expires_at < NOW()`; FK cascade dọn hash tương ứng. Không xóa riêng lịch sử token của phiên còn hạn vì sẽ mất khả năng phát hiện replay.

## Flutter

`TokenStore` lưu một bản ghi chứa cặp token bằng flutter_secure_storage, chỉ cache trong RAM. Không fallback sang Hive khi secure storage lỗi. Startup xóa auth_token/remember_pass cũ và compact Hive khi có token cũ; không chuyển JWT cũ thành phiên mới. Backup Hive cũ ngoài thiết bị không được tự xóa, nhưng JWT cũ không còn được backend chấp nhận.

`SessionClient` dùng chung cho API, voucher và upload: chỉ gửi đến origin cấu hình; không đi theo redirect; refresh một lần khi 401 rồi thử lại request một lần. Các request cùng hết hạn dùng chung một refresh. Response refresh đến sau logout không được khôi phục phiên. Lỗi mạng/5xx không xóa token; refresh bị từ chối thì xóa phiên. Nếu mạng mất đúng sau khi server đã rotate nhưng app chưa nhận cặp mới, lần dùng lại token cũ sẽ thu hồi phiên và yêu cầu đăng nhập lại — ưu tiên an toàn, không có cửa sổ cho replay.

Màn hình tài khoản có “Đăng xuất tất cả thiết bị” kèm xác nhận. Logout cần máy chủ xác nhận; khi offline không hiển thị thành công giả. Thiết bị khác trở về trạng thái chưa đăng nhập khi gọi API tiếp theo, không có push notification cưỡng bức đóng màn hình.

Android tắt auto-backup; plugin dùng Keystore. iOS/macOS có entitlement Keychain; cần build/sign trên macOS để kiểm chứng. Linux cần libsecret/jsoncpp theo tài liệu plugin. Web cần HTTPS/localhost và không chống được JavaScript độc hại cùng origin; dùng web nhiều tab có thể gây refresh replay và yêu cầu login lại (single-flight chỉ trong một instance app).

Tham khảo: [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage), [refresh rotation/replay — RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14).

## Kiểm thử

`npm run test:session`, `npm run test:security`, `npm run test:upload`; `flutter test test/session_client_test.dart`. Test Node dùng DB giả có tuần tự hóa transaction, không ghi dữ liệu cloud; cần kiểm thử tích hợp DB/proxy và thiết bị thật khi triển khai.
