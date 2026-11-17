import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/ui/client_colors.dart';
import 'package:surprising_client/src/ui/client_theme.dart';
import 'package:surprising_client/src/ui/theme/design_system_gallery_page.dart';
import 'package:surprising_client/src/ui/theme/tokens.dart';

void main() {
  test('buildClientTheme attaches SurprisingTokens and unifies dark palette', () {
    final theme = buildClientTheme(ClientTheme.dark);
    final tokens = theme.extension<SurprisingTokens>();
    expect(tokens, isNotNull);
    expect(tokens!.bgVoid, const Color(0xFF05060F));
    expect(tokens.auroraCyan, const Color(0xFF00E5FF));
    expect(ClientColors.background, tokens.bgVoid);
    expect(ClientColors.primary, tokens.auroraCyan);
    expect(tokens.auroraPrimaryGradient.colors, [
      tokens.auroraCyan,
      tokens.auroraViolet,
      tokens.auroraMagenta,
    ]);
    expect(tokens.glow(0), isEmpty);
    expect(tokens.glow(2).length, 2);
  });

  testWidgets('DesignSystemGalleryPage renders all token sections cleanly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClientTheme(ClientTheme.dark),
        home: const DesignSystemGalleryPage(),
      ),
    );
    expect(find.text('1. Deep-Space Elevations (5 Levels)'), findsOneWidget);
    expect(find.text('2. Aurora Spectrum & 3 Gradients'), findsOneWidget);
    expect(find.text('3. Semantic Market Colors & Glow (0-3)'), findsOneWidget);
  });
}
