import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

void main() {
  testWidgets('RTL language choices stay on screen at 320px with larger text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = AppState(offline: true, settingsStore: _Settings())
        ..language = ClientLanguage.ar;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الإعدادات الشخصية'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.bySemanticsIdentifier('client.language.select'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsIdentifier('client.language.select'));
      await tester.pumpAndSettle();
      final english = find.text('English');
      expect(english, findsOneWidget);
      final bounds = tester.getRect(english);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(720));
      await tester.tap(english);
      await tester.pumpAndSettle();
      expect(state.language, ClientLanguage.en);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => values;
  @override
  Future<void> write(Map<String, String> next) async {
    values = next;
  }
}
