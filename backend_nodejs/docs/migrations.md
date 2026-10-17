# Migration có phiên bản

## Schema chuẩn của bản này

- `users.password_hash` là nguồn mật khẩu duy nhất. Không còn đọc/ghi `users.password`; đăng nhập không chấp nhận plaintext.
- `orders.status` là trạng thái đơn duy nhất: pending, confirmed, shipping, completed, rejected. `payment_status` vẫn riêng vì trạng thái thanh toán khác trạng thái giao hàng.
- `order_status` đầu vào cũ còn được chuyển đổi ở adapter nghiệp vụ; không lưu hai cột. Flutter đã bỏ field trùng khỏi payload tạo đơn.
- API không truy vấn information_schema hay bỏ qua cột thiếu. Backend chỉ mở cổng nếu ledger có 0001 và 0002 ở trạng thái applied. Không tự chạy DDL lúc khởi động.

## Các phiên bản

- **0001_baseline**: xác nhận cài đặt hiện hữu đã có các cột/bảng mà runtime yêu cầu. Chỉ ghi nhận baseline sau khi kiểm tra thành công. Không bịa lịch sử thực thi cho SQL cũ và không tạo lại database.
- **0002_canonical_columns**: preflight toàn bộ người dùng/đơn hàng trước khi ghi; chuyển mật khẩu cũ sang bcrypt khi cần; chuẩn hóa trạng thái; bỏ hai cột cũ. Nếu hai nguồn mâu thuẫn hoặc trạng thái lạ, dừng và yêu cầu người triển khai đối soát. Không tự chọn trạng thái hoàn thành thay cho chờ xác nhận.

`database/migrations/*.sql` là lịch sử bootstrap trước khi có ledger, không nằm trong hàng đợi versioned. Cài đặt cũ thiếu schema phải hoàn tất các bước legacy còn thiếu trên staging trước khi nhận baseline. Database mới: bootstrap bằng schema hiện có và migration auth sessions, sau đó kiểm tra baseline; đây chưa phải công cụ tạo database rỗng một lệnh. Không chạy `database_reset.sql` lên dữ liệu thật.

Mỗi thay đổi mới thêm một file `database/versioned/NNNN_name.js` có `up`, `down`. Không sửa phiên bản đã triển khai. SHA-256 (chuẩn hóa CRLF/LF) được kiểm tra khi chạy status/up/down; sửa file hoặc xuất hiện phiên bản không biết sẽ bị chặn. Khi thêm phiên bản, cập nhật gate `src/schema-version.js` và test cho bản phát hành mới.

## Quy trình triển khai (PowerShell, trong backend_nodejs)

1. Chạy test; backup database bằng công cụ của nhà cung cấp và thử phục hồi trên staging. Ghi lại mã bản backup và commit triển khai trong hệ thống vận hành.
2. `npm run migrate:plan` chỉ đọc danh mục local, **không kết nối DB**. `npm run migrate:status` đọc ledger của DB được cấu hình, không tự sửa schema.
3. Trên staging, dừng **tất cả** backend/worker/cron/webhook writer, không chỉ một process. Các cờ bên dưới là xác nhận của người vận hành, không phải khóa chặn mọi client DB.
4. Đặt `$env:MIGRATION_ACTOR = 'ten-nguoi-trien-khai/ma-release'`.
5. Chạy `npm run migrate:up -- --maintenance --backup-confirmed`.
6. Kiểm tra status và event log, chạy smoke test đăng nhập/refresh, tạo đơn, thanh toán, lịch ca. Chỉ sau khi staging đạt mới lặp lại trên production trong maintenance window.
7. Khởi động backend bản mới. Bản này không được chạy trước migration; bản cũ không được tiếp tục ghi sau khi drop cột.

Không log SQL thô, bind parameters, password/hash, OTP hay chuỗi kết nối. `schema_migrations` lưu version/checksum/trạng thái/hướng/thời gian; `schema_migration_events` lưu run ID, actor, từng bước bắt đầu/kết thúc và mã lỗi. Bảo vệ quyền đọc/ghi các bảng này; tài khoản runtime không cần quyền DDL.

## Khi chạy dở

Người dùng có mật khẩu legacy được chuyển sang hash mới có thể phải đăng nhập lại vì session gắn với fingerprint credential. Session của tài khoản có hash không đổi vẫn được giữ nguyên.

DDL MySQL/TiDB có thể tự commit. Không hứa rollback transaction sẽ khôi phục schema. Bước thất bại để lại ledger failed (mất process có thể để running); lần up tiếp theo **không tự chạy lại**.

Sau khi kiểm tra schema, log và xử lý nguyên nhân, tiếp tục đúng phiên bản/hướng:

`npm run migrate:up -- --maintenance --backup-confirmed --resume=0002`

Các bước 0002 được thiết kế chạy lại sau DDL dở: kiểm tra sự tồn tại cột chỉ diễn ra trong migration. Không sửa checksum hay đánh applied bằng tay để bỏ qua lỗi.

Khóa `schema_migration_lock` dùng INSERT khóa chính, không phụ thuộc GET_LOCK của MySQL và không bị DDL commit giải phóng. Không tự hết hạn/chiếm khóa. Nếu process chết, xác nhận process cũ đã dừng, đọc owner trong bảng rồi chạy:

`node scripts/migrate.js unlock --maintenance --backup-confirmed --owner=UUID-CHINH-XAC`

Unlock không xóa ledger lỗi. Sau đó vẫn phải dùng resume đúng hướng. Không unlock khi runner khác còn chạy.

## Rollback

Dừng writer, backup mới, rồi:

`npm run migrate:down -- --maintenance --backup-confirmed`

Chỉ rollback phiên bản applied cao nhất (0002); baseline không có down phá dữ liệu. Sau down, deploy lại mã nguồn trước đợt này. Backend mới từ chối khởi động khi 0002 rolled_back.

Down tái tạo `users.password` từ hash hiện tại và `orders.order_status` từ status hiện tại, bao gồm tài khoản/đơn tạo sau up. Không ghi đè bằng snapshot cũ và không phục hồi plaintext. Đây là rollback tương thích ứng dụng, **không phải phục hồi chính xác mọi byte/giá trị legacy**; cột phục hồi cho phép NULL. Muốn khôi phục dữ liệu/DDL nguyên trạng phải dùng backup đã kiểm chứng.

Nếu down lỗi, kiểm tra và chạy lại với `--resume=0002` cùng lệnh down. Nếu up lỗi, hoàn tất resume up rồi down; không đổi hướng giữa một migration dở. Tình huống không thể hoàn tất cần phục hồi backup có kiểm soát.

## Kiểm thử và giới hạn

`npm run test:migrations` dùng DB giả kiểm tra checksum, thứ tự, khóa, interruption/resume, conflict trước ghi, up/down/re-up và dữ liệu mới sau triển khai. `npm test` kiểm tra toàn bộ backend; test kiến trúc cấm schema probing trong src.

Các test giả không thay thế chạy DDL trên MySQL/TiDB staging đúng phiên bản. Đợt sửa mã này không chạy migration hay thay đổi database cloud.
