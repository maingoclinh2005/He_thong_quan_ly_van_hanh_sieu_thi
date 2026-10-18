# Index truy vấn — migration 0004

| Bảng | Index (thứ tự cột) |
| --- | --- |
| orders | created_at, status, customer_id |
| inventory_logs | created_at, inventory_item_id |
| products | category_id, status |
| payments | order_id, status |

Bốn index BTREE không unique, không thay đổi dữ liệu hay kết quả API.
Chỉ thêm trong migration versioned; không sửa 0001–0003, không dò schema lúc xử lý request.

## An toàn khi triển khai

Theo quy trình backup/maintenance trong [migrations.md](migrations.md).
Chạy plan offline, staging trước, sau đó mới production. Backend bản này yêu cầu 0004 applied.
DDL có thể tự commit; quá trình xây index trên bảng lớn có thể tốn dung lượng, CPU và chặn writer.
Không ép ALGORITHM/LOCK vì khả năng hỗ trợ phụ thuộc phiên bản MySQL/TiDB.
Nếu thất bại, kiểm tra log, rồi dùng resume=0004 đúng hướng qua runner; không đánh applied thủ công.

Migration kiểm tra index hiện có bằng information_schema.STATISTICS:
- Bỏ qua nếu đã có BTREE với cùng các cột đầu, đúng thứ tự tăng dần và không cắt prefix.
- Trùng tên nhưng khác định nghĩa: dừng để kiểm tra, không tự xóa/thay.
- Gắn INDEX_COMMENT migration:0004_query_indexes cho index do migration tạo.
- Down chỉ xóa đúng tên, đúng cấu trúc và đúng marker; giữ index có sẵn.
- MySQL có thể loại bỏ index FK ngầm khi tạo composite thay thế. Down dựng lại index đơn hỗ trợ category_id/order_id nếu không còn index khác hỗ trợ, rồi mới xóa composite. Những index hỗ trợ này được giữ lại sau rollback.
- Không sửa/xóa index ngoài migration trong lúc chạy. Marker và cấu trúc giúp nhận biết quyền sở hữu nhưng không thay thế kiểm soát DDL.

## Đánh giá hiệu quả trên staging

Chưa đo hiệu năng trên TiDB thật. Dùng EXPLAIN cho truy vấn thật với tham số đại diện trước/sau migration;
so sánh index được chọn, số dòng ước tính/đọc, thời gian và chi phí ghi. Không dùng FORCE INDEX để che kế hoạch kém.
Ví dụ (chỉnh mốc ngày/ID theo dữ liệu staging):

```sql
EXPLAIN SELECT order_id, created_at, status, customer_id
FROM orders
WHERE created_at >= '2026-10-01' AND created_at < '2026-11-01'
ORDER BY created_at DESC;

EXPLAIN SELECT log_id, inventory_item_id, created_at
FROM inventory_logs
WHERE created_at >= '2026-10-01' AND created_at < '2026-11-01'
ORDER BY created_at DESC;

EXPLAIN SELECT product_id FROM products
WHERE category_id = 1 AND status = 'active';

EXPLAIN SELECT payment_id FROM payments
WHERE order_id = 1 AND status = 'completed';
```

Giới hạn theo truy vấn hiện tại:
- orders(created_at, status, customer_id) ưu tiên mốc thời gian; không thay thế index customer_id-first cho lịch sử một khách. Sau range created_at, các cột sau không đảm bảo thu hẹp phạm vi seek.
- Báo cáo hiện có DATE(o.created_at) = CURDATE(): thêm index không tự biến điều kiện này thành range. Cần đo và có thể đổi sang khoảng nửa mở trong đợt tối ưu truy vấn riêng.
- inventory_logs(created_at, inventory_item_id) không tối ưu riêng truy vấn giá nhập mới nhất của một item (item_id-first). API lịch sử tồn mới đọc inventory_ledger, không hưởng index của inventory_logs.
- Danh sách products hiện lọc status nhưng không lọc category_id; không đảm bảo hưởng lợi từ composite này.
- Truy vấn payment mới nhất dùng order_id + ORDER BY payment_id; index order_id,status phục vụ lọc trạng thái nhưng không thay thế order_id,payment_id cho sắp xếp.
- Không thêm index suy đoán khác, không xóa index đơn/FK có sẵn trong đợt này. Test tự động dùng DB giả, không xác nhận hiệu năng hay tương thích DDL trên máy chủ thật.
