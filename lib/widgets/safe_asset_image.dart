import 'package:flutter/material.dart';
import '../utils/product_asset_resolver.dart';

/// A finite fallback chain, including when the default asset is missing.
class SafeAssetImage extends StatelessWidget {
  const SafeAssetImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
  });
  final String path;
  final BoxFit fit;
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() =>
        const Center(child: Icon(Icons.image_not_supported_outlined));
    return Image.asset(
      path,
      fit: fit,
      width: width,
      errorBuilder: (_, error, stack) =>
          path == ProductAssetResolver.defaultProductAsset
          ? placeholder()
          : Image.asset(
              ProductAssetResolver.defaultProductAsset,
              fit: fit,
              width: width,
              errorBuilder: (_, error, stack) => placeholder(),
            ),
    );
  }
}
