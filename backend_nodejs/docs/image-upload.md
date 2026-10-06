# Upload ảnh sản phẩm

POST /api/uploads/product-image yêu cầu Bearer JWT của admin hoặc employee.
Khách hàng nhận 403; request thiếu token hoặc token không hợp lệ nhận 401.
Multipart chỉ nhận một file tên image, không nhận field khác.

- JPG/JPEG, PNG, GIF, WebP; đuôi, MIME, chữ ký và định dạng giải mã phải khớp.
- Tối đa 5 MB (413 khi vượt giới hạn), 20 triệu pixel đầu vào.
- File giả, ảnh hỏng, SVG và HEIC/HEIF bị từ chối (400). Đổi HEIC/HEIF sang JPG trước khi upload.
- Server giải mã và tạo lại WebP tối đa 2048 x 2048, giữ tỷ lệ. GIF/ảnh động chỉ lấy frame đầu.
- Xóa metadata và dữ liệu chèn thêm; tên UUID do server tạo; chỉ ảnh đã xử lý được lưu.
- Tối đa 20 request/5 phút/tài khoản (429); tối đa 4 upload đang xử lý mỗi tiến trình (503).
- Bộ đếm nằm trong bộ nhớ và reset khi restart. Khi chạy nhiều instance cần shared rate-limit store.
- Response trả đường dẫn tương đối /uploads/products/<uuid>.webp để không phụ thuộc Host header.
- GET ảnh sản phẩm vẫn công khai để khách xem hàng; thêm nosniff và CSP cho file tĩnh.

Flutter gửi token và MIME đúng, kiểm tra kích thước trước khi gửi.
Chạy npm ci và npm run test:upload trong backend_nodejs. Test dùng database giả
và thư mục tạm, không truy cập TiDB hoặc sửa dữ liệu thật.
Khởi động lại backend và build/cập nhật Flutter để áp dụng cả hai đầu.
Ảnh cũ không được chuyển đổi tự động trong thay đổi này.
