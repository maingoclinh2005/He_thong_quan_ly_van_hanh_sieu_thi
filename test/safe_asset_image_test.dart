import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sieuthimini/widgets/safe_asset_image.dart';
import 'package:sieuthimini/utils/product_asset_resolver.dart';

class MissingAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw FlutterError('Missing: $key');
}

void main() {
  testWidgets('missing product image uses bundled default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SafeAssetImage('assets/images/thit_heo.jpg')),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final image = tester.widgetList<Image>(find.byType(Image)).last;
    expect(
      (image.image as AssetImage).assetName,
      ProductAssetResolver.defaultProductAsset,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing default terminates in icon, not another failing image', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultAssetBundle(
          bundle: MissingAssets(),
          child: const SafeAssetImage('missing.jpg'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
