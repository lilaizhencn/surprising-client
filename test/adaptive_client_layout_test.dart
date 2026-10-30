import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/ui/adaptive_client_layout.dart';
import 'package:surprising_client/src/account/kyc_status.dart';

void main() {
  testWidgets(
    'pushed detail routes and return navigation stay outside a hinge',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      const hinge = Rect.fromLTWH(590, 0, 20, 900);
      tester.view.displayFeatures = [
        const ui.DisplayFeature(
          bounds: hinge,
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetDisplayFeatures);
      final state = AppState(offline: true);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(Scaffold).last);
      expect(bounds.overlaps(hinge), false);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('交易所'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'book and tabletop regions avoid hinges while a flat crease stays usable',
    () {
      const size = Size(1000, 800);
      final book = clientDisplayPanes(size, [
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(490, 0, 20, 800),
          type: ui.DisplayFeatureType.hinge,
          state: ui.DisplayFeatureState.postureFlat,
        ),
      ]);
      expect(book, [
        const Rect.fromLTWH(0, 0, 490, 800),
        const Rect.fromLTWH(510, 0, 490, 800),
      ]);
      final tabletop = clientDisplayPanes(size, [
        const ui.DisplayFeature(
          bounds: Rect.fromLTWH(0, 400, 1000, 0),
          type: ui.DisplayFeatureType.fold,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ]);
      expect(tabletop, [
        const Rect.fromLTWH(0, 0, 1000, 400),
        const Rect.fromLTWH(0, 400, 1000, 400),
      ]);
      expect(
        clientDisplayPanes(size, [
          const ui.DisplayFeature(
            bounds: Rect.fromLTWH(500, 0, 0, 800),
            type: ui.DisplayFeatureType.fold,
            state: ui.DisplayFeatureState.postureFlat,
          ),
        ]),
        [Offset.zero & size],
      );
    },
  );

  test(
    'expiry boundaries and unknown states never advertise verified identity',
    () {
      final now = DateTime.utc(2026, 10, 29);
      expect(
        kycExpired({
          'status': 'VERIFIED',
          'expiresAt': now.toIso8601String(),
        }, now),
        true,
      );
      expect(
        kycExpired({
          'status': 'VERIFIED',
          'expiresAt': now.add(const Duration(seconds: 1)).toIso8601String(),
        }, now),
        false,
      );
      expect(kycStatusLabel({'status': 'UNKNOWN'}), '状态暂不可用');
      expect(kycStatusLabel({'status': 'REJECTED'}), contains('补正'));
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(600, 900),
    const Size(1200, 800),
  ]) {
    testWidgets('navigation adapts to $size and remains operable', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(offline: true);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(ExchangeSideNav),
        size.width >= 600 ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('交易').last);
      await tester.pumpAndSettle();
      expect(find.byType(TradePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resizing and folding preserve the active order form inputs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(offline: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('交易').last);
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(TradePage),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.first, '12345.6');
    final controller = tester.widget<TextField>(fields.first).controller!;
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(fields.first).controller, same(controller));
    expect(controller.text, '12345.6');
    tester.view.physicalSize = const Size(390, 900);
    await tester.pumpAndSettle();
    expect(controller.text, '12345.6');
    expect(tester.takeException(), isNull);
  });
}
