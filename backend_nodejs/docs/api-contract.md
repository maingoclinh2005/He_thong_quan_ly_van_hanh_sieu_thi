# Hợp đồng API (15/10/2026)

## Quy ước chính

- API ứng dụng chỉ dùng prefix `/api`. Health check: `GET /api/health`.
- JSON request/response và query parameter dùng `snake_case`, kể cả object lồng nhau: `order_id`, `discount_amount`, `payment_status`, `stock_quantity`.
- URL tài nguyên vẫn dùng kebab-case khi cần (`/api/my-orders`, `/api/work-shifts`). Tên biến nội bộ JavaScript/Dart và schema Hive không bị đổi.
- `/uploads/...` là URL file tĩnh, không phải endpoint JSON. Giữ nguyên để ảnh đã lưu tiếp tục hiển thị.
- Giữ nguyên envelope hiện có (`success`, `message`, `data` hoặc `voucher`); không đổi nghiệp vụ, quyền, transaction hay database.

## URL ứng dụng đã ngừng phục vụ

| Cũ | Chuẩn |
| --- | --- |
| `/cart`, `/api/cart` và các path con | `/api/carts` và các path con |
| `/orders` và các path con | `/api/orders` và các path con |
| `/my-orders` | `/api/my-orders` |
| `/` (health check cũ) | `/api/health` |

Ba nhóm alias ứng dụng đầu tiên trả **410 Gone** và field `replacement`, không redirect POST/PUT và không chạy nghiệp vụ/DB. Root cũ trả 404. Flutter trong cùng commit đã dùng URL chuẩn. Cần phát hành bản Flutter mới đồng bộ với backend; bản app cũ không được bảo đảm tiếp tục hoạt động.

## Chuyển đổi field và tương thích tạm thời

`middlewares/api-contract.js` chuẩn hóa JSON response tại ranh giới HTTP; field snake_case rõ ràng được ưu tiên khi domain còn trả cả hai alias. Date và row DB vẫn được serialize đúng. Request snake_case được chuyển cho các handler nội bộ còn dùng camelCase.

Request camelCase cũ tạm được chấp nhận với header `Deprecation`; gửi đồng thời hai tên tương đương bị từ chối 400, kể cả trong mảng/object con. Chặn các key prototype nguy hiểm. Chưa ấn định ngày ngừng nhận camelCase: trước khi bỏ cần xác nhận các client đã nâng cấp.

Flutter dùng `ApiContract.toWire` trong client HTTP chung để gửi JSON snake_case; `ApiContract.decode` tạo alias nội bộ cho model/UI hiện hữu. Không thêm alias lên mạng, không đổi dữ liệu Hive. Multipart upload và token không đổi nội dung. Đây là bước chuẩn hóa hợp đồng trên mạng, chưa phải đổi mọi tên biến/model nội bộ.

## Ngoại lệ giao thức thanh toán

Không đổi body/query/response của callback VNPay và ngân hàng: chữ ký phụ thuộc đúng tên field như `vnp_SecureHash`, `RspCode`, `transferAmount`.

URL chuẩn: `/api/payments/vnpay-return`, `/api/payments/vnpay-ipn`, `/api/payments/bank-webhook`, `/api/payments/sepay`.

Alias `/api/webhook` tạm chỉ phục vụ đúng bốn callback trên, kèm `Deprecation` và `Link: rel="successor-version"`. Không còn mount toàn bộ payment router công khai ở prefix này: các action như `/api/webhook/vnpay/create` trả 410. Cần cập nhật URL ở cấu hình VNPay/ngân hàng rồi mới gỡ các alias callback. Không tự sửa cấu hình dịch vụ ngoài hay secrets trong đợt này.

## Kiểm thử

- `npm test`: contract đệ quy, duplicate/prototype, query, callback giữ nguyên casing, server thật dùng DB giả, route 410 và phân quyền.
- `flutter test test/api_contract_test.dart test/session_client_test.dart`: JSON trên mạng, alias cho domain, multipart và retry/refresh.
- `npm run test:vnpay`: kiểm tra chữ ký cục bộ; không tạo giao dịch thanh toán thật.
