part of 'home_screen.dart';

extension _HomeImages on _HomeScreenState {
  String _imageFor(Product p) {
    final resolvedAsset = ProductAssetResolver.forProduct(p);
    if (resolvedAsset != ProductAssetResolver.defaultProductAsset) {
      return resolvedAsset;
    }

    final id = p.id.toLowerCase();
    final name = p.name.toLowerCase();
    final barcode = (p.barcode ?? '').toLowerCase();
    final sku = barcode.isNotEmpty ? barcode : id;
    const assetBySku = {
      'prod001': 'assets/images/chuoi.png',
      'prod002': 'assets/images/dautay.jpg',
      'prod003': 'assets/images/tao.png',
      'prod004': 'assets/images/dua.jpg',
      'prod005': 'assets/images/duahau.jpg',
      'prod006': 'assets/images/xotthaixatac.jpg',
      'prod007': 'assets/images/XotBBQ.png',
      'prod008': 'assets/images/muoiotchanh.png',
      'prod009': 'assets/images/xotkimquat.jpg',
      'prod010': 'assets/images/sottrungmuoi.png',
      'prod011': 'assets/images/trathtruetea.jpg',
      'prod012': 'assets/images/tradaohatchia.jpg',
      'prod013': 'assets/images/C2.jpg',
      'prod014': 'assets/images/trahoanhai.png',
      'prod015': 'assets/images/trachanhmatong.jpg',
    };
    final assetByProductCode = assetBySku[sku];
    if (assetByProductCode != null) return assetByProductCode;

    bool anyContains(List<String> needles) {
      for (final n in needles) {
        if (id.contains(n) || name.contains(n) || barcode.contains(n)) {
          return true;
        }
      }
      return false;
    }

    if (anyContains(['banana', 'chuoi', 'chuối'])) {
      return 'assets/images/chuoi.png';
    }
    if (anyContains(['apple', 'tao', 'táo'])) {
      return 'assets/images/tao.png';
    }
    if (anyContains(['coke', 'coca'])) {
      return 'assets/images/nuoccoca.png';
    }
    if (anyContains(['diet_coke', 'diet'])) {
      return 'assets/images/dietcoca.png';
    }
    if (anyContains(['tomato', 'cachua', 'càchua', 'cà chua'])) {
      return 'assets/images/cachua.png';
    }
    if (anyContains([
      'brocoli',
      'broccoli',
      'bongcai',
      'bôngcải',
      'bông cải',
    ])) {
      return 'assets/images/bongcai.png';
    }

    // Luôn có ảnh fallback để tránh hiển thị icon trống
    if (anyContains(['bia', 'saigon', 'sai gon', 'bia sai gon'])) {
      return 'assets/images/biasaigon.jpg';
    }
    if (anyContains(['c2', 'tra xanh c2', 'trÃ  xanh c2'])) {
      return 'assets/images/C2.jpg';
    }
    if (anyContains(['dau tay', 'dautay', 'dÃ¢u tÃ¢y'])) {
      return 'assets/images/dautay.jpg';
    }
    if (anyContains(['dua', 'dá»©a'])) {
      return 'assets/images/dua.jpg';
    }
    if (anyContains(['dua hau', 'duahau', 'dÆ°a háº¥u'])) {
      return 'assets/images/duahau.jpg';
    }
    if (anyContains(['muoi ot chanh', 'muoiotchanh', 'muá»‘i á»›t chanh'])) {
      return 'assets/images/muoiotchanh.png';
    }
    if (anyContains(['nuoc cam', 'nuoccam', 'nÆ°á»›c cam'])) {
      return 'assets/products/nuoc_cam.jpg';
    }
    if (anyContains(['nuoc loc', 'nuoc suoi', 'nÆ°á»›c lá»c'])) {
      return 'assets/products/lavie.jpg';
    }
    if (anyContains([
      'sot trung muoi',
      'sottrungmuoi',
      'sá»‘t trá»©ng muá»‘i',
    ])) {
      return 'assets/images/sottrungmuoi.png';
    }
    if (anyContains(['sua tuoi', 'suatuoi', 'sá»¯a tÆ°Æ¡i'])) {
      return 'assets/images/suatuoi.jpg';
    }
    if (anyContains([
      'tra chanh mat ong',
      'trachanhmatong',
      'trÃ  chanh máº­t ong',
    ])) {
      return 'assets/images/trachanhmatong.jpg';
    }
    if (anyContains([
      'tra dao hat chia',
      'tradaohatchia',
      'trÃ  Ä‘Ã o háº¡t chia',
    ])) {
      return 'assets/images/tradaohatchia.jpg';
    }
    if (anyContains(['tra hoa nhai', 'trahoanhai', 'trÃ  hoa nhÃ i'])) {
      return 'assets/images/trahoanhai.png';
    }
    if (anyContains(['true tea', 'truetea', 'trathtruetea'])) {
      return 'assets/images/trathtruetea.jpg';
    }
    if (anyContains(['xot bbq', 'xotbbq', 'bbq'])) {
      return 'assets/images/XotBBQ.png';
    }
    if (anyContains(['xot kim quat', 'xotkimquat', 'kim quat'])) {
      return 'assets/images/xotkimquat.jpg';
    }
    if (anyContains(['xot thai xa tac', 'xotthaixatac', 'thai xa tac'])) {
      return 'assets/images/xotthaixatac.jpg';
    }

    return ProductAssetResolver.defaultProductAsset;
  }

  Widget _buildProductImage(Product p) {
    // Nguồn ảnh có thể là:
    // - URL (backend trả về) -> Image.network
    // - Path local (inventory) -> Image.file
    // - Không có -> Image.asset fallback
    final stored = (DBService.productImages().get(p.id) ?? p.imageUrl ?? '')
        .toString();
    if (stored.trim().startsWith('assets/')) {
      return Image.asset(
        stored.trim(),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (c, e, s) => Image.asset(
          _imageFor(p),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }
    if (stored.isNotEmpty && stored.startsWith('http')) {
      return Image.network(
        stored,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (c, e, s) => Image.asset(
          _imageFor(p),
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      );
    }

    if (stored.isNotEmpty) {
      try {
        final file = File(stored);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (c, e, s) => Image.asset(
              _imageFor(p),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          );
        }
      } catch (_) {
        // fallthrough
      }
    }

    return Image.asset(
      _imageFor(p),
      fit: BoxFit.cover,
      width: double.infinity,
      errorBuilder: (c, e, s) => Container(
        color: Colors.grey.shade100,
        child: Image.asset(
          ProductAssetResolver.defaultProductAsset,
          fit: BoxFit.cover,
          width: double.infinity,
        ),
      ),
    );
  }
}
