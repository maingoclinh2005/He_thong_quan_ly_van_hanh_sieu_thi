# Nguồn sự thật tồn kho

## Mô hình

Một bảng inventory_ledger, hai tài khoản tồn theo vị trí: warehouse (inventory_items) và shelf (products).
Cùng barcode là cùng mặt hàng; đơn vị và category phải khớp khi chuyển. Hai vị trí có số lượng riêng, không ép bằng nhau.
products.stock và inventory_items.stock chỉ là projection SUM(delta) của từng tài khoản, phục vụ đọc nhanh.
Mọi ghi tồn runtime đi qua stock-ledger.repository trên cùng connection transaction với nghiệp vụ.
Không UPDATE stock trực tiếp, không sửa/xóa ledger đã ghi; sửa sai bằng bút toán điều chỉnh.
Giới hạn quyền DB của ứng dụng; tài khoản quản trị DB vẫn có thể phá invariant nếu ghi SQL ngoài luồng.

- Nhập kho: receipt dương ở warehouse.
- Chuyển lên kệ: hai bút toán transfer âm kho/dương kệ, chung operation_id, commit/rollback cùng nhau.
- Bán: sale âm trên kệ cùng transaction tạo order_items.
- Từ chối/hủy đơn chưa hoàn thành: sale_reversal, khóa định danh reverse:ledger_id chống cộng lại hai lần.
- Kiểm kê hoặc cập nhật stock có chủ đích: adjustment chênh lệch so với ledger.
- Tạo mặt hàng: opening. Không đổi barcode/đơn vị của tài khoản đã tạo.
- Không mở lại đơn completed/rejected; hoàn tiền và trả hàng sau hoàn tất là nghiệp vụ riêng, chưa nằm trong thay đổi này.

Khóa hàng tài khoản bằng FOR UPDATE trước khi đọc ledger và ghi projection. Thiếu tồn hoặc lỗi ở bất kỳ bước nào sẽ rollback.
Deadlock của DB vẫn có thể xảy ra và được trả lỗi/rollback; chưa có cơ chế tự retry mọi nghiệp vụ.
inventory_logs cũ được giữ để tra giá nhập/lịch sử cũ; không dùng làm nguồn số lượng mới.
API /inventory/logs hiển thị ledger từ số dư đầu kỳ 0003 trở đi; lịch sử legacy trước thời điểm này vẫn ở inventory_logs để đối soát/xuất báo cáo, không được nhập lại thành biến động mới.

## API và Flutter

POST /api/inventory/export bây giờ thực hiện toàn bộ chuyển kho lên kệ và trả product.
Không gọi create/update product trước API này. Triển khai backend và Flutter cùng đợt, ngừng client cũ dùng luồng hai API.
request_key dài 16–80 ký tự chữ/số/gạch dưới/gạch ngang: cùng khóa + cùng payload không chuyển lần nữa; đổi payload sẽ bị từ chối.
Client Flutter giữ khóa chờ trong settings trước khi gửi, dùng lại khi retry; chống bấm song song cùng mặt hàng/số lượng.
Client ngoài Flutter nên luôn cung cấp request_key (backend còn nhận yêu cầu thiếu khóa để tương thích).
employee_id luôn lấy từ người dùng đã xác thực, không tin actor gửi trong body.

## Migration 0003

Theo quy trình maintenance/backup trong migrations.md. Chỉ chạy sau 0001 và 0002.
Preflight chặn barcode trống/trùng, category không tồn tại, tồn âm/phân số/quá giới hạn và đơn vị/category kho-kệ lệch.
inventory_items.category_id được bổ sung foreign key ON DELETE RESTRICT.
Không tự xóa dữ liệu lỗi hoặc tự chọn danh mục thay thế.

Số dư đầu kỳ giữ nguyên tồn thực tế của từng vị trí. Đơn pending/confirmed/shipping đã trừ tồn trước đây được gieo sale tương ứng,
đồng thời cộng bù vào opening của kệ để SUM(delta) vẫn bằng tồn hiện tại. Nhờ vậy hủy đơn cũ có thể hoàn tồn.
Phải đối soát trên staging rằng dữ liệu cũ đã trừ tồn các đơn này; không thể suy ra lịch sử bị sửa tay chỉ từ snapshot.

Sau up: npm run stock:check đối chiếu projection và ledger bằng snapshot chỉ đọc.
Chạy smoke test nhập, kiểm kê, chuyển kho, gửi lại cùng request_key, bán vượt tồn, hủy đơn và chuyển trạng thái terminal.
Kiểm thử cạnh tranh và DDL/FK/CHECK phải chạy trên MySQL/TiDB staging đúng phiên bản trước production.

## Rollback

Down 0003 dựng lại projection từ ledger rồi đổi tên thành inventory_ledger_0003_archive, giữ toàn bộ lịch sử.
Chỉ gỡ FK category do 0003 thêm. Dừng tất cả writer trong toàn bộ quá trình; DDL có thể tự commit.
Ứng dụng mới không khởi động khi 0003 không applied.
Không chạy lại up mù sau rollback: archive sẽ chặn. Nếu mã cũ đã ghi stock, cần migration đối soát được review để nối lịch sử,
không xóa archive/đánh applied bằng tay. Có thể phục hồi backup đã kiểm chứng theo quy trình vận hành.

Các test tự động dùng DB giả; không chứng minh DDL hoặc khóa cạnh tranh trên TiDB thật. Đợt sửa mã không chạy migration cloud.
