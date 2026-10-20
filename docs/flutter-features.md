# Flutter feature refactor — reports và các đợt tiếp theo

Đợt 2 đã chuyển catalog/kho, giỏ hàng, checkout/payment và Home. Xem [storefront-cache-checkout.md](storefront-cache-checkout.md) cho phạm vi, hàng đợi cache và giới hạn đối soát timeout.

## Phạm vi đã chuyển

Hai route cũ vẫn dùng được nhờ file export tương thích:
- lib/screens/revenue_overview_screen.dart → features/reports/presentation/revenue_overview_screen.dart
- lib/screens/product_performance_report_screen.dart → features/reports/presentation/product_performance_report_screen.dart

Screen doanh thu từ 1.635 dòng còn khoảng 970; hiệu suất từ 1.517 còn khoảng 411.
Không chỉ chia file: lấy dữ liệu, tính toán và trạng thái request đã rời khỏi State của màn hình.
Model biểu đồ/lịch là Dart thuần; widget nhận dữ liệu/callback; chi tiết sản phẩm là màn riêng.

## Quy ước áp dụng cho feature

- presentation: widget, điều hướng và trạng thái thuần giao diện như ngày được chọn trên lịch, kiểu xếp hạng.
- application: ReportController (ChangeNotifier), được cấp bằng Provider; sở hữu trạng thái tải/lỗi/dữ liệu và bộ lọc request.
- data: repository điều phối nghiệp vụ đọc; ReportSource là interface để thay thế bằng fake trong test. ApiReportSource là adapter gọi ApiService hiện có.
- domain: ReportQuery bất biến và model lịch/biểu đồ, không phụ thuộc storage hay widget.
- State của route tạo/dispose controller; ChangeNotifierProvider.value không tự sở hữu lifecycle này.
- Không thêm thư viện state management mới. AuthState hiện có vẫn dùng Provider/ChangeNotifier.

ReportController dùng snapshot loading/data/error, gộp refresh cùng request, chờ request thật khi kéo làm mới.
Đổi kỳ/tháng tạo query snapshot mới; phản hồi cũ (kể cả lỗi) không ghi đè trạng thái mới.
Dispose bỏ qua completion đến muộn. Chưa hủy HTTP vật lý; request cũ có thể hoàn thành trên mạng.

## Cache và tính đúng dữ liệu

Reports là network-only: không tự ghi/xóa cache products/orders, không lấy số liệu Hive thay thế khi API lỗi.
Chỉ adapter ApiReportSource đọc current_user_id từ settings để giữ hợp đồng API cũ; xác thực vẫn qua SessionClient/token bảo mật.
Không di chuyển token về Hive, không thay đổi cache schema.
Màn hình không gọi trực tiếp ApiService, DBService hay Hive.

Thay đổi có chủ đích:
- Lỗi API hiệu suất không fallback sang nhiều API legacy với kỳ lọc không đảm bảo tương đương. Backend hiện tại cần cung cấp endpoint dashboard.
- Lỗi tải chi tiết đơn trong báo cáo doanh thu hiển thị lỗi/thử lại, không trả báo cáo toàn thời gian dưới nhãn kỳ đang chọn.
- Báo cáo doanh thu vẫn tổng hợp từ API danh sách + chi tiết, giữ cách tính hiện hành; giới hạn tối đa 6 request chi tiết đồng thời.
- Chưa thay đổi định nghĩa doanh thu/đơn đủ điều kiện, chưa thay API báo cáo phía backend bằng truy vấn tổng hợp theo kỳ.
- Chưa có cache báo cáo offline. Nếu bổ sung, cache phải có key gồm user + quyền + bộ lọc, thời điểm cập nhật và nhãn stale rõ ràng; không dùng cache để xác nhận giao dịch.

## Lộ trình ghi nhận sau đợt 1 (đợt 2 đã triển khai bên trên)

Tại thời điểm kết thúc đợt 1, Home, thanh toán tại quầy, checkout online và các màn kho còn ở cấu trúc cũ. Đợt 2 đã chuyển các màn chính; ApiService/DBService vẫn giữ facade cho consumer chưa chuyển.
Không coi đây là hoàn tất refactor toàn bộ Flutter hoặc giải quyết tất cả race cache–API.

Thứ tự tiếp theo:
1. Catalog/inventory: repository duy nhất sở hữu API + Hive, snapshot cache chỉ đọc cho UI; đồng bộ một đầu mối, giữ idempotency chuyển kho.
2. Cart/checkout/payment: controller riêng cho trạng thái giao dịch; phân biệt API ghi đã thành công nhưng refresh cache lỗi để tránh gửi lại giao dịch.
3. Home/auth/profile: scope cache theo tài khoản, xóa cache đúng lifecycle đăng xuất; bỏ gọi syncAll từ nhiều màn hình.
4. Tách endpoint client theo feature sau khi facade cũ có đủ test; không xóa facade khi còn consumer.

Mỗi phần phải có test trước khi thay đường ghi cache. Không thêm repository chỉ bọc lời gọi rồi để screen tiếp tục tự sync.

## Kiểm thử

flutter test --no-pub
flutter analyze --no-pub lib/features/reports lib/screens/revenue_overview_screen.dart lib/screens/product_performance_report_screen.dart test/reports_feature_test.dart

Test kiểm tra race phản hồi, gộp refresh, retry, dispose, ranh giới kỳ/tháng, giới hạn đồng thời,
không fallback khi API lỗi, widget loading/error/data và route export.
Test kiến trúc chặn truy cập storage/API trực tiếp trong presentation; mỗi file reports dưới 1.000 dòng.
Chưa kiểm thử trên điện thoại thật hoặc API production. Không có migration DB trong đợt này.
