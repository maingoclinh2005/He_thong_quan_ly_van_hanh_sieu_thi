part of 'home_screen.dart';

extension _HomeNavigation on _HomeScreenState {
  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProfileSection(), // Tách Profile Section
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: _buildDrawerMenuItems(), // Tách Menu Items
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tách Menu Items
  List<Widget> _buildDrawerMenuItems() {
    // Hàm helper để tạo item menu đồng bộ với thiết kế của ProfileViewScreen
    Widget buildMenuItem({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Khối bọc icon màu xanh nhạt tương tự _infoRow
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF2F855A), size: 22),
                ),
                const SizedBox(width: 14),
                // Tiêu đề của mục menu
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Mũi tên điều hướng nhỏ ở góc phải
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black26,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Khởi tạo item mặc định dành cho tất cả mọi người
    final List<Widget> items = [
      buildMenuItem(
        icon: Icons.lock_outline,
        title: 'Thông tin bảo mật',
        onTap: () async {
          Navigator.of(context).pop(); // Đóng Drawer
          if (!await _requireLogin(
            message: 'Vui lòng đăng nhập để xem thông tin bảo mật',
          )) {
            return;
          }
          if (!mounted) return;
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SecurityInfoScreen()));
        },
      ),
    ];

    // Nếu là ADMIN
    if (widget.role == 'admin') {
      items.insertAll(0, [
        buildMenuItem(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Xem doanh thu và lợi nhuận',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RevenueOverviewScreen()),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.bar_chart_outlined,
          title: 'Xem báo cáo hiệu suất sản phẩm',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProductPerformanceReportScreen(),
              ),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.schedule_outlined,
          title: 'Quản lý ca làm',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkShiftManagementScreen(role: widget.role),
              ),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.groups_outlined,
          title: 'Quản lý khách hàng',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CustomerManagementScreen(),
              ),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.card_giftcard_outlined,
          title: 'Quản lý mã khuyến mãi',
          onTap: () {
            Navigator.of(context).pop();
            const token = '';
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AdminVouchersScreen(token: token.toString()),
              ),
            );
          },
        ),
      ]);
    }
    // Nếu là EMPLOYEE
    else if (widget.role == 'employee') {
      items.insertAll(0, [
        buildMenuItem(
          icon: Icons.schedule_outlined,
          title: 'Ca làm của tôi',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkShiftManagementScreen(role: widget.role),
              ),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.receipt_long_outlined,
          title: 'Lịch sử',
          onTap: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              buildSlidePageRoute(OrderManagementScreen(role: widget.role)),
            );
          },
        ),
        buildMenuItem(
          icon: Icons.inventory_2_outlined,
          title: 'Quản lý sản phẩm',
          onTap: () async {
            Navigator.of(context).pop();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ProductManagementScreen(),
              ),
            );
            if (!mounted) return;
            _redraw(() {});
          },
        ),
        buildMenuItem(
          icon: Icons.inventory,
          title: 'Quản lý kho hàng',
          onTap: () async {
            Navigator.of(context).pop();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const InventoryManagementScreen(),
              ),
            );
            if (!mounted) return;
            _redraw(() {});
          },
        ),
      ]);
    }

    return items;
  }

  // Tách Profile Section trong Drawer
  Widget _buildProfileSection() {
    return GestureDetector(
      onTap: () async {
        Navigator.of(context).pop();
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để vào tài khoản',
        )) {
          return;
        }
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => buildProfileScreenForRole(widget.role),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black12, width: 6),
                ),
                child: const Center(
                  child: Icon(Icons.person_outline, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thông tin cá nhân',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Divider(),
          ],
        ),
      ),
    );
  }

  // Tách App Bar Title (Search Bar)
  // Tách App Bar Title (Search Bar)
  Widget _buildSearchBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: TextField(
        controller: _searchController, // Gắn controller
        decoration: InputDecoration(
          hintText: 'Tìm sản phẩm',
          prefixIcon: const Icon(Icons.search, color: Colors.black45),
          // Nút xoá (chỉ hiện khi có chữ)
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.black45),
                  onPressed: () {
                    _searchController
                        .clear(); // Xoá chữ và gọi _onSearchChanged
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 8,
          ),
        ),
      ),
    );
  }
}
