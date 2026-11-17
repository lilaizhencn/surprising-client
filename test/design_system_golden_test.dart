import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/ui/client_theme.dart';
import 'package:surprising_client/src/ui/theme/design_system_gallery_page.dart';
import 'package:surprising_client/src/ui/theme/sci_fi_widgets.dart';

void main() {
  testWidgets('DesignSystemGalleryPage & SciFi widgets pixel golden', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildClientTheme(ClientTheme.dark),
        home: const SurprisingAuroraBackdrop(
          child: Column(
            children: [
              Expanded(child: DesignSystemGalleryPage()),
              Padding(
                padding: EdgeInsets.all(12),
                child: SurprisingAdlEnergyBar(level: 4),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/design_system_gallery.png'),
    );
  });
}
