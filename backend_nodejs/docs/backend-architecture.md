# Tách kiến trúc backend — đơn hàng và kho

Lưu ý cập nhật 15/10/2026: phần mô tả giữ alias/field dưới đây ghi lại thời điểm refactor. Hợp đồng HTTP hiện tại theo [api-contract.md](api-contract.md): một prefix `/api`, JSON snake_case và alias ứng dụng cũ trả 410.

## Phạm vi đã hoàn thành

Toàn bộ 14 khai báo route trong `order.routes.js` (bao gồm hai đường dẫn lịch sử), alias `/api/orders` và `/orders`, cùng `/my-orders` đã chuyển sang controller → service → repository. Đợt tiếp theo đã chuyển cả 8 endpoint của `inventory.routes.js`. Các module auth, payment/webhook, upload, user, voucher, report và ca làm **chưa** chuyển toàn bộ theo kiến trúc này; không coi đây là refactor xong mọi backend.

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

## Module kho

- `routes/inventory.routes.js`: đăng ký 8 endpoint; giữ guard đăng nhập và vai trò employee/admin cho toàn bộ router.
- `composition/inventory.js`: lắp ráp dependency; `controllers/inventory.controller.js`: chuyển input HTTP và ánh xạ lỗi nghiệp vụ, chuyển lỗi bất ngờ cho security handler.
- `services/inventory/item.service.js`: đọc/tạo/cập nhật mặt hàng, lịch sử, giá nhập và ánh xạ các alias JSON cũ.
- `services/inventory/movement.service.js`: nhập, xuất, kiểm kê; tính chênh lệch và điều phối transaction.
- `repositories/inventory.repository.js`: toàn bộ SQL kho, tham số bind và khóa `FOR UPDATE`. Cập nhật tồn và ghi lịch sử sử dụng cùng connection qua transaction helper dùng chung.

Đợt kho chỉ thay đổi cấu trúc, không đổi schema hay chạy giao dịch trên DB thật. Các hành vi cũ cần xử lý bằng đợt gia cố riêng: `employee_id` của log vẫn lấy từ body; validation số chưa kiểm tra đầy đủ NaN/Infinity; thiếu mặt hàng hoặc không đủ tồn ở luồng xuất vẫn đi qua lỗi 500 được che nội dung. Cập nhật không truyền ảnh vẫn xóa ảnh về null, khóa tìm kiếm vẫn chấp nhận ID hoặc barcode, và xuất kho chỉ trừ `inventory_items.stock`, không tự tăng `products.stock`. Những giới hạn này không được coi là đã sửa nhờ refactor.

## Tương thích và giới hạn chủ ý

Giữ endpoint, middleware phân quyền, tên field JSON, thông báo validation và status thành công 200/201. Quyền xem payment-status vẫn chặt hơn quyền xem chi tiết (khách sở hữu/nhân viên được gán/admin). Không thay đổi quy tắc voucher, thanh toán giả lập ewallet, giá/discount do nhân viên nhập hay chính sách hoàn tồn khi từ chối. Các vấn đề nghiệp vụ cần sửa bằng thay đổi riêng có test; refactor không đồng nghĩa đã bảo mật thêm các luồng này.

Loyalty hiện là service dùng chung của đơn hàng và thanh toán. `create.service.js` nhận loyalty qua dependency injection và truyền **cùng connection transaction** vào API cũ. SQL nội bộ loyalty chưa được tách trong đợt này. Đây là ranh giới tương thích được ghi rõ, không tạo vòng dependency repository → service.

Không thay đổi database/schema, không chạy giao dịch đơn hàng trên dữ liệu thật để thử refactor.

## Test và cách mở rộng

Chạy `npm run test:order` cho unit test policy/service, repository/transaction, HTTP endpoint/phân quyền và kiểm tra ranh giới kiến trúc. `npm test` chạy toàn bộ test Node hiện có. Test đơn hàng dùng dependency giả, không đọc `.env` hay kết nối cloud DB; test server hiện có có thể nạp cấu hình `.env` nhưng đã thay DB bằng stub trước khi import server.

Khi thêm luồng: thêm phương thức repository có tên theo thao tác dữ liệu; thêm use case service nhận object input và actor; thêm adapter controller; cuối cùng đăng ký route với guard. Test rollback/commit và trường hợp thiếu quyền trước khi thêm đường dẫn.

Chạy `npm run test:inventory` cho test mapping/validation mặt hàng, nhập/xuất/kiểm kê, rollback khi ghi log lỗi, SQL binding và dùng chung connection, HTTP status/phân quyền cho cả 8 endpoint, cùng kiểm tra ranh giới kiến trúc. Test kho dùng dependency giả, không kết nối cloud DB.

Các đợt tiếp theo nên chuyển payment và user bằng cùng factory/dependency injection, giữ mỗi đợt độc lập để dễ đối chiếu API và rollback mã. Không chuyển nguyên handler `(req, res)` sang một file đặt tên service vì như vậy vẫn chưa tách được trách nhiệm.
