import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/price_chart.dart';
import 'package:surprising_client/src/ui/client_theme.dart';
import 'transfer_page_test.dart' show MemorySettings;

double contrast(Color a, Color b) {
  final light = a.computeLuminance(), dark = b.computeLuminance();
  return (light > dark
      ? (light + .05) / (dark + .05)
      : (dark + .05) / (light + .05));
}

void main() {
  testWidgets(
    'guests can choose a palette from personal settings and return home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(offline: true, settingsStore: MemorySettings());
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      expect(find.text('未登录'), findsOneWidget);
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深海蓝'));
      await tester.pumpAndSettle();
      expect(state.clientTheme, ClientTheme.ocean);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .colorScheme
            .surface,
        clientColorScheme(ClientTheme.ocean).surface,
      );
      expect(find.byType(AuthSheet), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('交易所'), findsOneWidget);
      final homeMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HomePage),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        homeMaterial.color,
        clientColorScheme(ClientTheme.ocean).surfaceDim,
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'all six palettes persist a stable code and readable semantic colors',
    () {
      expect(ClientTheme.values, hasLength(6));
      final surfaces = <Color>{};
      for (final palette in ClientTheme.values) {
        expect(ClientTheme.fromCode(palette.code), palette);
        final theme = buildClientTheme(palette),
            colors = clientColorScheme(palette);
        surfaces.add(colors.surfaceDim);
        expect(
          contrast(colors.onSurface, colors.surface),
          greaterThanOrEqualTo(4.5),
          reason: palette.code,
        );
        expect(
          contrast(colors.onSurfaceVariant, colors.surface),
          greaterThanOrEqualTo(4.5),
          reason: palette.code,
        );
        expect(
          contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5),
          reason: palette.code,
        );
        expect(
          contrast(colors.error, colors.surface),
          greaterThanOrEqualTo(3),
          reason: palette.code,
        );
        expect(
          contrast(colors.tertiary, colors.surface),
          greaterThanOrEqualTo(3),
          reason: palette.code,
        );
        expect(theme.scaffoldBackgroundColor, colors.surfaceDim);
        expect(
          theme.brightness,
          palette.isLight ? Brightness.light : Brightness.dark,
        );
        expect(chartColor(colors.surface), startsWith('rgba('));
      }
      expect(surfaces, hasLength(6));
      expect(ClientTheme.fromCode('unknown'), ClientTheme.dark);
    },
  );
  test(
    'palette accents stay distinct and body text remains readable on raised surfaces',
    () {
      final accents = <Color>{};
      for (final palette in ClientTheme.values) {
        final colors = clientColorScheme(palette);
        accents.add(colors.primary);
        expect(HSVColor.fromColor(colors.primary).saturation, greaterThan(.6));
        for (final surface in [
          colors.surfaceDim,
          colors.surfaceContainerHighest,
        ]) {
          expect(
            contrast(colors.onSurface, surface),
            greaterThanOrEqualTo(4.5),
            reason: palette.code,
          );
          expect(
            contrast(colors.onSurfaceVariant, surface),
            greaterThanOrEqualTo(4.5),
            reason: palette.code,
          );
        }
      }
      expect(accents, hasLength(ClientTheme.values.length));
    },
  );
}
