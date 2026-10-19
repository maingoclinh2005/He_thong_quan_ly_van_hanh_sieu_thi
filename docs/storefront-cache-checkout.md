# Flutter đợt 2 — catalog, kho, giỏ hàng, checkout, Home

## Cấu trúc

- core/data/cache_coordinator.dart: hàng đợi chung cho fetch → cache và API ghi → cache.
- features/catalog/data: nguồn đồng bộ products, inventory, users, orders, history và các thao tác sản phẩm/kho.
- features/catalog/application: CatalogController (ChangeNotifier) cho snapshot và refresh.
- features/cart: CartRepository và CartController; draft UI do controller sở hữu, persist dùng bản sao.
- features/checkout: CheckoutController, CheckoutRepository, SubmissionGuard và màn checkout/online/payment.
- features/home: màn Home, tách helper giao diện ảnh/điều hướng/widget thành part riêng.
- Các đường dẫn screens cũ là export tương thích. DBService còn facade cho consumer cũ; không tạo nguồn cache thứ hai.

Cùng mô hình ChangeNotifier đã có ở reports/auth. AnimatedBuilder lắng nghe controller; setState còn dùng cho trạng thái form, dialog và lựa chọn thuần UI.
Các part giao diện dùng chung private state của màn hình, không phải module nghiệp vụ độc lập.
Voucher/điểm thưởng và một số màn quản trị ngoài phạm vi này vẫn còn adapter legacy; chưa tuyên bố toàn bộ app không còn ApiService/DBService trực tiếp.

## Quy tắc đồng bộ

1. Gộp yêu cầu refresh trùng đang chạy. Thao tác API/cache được xếp hàng để fetch cũ không ghi đè mutation mới.
2. Một mutation làm thay đổi revision: refresh sau mutation không được tham gia request trước mutation.
3. Snapshot server rỗng là thật: bỏ dòng cache thừa, không tự seed sản phẩm demo trong chế độ production.
4. putAll trước deleteAll, không clear rồi ghi từng dòng tạo trạng thái trắng tạm thời. Đây KHÔNG phải transaction Hive qua nhiều box.
5. API đã xác nhận ghi thành công: lỗi cache được lưu trong coordinator.errors và hiện banner; không biến thành thất bại giao dịch.
6. Phiên xác định bằng TokenStore.generation + user ID. Request chờ từ phiên cũ bị chặn; kết quả về muộn không ghi sang cache phiên mới.
7. Logout xếp việc xóa cache sau tác vụ đang chạy. Hộp chưa mở cũng được xóa trên đĩa để hỗ trợ migration auth lúc khởi động.
8. ApiService/SessionClient vẫn chịu trách nhiệm HTTP, xác thực, refresh token. Không thay đổi token storage.

Hàng đợi là phạm vi một process Flutter, không khóa nhiều thiết bị hoặc server.
Cache có thể lỗi từng phần; banner yêu cầu đồng bộ lại. Không dùng cache tồn kho làm quyết định cuối cùng, server vẫn kiểm tra ledger/transaction.
Một request đọc dài có thể trì hoãn tác vụ sau; chi tiết đơn được tải tối đa 6 request song song để giới hạn áp lực.
Một số consumer cũ vẫn đọc Hive trực tiếp, nên không đảm bảo snapshot nhiều bảng nguyên tử cho mọi màn.

## Kho và catalog

- Tạo mặt hàng với tồn đầu kỳ dùng một API create có ledger opening, không create rồi import bằng hai request.
- Sửa mặt hàng kho gửi số kiểm kê trong một API update, không update rồi adjust lần nữa.
- Chuyển kho giữ request_key qua retry. Khóa mới có user ID; khóa pending cũ được dùng lại khi nâng cấp, tránh gửi mới một thao tác chưa rõ kết quả.
- API chuyển kho đã có idempotency backend. API nhập kho và các API ghi khác chưa có cơ chế này đầy đủ: timeout mạng vẫn cần đối soát, không cam kết exactly-once.
- Đồng bộ sau nhập/kiểm kê/chuyển kho là best-effort và có cảnh báo. Lỗi đồng bộ không khiến màn hình báo thao tác API đã thành công là thất bại.

## Giỏ hàng và đơn hàng

- Server trả giỏ rỗng thì cache cũng rỗng. Không upload lại giỏ cũ khi đơn đã tiêu thụ giỏ server.
- Save giỏ xếp hàng với snapshot riêng, tránh request cũ ghi đè draft mới. Load về muộn không đè draft người dùng đã sửa.
- Online checkout flush giỏ trước khi tạo đơn; không flush lại khi đang có marker checkout chưa giải quyết.
- CheckoutController gộp double tap và giữ Order trả từ server, không tìm lại kết quả từ cache bằng transactionId.
- QR quay lại vẫn dùng đơn pending đã tạo và số tiền của đơn đó. UI chỉ đánh dấu paid khi response server xác nhận paid/completed/success.
- Kéo/làm mới cache không tạo lại đơn. Consumer cũ gọi saveOrder nay cũng nhận Order từ server.

## Kết quả chưa rõ và đối soát

SubmissionGuard ghi pending_checkout_USER_ID trước khi POST. Không lưu token trong marker.
- HTTP 4xx từ server được coi là từ chối: xóa marker, cho phép sửa và thử lại.
- Có Order xác nhận: giữ receipt order_id, cache thành công thì xóa marker.
- Timeout, mất kết nối, response hỏng hoặc lỗi 5xx: giữ marker, chặn POST tiếp theo kể cả khi đóng/mở app.
- Marker có order_id thì đọc lại đơn, KHÔNG tạo đơn khác.
- Không có order_id thì cần đối soát với quản trị viên. Chưa có màn hình đối soát tự động; không tự xóa marker theo timeout hay khi logout.
- Sau khi đối chiếu server và chắc chắn không có đơn, người vận hành mới được xóa đúng marker của tài khoản trên thiết bị.
  Nếu đã có đơn, ghi đúng order_id để phục hồi; không xóa toàn bộ settings/token/các marker khác.
- Đây là biện pháp chặn gửi lại mù, KHÔNG phải idempotency giao dịch phía backend. Nếu xóa dữ liệu app hoặc gửi từ thiết bị khác, marker không bảo vệ được.
- Có marker xác nhận cũ nhưng cache hỏng: phục hồi đơn cũ trước khi bắt đầu đơn mới. Không tự suy đoán giao dịch mới dựa trên giỏ giống nhau.

## Kiểm thử và triển khai

flutter test --no-pub
flutter analyze --no-pub lib/core lib/features lib/services/api_service.dart lib/services/db_service.dart lib/screens/edit_inventory_item_screen.dart test/storefront_state_test.dart test/storefront_widgets_test.dart

Test có: queue/dedup/revision, cache failure sau remote success, đổi phiên/logout, Hive snapshot rỗng, cart race/retry,
checkout double tap, timeout, receipt recovery, dispose, widget Home/checkout/payment và export route cũ.
Không chạy API ghi lên production hoặc migration DB. Chưa test trên điện thoại thật.
Trước phát hành: staging smoke test nhập/kiểm kê/chuyển kho, cash, QR quay lại, VNPay, mất mạng, logout khi đang sync và đổi tài khoản.
