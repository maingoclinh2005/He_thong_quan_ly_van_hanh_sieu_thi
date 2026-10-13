# Tách kiến trúc backend — đợt 1: đơn hàng

## Phạm vi đã hoàn thành

Toàn bộ 14 khai báo route trong `order.routes.js` (bao gồm hai đường dẫn lịch sử), alias `/api/orders` và `/orders`, cùng `/my-orders` đã chuyển sang controller → service → repository. Các module auth, payment/webhook, upload, inventory, user, voucher, report và ca làm **chưa** chuyển toàn bộ theo kiến trúc này; không coi đợt này là refactor xong mọi backend.

## Trách nhiệm

- `routes/order.routes.js`, `routes/myOrder.routes.js`: chỉ khai báo URL/method và middleware đăng nhập/phân quyền. Giữ thứ tự đường dẫn cụ thể trước `/:id`.
- `composition/order.js`: lắp ráp pool → repository → service → controller tại một nơi; không trộn nghiệp vụ.
- `controllers/order.controller.js`: lấy input/actor từ HTTP, gọi use case, chọn HTTP status. ApplicationError chỉ chứa loại lỗi nghiệp vụ và thông báo; lỗi bất ngờ chuyển vào security handler hiện có để không lộ SQL/stack.
- `services/order.service.js`: factory nhận dependency để test không cần Express hay DB thật.
- `services/order/read.service.js`: danh sách, chi tiết, lịch sử, trạng thái thanh toán, quyền sở hữu, dữ liệu khách hàng.
- `services/order/status.service.js`: xác nhận, từ chối, đã nhận hàng và cập nhật trạng thái.
- `services/order/checkout.service.js`: checkout giỏ hàng online và voucher.
- `services/order/create.service.js`: tạo đơn tại quầy, ca làm, voucher và tích điểm.
- `services/order/order-policy.js`: chuẩn hóa trạng thái/dữ liệu, quyền đọc, tính giảm giá (hàm thuần).
- `repositories/order.repository.js`: SQL, bind tham số, schema cũ/mới, khóa row, ghi order/items/payment và tồn kho. Không nhận SQL tùy ý từ controller/service.
- `repositories/transaction.js`: BEGIN/COMMIT/ROLLBACK/release; luôn trả connection về pool và không che lỗi gốc nếu rollback cũng lỗi.

Repository tạo bản gắn với connection riêng cho mỗi transaction. Service thực hiện toàn bộ ghi dữ liệu trên bản đó; chỉ đọc lại đơn sau khi commit. Các truy vấn metadata chỉ đọc dùng pool trực tiếp, tránh cách cũ lấy connection rồi quên release khi truy vấn lỗi. Nếu đọc lại sau commit lỗi, API vẫn có thể trả 500 dù transaction đã thành công; đợt này chưa thêm idempotency.

## Tương thích và giới hạn chủ ý

Giữ endpoint, middleware phân quyền, tên field JSON, thông báo validation và status thành công 200/201. Quyền xem payment-status vẫn chặt hơn quyền xem chi tiết (khách sở hữu/nhân viên được gán/admin). Không thay đổi quy tắc voucher, thanh toán giả lập ewallet, giá/discount do nhân viên nhập hay chính sách hoàn tồn khi từ chối. Các vấn đề nghiệp vụ cần sửa bằng thay đổi riêng có test; refactor không đồng nghĩa đã bảo mật thêm các luồng này.

Loyalty hiện là service dùng chung của đơn hàng và thanh toán. `create.service.js` nhận loyalty qua dependency injection và truyền **cùng connection transaction** vào API cũ. SQL nội bộ loyalty chưa được tách trong đợt này. Đây là ranh giới tương thích được ghi rõ, không tạo vòng dependency repository → service.

Không thay đổi database/schema, không chạy giao dịch đơn hàng trên dữ liệu thật để thử refactor.

## Test và cách mở rộng

Chạy `npm run test:order` cho unit test policy/service, repository/transaction, HTTP endpoint/phân quyền và kiểm tra ranh giới kiến trúc. `npm test` chạy toàn bộ test Node hiện có. Test đơn hàng dùng dependency giả, không đọc `.env` hay kết nối cloud DB; test server hiện có có thể nạp cấu hình `.env` nhưng đã thay DB bằng stub trước khi import server.

Khi thêm luồng: thêm phương thức repository có tên theo thao tác dữ liệu; thêm use case service nhận object input và actor; thêm adapter controller; cuối cùng đăng ký route với guard. Test rollback/commit và trường hợp thiếu quyền trước khi thêm đường dẫn.

Các đợt tiếp theo nên chuyển inventory, payment và user bằng cùng factory/dependency injection, giữ mỗi đợt độc lập để dễ đối chiếu API và rollback mã. Không chuyển nguyên handler `(req, res)` sang một file đặt tên service vì như vậy vẫn chưa tách được trách nhiệm.
