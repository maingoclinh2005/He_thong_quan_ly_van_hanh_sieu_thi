part of 'home_screen.dart';

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/banner.png',
        width: double.infinity,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => Container(
          height: 100,
          color: Colors.orange.shade50,
          alignment: Alignment.center,
          child: const Text('Banner'),
        ),
      ),
    );
  }
}

// 2. Loading Indicator ở cuối danh sách
class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

// 3. Thông báo không tìm thấy sản phẩm
class _NoProductsFound extends StatelessWidget {
  const _NoProductsFound();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24.0),
      child: Center(child: Text('Không có sản phẩm')),
    );
  }
}

// 4. Thanh kéo của Modal
