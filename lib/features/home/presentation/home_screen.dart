import 'package:sieuthimini/features/catalog/application/catalog_controller.dart';
import 'package:sieuthimini/features/catalog/presentation/cache_sync_banner.dart';
import 'package:sieuthimini/features/cart/application/cart_controller.dart';
import 'package:flutter/material.dart';
import 'package:sieuthimini/services/token_store.dart';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:sieuthimini/services/auth_state.dart';
import 'package:sieuthimini/services/db_service.dart';
import 'package:sieuthimini/models/product.dart';
import 'package:sieuthimini/screens/profile_route.dart';
import 'package:sieuthimini/screens/checkout_screen.dart';
import 'package:sieuthimini/screens/customer_online_checkout_screen.dart';
import 'package:sieuthimini/screens/customer_vouchers_screen.dart';
import 'package:sieuthimini/screens/revenue_overview_screen.dart'; // Đã thêm
import 'package:sieuthimini/screens/product_management_screen.dart';
import 'package:sieuthimini/screens/inventory_management_screen.dart';
import 'package:sieuthimini/screens/employee.dart';
import 'package:sieuthimini/screens/employee_confirm_orders_screen.dart';
import 'package:sieuthimini/screens/work_shift_management_screen.dart';
import 'package:sieuthimini/screens/customer_management_screen.dart';
import 'package:sieuthimini/screens/orders_screen.dart';
import 'package:sieuthimini/screens/order_management_screen.dart';
import 'package:sieuthimini/screens/product_performance_report_screen.dart';
import 'package:sieuthimini/screens/scan_product_screen.dart';
import 'package:sieuthimini/screens/security_info_screen.dart';
import 'package:sieuthimini/screens/admin_vouchers_screen.dart';
import 'package:sieuthimini/screens/login_screen.dart';
import 'package:sieuthimini/widgets/role_bottom_navigation_bar.dart';
import 'package:sieuthimini/widgets/product_list_card.dart';
import 'package:sieuthimini/widgets/slide_page_route.dart';
import 'package:sieuthimini/screens/product_detail_screen.dart';
import 'package:sieuthimini/utils/product_asset_resolver.dart';
import 'package:sieuthimini/utils/product_stock_utils.dart';

part 'home_images.dart';
part 'home_navigation.dart';
part 'home_cart_sheet.dart';

enum HomeFilterOption { bestSeller, priceAsc, priceDesc, inStockOnly }

// --- WIDGET CHÍNH ---
class HomeScreen extends StatefulWidget {
  final String role;
  final VoidCallback onLogout;

  final CatalogController? catalog;
  const HomeScreen({
    super.key,
    required this.role,
    required this.onLogout,
    this.catalog,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _redraw(VoidCallback update) {
    if (mounted) setState(update);
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final CatalogController _catalog;
  late final CartController _cartState;
  Map<String, int> get _cart => _cartState.items;
  String? _currentUserEmail;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = _allCategoryLabel;
  HomeFilterOption _filterOption = HomeFilterOption.bestSeller;
  RoleBottomTab _currentBottomTab = RoleBottomTab.home;
  // *** INFINITE SCROLL LOGIC ***
  final ScrollController _scrollController = ScrollController();
  final int _productsPerPage = 6;
  int _loadedProductCount = 6;
  bool _isLoadingMore = false;
  // *****************************

  static const Color _primaryGreen = Color(0xFF1B7F4D);
  static const Color _surface = Color(0xFFF6F7F9);
  static const String _allCategoryLabel = 'Tất cả';

  bool get _isGuest =>
      !TokenStore.instance.hasSession || DBService.currentUserId() == null;

  Future<bool> _requireLogin({
    String message = 'Vui lòng đăng nhập để tiếp tục',
  }) async {
    if (!_isGuest) return true;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    final auth = Provider.of<AuthState>(context, listen: false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          closeOnLogin: true,
          onLogin: (role) => auth.login(role),
        ),
      ),
    );
    if (!mounted) return false;
    await _loadCurrentUserCart();
    return !_isGuest;
  }

  // Mapping sản phẩm sang đường dẫn ảnh asset (fallback khi không có ảnh từ backend)
  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog ?? CatalogController();
    _cartState = CartController(
      loadCart: () async {
        final email = DBService.currentUserEmail();
        return email == null
            ? <String, int>{}
            : DBService.loadCartForCurrentUser(email);
      },
      saveCart: (cart) async {
        final email = DBService.currentUserEmail();
        if (email != null) await DBService.saveCartForUser(email, cart);
      },
    )..addListener(_controllerChanged);
    _catalog.refresh();
    _selectedCategory = _allCategoryLabel;
    _loadCurrentUserCart();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cartState.dispose();
    _catalog.dispose();
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // Hàm tải giỏ hàng người dùng
  Future<void> _loadCurrentUserCart() async {
    _currentUserEmail = DBService.currentUserEmail();
    await _cartState.load();
  }

  Future<void> _persistCart() => _cartState.persist();

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _loadMoreProducts();
    }
  }

  void _loadMoreProducts() {
    if (_isLoadingMore) {
      return;
    }

    final allItems = _catalog.products.toList().cast<Product>();

    if (_loadedProductCount >= allItems.length) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    // Giả lập độ trễ tải
    Future.delayed(const Duration(milliseconds: 1000), () {
      setState(() {
        _loadedProductCount += _productsPerPage;
        _isLoadingMore = false;
      });
    });
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      _loadedProductCount = _productsPerPage;
    });
  }

  String _categoryOf(Product product) {
    final explicitLabel = (product.categoryName ?? '').trim();
    if (explicitLabel.isNotEmpty) {
      return explicitLabel;
    }
    final explicit = explicitLabel.toLowerCase();
    if (explicit.contains('trái') || explicit.contains('hoa quả')) {
      return 'Trái cây';
    }
    if (explicit.contains('đồ uống') || explicit.contains('nuoc')) {
      return 'Đồ uống';
    }
    if (explicit.contains('gia vị') || explicit.contains('xốt')) {
      return 'Gia vị';
    }

    final name = product.name.toLowerCase();
    final barcode = (product.barcode ?? '').toLowerCase();
    final hint = '$name $barcode';
    if (hint.contains('chuối') ||
        hint.contains('chuoi') ||
        hint.contains('dâu') ||
        hint.contains('tao') ||
        hint.contains('táo') ||
        hint.contains('dứa') ||
        hint.contains('dua hau') ||
        hint.contains('dưa hấu')) {
      return 'Trái cây';
    }
    if (hint.contains('trà') ||
        hint.contains('tea') ||
        hint.contains('coca') ||
        hint.contains('pepsi') ||
        hint.contains('c2') ||
        hint.contains('lipton')) {
      return 'Đồ uống';
    }
    if (hint.contains('xốt') ||
        hint.contains('muối') ||
        hint.contains('bbq') ||
        hint.contains('kim quất')) {
      return 'Gia vị';
    }
    return 'Khác';
  }

  List<String> _categoryFilterOptions() {
    final names = <String>{};

    for (final product in _catalog.products) {
      final name = _categoryOf(product).trim();
      if (name.isNotEmpty && name != _allCategoryLabel) {
        names.add(name);
      }
    }

    final ordered = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [_allCategoryLabel, ...ordered];
  }

  List<Product> _applyFilters(List<Product> items) {
    Iterable<Product> result = items.where((p) => p.isActive);

    if (_selectedCategory != _allCategoryLabel) {
      result = result.where((p) => _categoryOf(p) == _selectedCategory);
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      result = result.where((product) {
        final name = product.name.toLowerCase();
        final barcode = (product.barcode ?? '').toLowerCase();
        return name.contains(q) || barcode.contains(q);
      });
    }

    final list = result.toList();
    switch (_filterOption) {
      case HomeFilterOption.bestSeller:
        // Không có dữ liệu bán chạy riêng, dùng tồn kho thấp hơn làm tín hiệu bán chạy.
        list.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
        break;
      case HomeFilterOption.priceAsc:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case HomeFilterOption.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case HomeFilterOption.inStockOnly:
        list.removeWhere((p) => p.stockQuantity <= 0);
        break;
    }
    return list;
  }

  String _formatVnd(double amount) {
    final value = amount.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      if (i > 0 && (value.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(value[i]);
    }
    return '${buffer.toString()} VNĐ';
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<HomeFilterOption>(
          groupValue: _filterOption,
          onChanged: (v) {
            if (v == null) {
              return;
            }
            setState(() => _filterOption = v);
            Navigator.pop(ctx);
          },
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('Bộ lọc sản phẩm')),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.bestSeller,
                title: Text('Bán chạy'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.priceAsc,
                title: Text('Giá thấp đến cao'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.priceDesc,
                title: Text('Giá cao đến thấp'),
              ),
              RadioListTile<HomeFilterOption>(
                value: HomeFilterOption.inStockOnly,
                title: Text('Còn hàng'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HÀM TÁCH WIDGET ---

  // Tách Widget Drawer
  void _openProductDetail(Product p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(
          product: p,
          assetFallback: _imageFor,
          onAddToCart: (product, quantity) async {
            await _addToCart(product, quantity: quantity, showSnack: false);
          },
          onBuyNow: (product, quantity) async {
            final added = await _addToCart(
              product,
              quantity: quantity,
              showSnack: false,
            );
            if (!added) return;
            if (!mounted) return;
            await _openCheckoutScreen();
          },
        ),
      ),
    );
  }

  Widget _buildProductCard(Product p) {
    return ProductListCard(
      product: p,
      categoryLabel: _categoryOf(p),
      priceText: _formatVnd(p.price),
      image: _buildProductImage(p),
      onOpenDetail: () => _openProductDetail(p),
      onAddToCart: () => _addToCart(p),
    );
  }

  Future<bool> _addToCart(
    Product p, {
    int quantity = 1,
    bool showSnack = true,
  }) async {
    if (quantity <= 0) return false;
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để thêm sản phẩm vào giỏ hàng',
    );
    if (!loggedIn) return false;
    if (!mounted) return false;
    if (!ProductStockUtils.canPurchase(p)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sản phẩm "${p.name}" đã hết hàng')),
      );
      return false;
    }

    final current = _cart[p.id] ?? 0;
    if (current + quantity > p.stockQuantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Chỉ còn ${p.stockQuantity} ${p.unit}, không thể thêm thêm ${p.name}.',
          ),
        ),
      );
      return false;
    }

    setState(() {
      _cart.update(p.id, (v) => v + quantity, ifAbsent: () => quantity);
    });
    Future.microtask(() => _persistCart());
    if (showSnack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm ${p.name} vào giỏ hàng'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
    return true;
  }

  Future<void> _scanAndAddToCart() async {
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để quét và thêm sản phẩm',
    );
    if (!mounted) return;
    if (!loggedIn) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    final product = await Navigator.of(
      context,
    ).push<Product?>(buildSlidePageRoute(const ScanProductScreen()));
    if (product == null || !mounted) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    try {
      final updatedCart = await DBService.addProductToCurrentCart(product);
      if (!mounted) return;
      setState(() {
        _cart
          ..clear()
          ..addAll(updatedCart);
        _currentBottomTab = RoleBottomTab.cart;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã thêm ${product.name} vào giỏ hàng')),
      );
      await _openCheckoutScreen();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _currentBottomTab = RoleBottomTab.home);
    }
  }

  Future<void> _openCheckoutScreen() async {
    final loggedIn = await _requireLogin(
      message: 'Vui lòng đăng nhập để xem giỏ hàng',
    );
    if (!mounted) return;
    if (!loggedIn) {
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Giỏ hàng đang trống')));
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    final allProducts = DBService.getAllProducts();
    final validIds = allProducts.map((product) => product.id).toSet();
    _cart.removeWhere((productId, quantity) {
      return quantity <= 0 || !validIds.contains(productId);
    });
    if (_cart.isEmpty) {
      await _persistCart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy sản phẩm trong giỏ hàng')),
      );
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    await _persistCart();
    if (!mounted) return;
    if (widget.role == 'customer') {
      await Navigator.of(context).push(
        buildSlidePageRoute(
          CustomerOnlineCheckoutScreen(
            cart: Map.from(_cart),
            onCheckoutComplete: () async {
              setState(() => _cart.clear());
              await _persistCart();
            },
          ),
        ),
      );
      if (!mounted) return;
      final email = _currentUserEmail;
      if (email != null) {
        final saved = DBService.getCartForUser(email);
        setState(() {
          _cart
            ..clear()
            ..addAll(saved);
        });
      }
      setState(() => _currentBottomTab = RoleBottomTab.home);
      return;
    }

    await Navigator.of(context).push(
      buildSlidePageRoute(
        CheckoutScreen(
          cart: Map.from(_cart),
          role: widget.role,
          onCheckoutComplete: () async {
            setState(() => _cart.clear());
            await _persistCart();
          },
        ),
      ),
    );
    if (!mounted) return;
    final email = _currentUserEmail;
    if (email != null) {
      final saved = DBService.getCartForUser(email);
      setState(() {
        _cart
          ..clear()
          ..addAll(saved);
      });
    }
    setState(() => _currentBottomTab = RoleBottomTab.home);
  }

  void _handleBottomTab(RoleBottomTab tab) async {
    switch (tab) {
      case RoleBottomTab.home:
        setState(() => _currentBottomTab = tab);
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
        break;
      case RoleBottomTab.employees:
        setState(() => _currentBottomTab = tab);
        Navigator.of(context).push(
          buildSlidePageRoute(EmployeeManagementScreen(role: widget.role)),
        );
        break;
      case RoleBottomTab.scan:
        setState(() => _currentBottomTab = tab);
        await _scanAndAddToCart();
        break;
      case RoleBottomTab.invoices:
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(OrderManagementScreen(role: widget.role)));
        break;
      case RoleBottomTab.confirmOrders:
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const EmployeeConfirmOrdersScreen()));
        break;
      case RoleBottomTab.offers:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để xem ưu đãi của bạn',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(const CustomerVouchersScreen()));
        break;
      case RoleBottomTab.cart:
        if (_currentBottomTab != RoleBottomTab.cart) {
          setState(() => _currentBottomTab = RoleBottomTab.cart);
        }
        await _openCheckoutScreen();
        break;
      case RoleBottomTab.orders:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để xem đơn hàng',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case RoleBottomTab.account:
        if (!await _requireLogin(
          message: 'Vui lòng đăng nhập để vào tài khoản',
        )) {
          if (!mounted) return;
          setState(() => _currentBottomTab = RoleBottomTab.home);
          return;
        }
        if (!mounted) return;
        setState(() => _currentBottomTab = tab);
        Navigator.of(
          context,
        ).push(buildSlidePageRoute(buildProfileScreenForRole(widget.role)));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _surface,
      drawer: _buildDrawer(), // Sử dụng Widget đã tách
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: _buildSearchBar(), // Sử dụng Widget đã tách
        actions: [
          if (_isGuest)
            IconButton(
              onPressed: () =>
                  _requireLogin(message: 'Vui lòng đăng nhập để vào tài khoản'),
              icon: const Icon(Icons.login, color: Colors.black87),
              tooltip: 'Đăng nhập',
            )
          else
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout, color: Colors.black87),
              tooltip: 'Đăng xuất',
            ),
        ],
      ),

      // LOẠI BỎ SingleChildScrollView
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CacheSyncBanner(),
            if (_cartState.error != null)
              ListTile(
                title: const Text('Chưa lưu được giỏ hàng'),
                trailing: TextButton(
                  onPressed: _persistCart,
                  child: const Text('Thử lại'),
                ),
              ),
            // Promo banner (Image)
            const _PromoBanner(), // Tách thành Widget riêng
            const SizedBox(height: 18),

            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sản phẩm',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                AnimatedBuilder(
                  animation: _catalog,
                  builder: (context, _) {
                    final total = _applyFilters(_catalog.products).length;
                    return Text(
                      '$total mặt hàng',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _categoryFilterOptions()
                          .map(
                            (category) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category),
                                selected: _selectedCategory == category,
                                selectedColor: _primaryGreen.withValues(
                                  alpha: 0.14,
                                ),
                                labelStyle: TextStyle(
                                  color: _selectedCategory == category
                                      ? _primaryGreen
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                side: BorderSide(
                                  color: _selectedCategory == category
                                      ? _primaryGreen.withValues(alpha: 0.35)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSelected: (_) {
                                  setState(() {
                                    _selectedCategory = category;
                                    _loadedProductCount = _productsPerPage;
                                  });
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _openFilterSheet,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Bộ lọc',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Danh sách sản phẩm (Đã thêm Expanded cho Infinite Scrolling)
            Expanded(
              child: AnimatedBuilder(
                animation: _catalog,
                builder: (context, _) {
                  final allItems = _catalog.products;
                  final filteredItems = _applyFilters(allItems);

                  // 2. ✅ SỬA LỖI Ở ĐÂY: Gán kết quả cho biến
                  final itemsToShow = filteredItems
                      .take(_loadedProductCount)
                      .toList();
                  final hasMore = filteredItems.length > itemsToShow.length;

                  // 3. Kiểm tra danh sách rỗng
                  if (itemsToShow.isEmpty) {
                    if (_searchQuery.isNotEmpty ||
                        _selectedCategory != 'Tất cả') {
                      return const Center(
                        child: Text('Không tìm thấy sản phẩm nào.'),
                      );
                    }
                    return const _NoProductsFound();
                  }

                  // 4. Trả về GridView
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1000
                          ? 5
                          : width >= 760
                          ? 4
                          : width >= 520
                          ? 3
                          : 2;
                      return GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.70,
                        ),
                        itemCount: itemsToShow.length + (hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == itemsToShow.length && hasMore) {
                            return const _LoadingFooter();
                          }

                          final Product p = itemsToShow[index];
                          return _buildProductCard(p);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: null,
      bottomNavigationBar: RoleBottomNavigationBar(
        role: widget.role,
        currentTab: _currentBottomTab,
        onTabSelected: _handleBottomTab,
      ),
    );
  }

  // Tách Cart Sheet
  // ignore: unused_element
}
