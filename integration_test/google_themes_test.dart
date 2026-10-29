import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

class MemoryThemeSettings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => values;
  @override
  Future<void> write(Map<String, String> next) async {
    values = {...next};
  }
}

class GoogleQaApi extends ApiClient {
  GoogleQaApi() : super(const AppConfig());
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    Map<String, String>? query,
    bool unwrapResponseResult = false,
  }) async {
    if (path.endsWith('/google/config')) {
      return {
        'enabled': false,
        'webClientId': '',
        'iosClientId': '',
        'androidEnabled': false,
        'iosEnabled': false,
      };
    }
    if (path.endsWith('/telegram/config')) return {'enabled': false};
    return {};
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nativeCapture = bool.fromEnvironment('NATIVE_CAPTURE_HANDSHAKE');
  Future<void> capture(String name) async {
    if (!nativeCapture) {
      await binding.takeScreenshot(name);
      return;
    }
    final ack = File('${Directory.systemTemp.path}/google-theme-$name.ack');
    if (await ack.exists()) await ack.delete();
    debugPrint('NATIVE_CAPTURE_READY:$name:${ack.path}');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!await ack.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Host did not capture $name');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await ack.delete();
  }

  testWidgets(
    'native six palettes, selection, text entry, and unconfigured Google entry',
    (tester) async {
      final settings = MemoryThemeSettings();
      final state = AppState(
        offline: true,
        apiClient: GoogleQaApi(),
        settingsStore: settings,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      if (Platform.isAndroid && !nativeCapture) {
        await binding.convertFlutterSurfaceToImage();
      }
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      for (final theme in ClientTheme.values) {
        await tester.tap(find.text('主题'));
        await tester.pumpAndSettle();
        if (theme == ClientTheme.ocean) {
          await capture('native-theme-picker');
        }
        await tester.tap(find.text(theme.label).last);
        await tester.pumpAndSettle();
        expect(state.clientTheme, theme);
        expect(
          tester
              .widget<MaterialApp>(find.byType(MaterialApp))
              .theme!
              .colorScheme
              .surface,
          clientColorScheme(theme).surface,
        );
        expect(tester.takeException(), isNull);
        await capture('native-${theme.code}');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(settings.values['theme'], theme.code);
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      await tester.pumpAndSettle();
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('暖沙色').last);
      await capture('native-large-text-picker');
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('暖沙色').last);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await capture('native-home-sand');
      state.selectTheme(ClientTheme.ocean);
      await tester.pumpAndSettle();
      await capture('native-home-ocean');
      await tester.tap(find.text('行情').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PublicMarketRow).first);
      await tester.pumpAndSettle();
      final view = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      for (final theme in [ClientTheme.ocean, ClientTheme.sand]) {
        state.selectTheme(theme);
        await tester.pumpAndSettle();
        final color = clientColorScheme(theme).surface;
        final expected =
            '${(color.r * 255).round()}, ${(color.g * 255).round()}, ${(color.b * 255).round()}';
        var matched = false;
        for (var attempt = 0; attempt < 30; attempt++) {
          final background = await view.runJavaScriptReturningResult(
            'getComputedStyle(document.body).backgroundColor',
          );
          if (background.toString().contains(expected)) {
            matched = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await tester.pump();
        }
        expect(matched, isTrue, reason: 'chart theme ${theme.code}');
        await capture('native-chart-${theme.code}');
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录').last);
      await tester.pumpAndSettle();
      final google = find.byKey(const ValueKey('google-login'));
      await tester.ensureVisible(google);
      expect(tester.widget<OutlinedButton>(google).onPressed, isNull);
      expect(
        tester.widget<OutlinedButton>(google).style!.foregroundColor!.resolve({
          WidgetState.disabled,
        }),
        const Color(0xFF747775),
      );
      await capture('native-google-unconfigured');
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.tap(find.byType(TextField).first);
      await tester.enterText(
        find.byType(TextField).first,
        'long-google-user@example.com',
      );
      await tester.pumpAndSettle();
      // Test binding text input does not prove OS keyboard visibility. The
      // normal preview app is separately driven with native input and captures.
      expect(find.text('long-google-user@example.com'), findsOneWidget);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.ensureVisible(google);
      expect(tester.takeException(), isNull);
      await capture('native-auth-text-entry');
      await tester.ensureVisible(find.byTooltip('关闭').last);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      // Repeated mounting/closing exercises listener and dialog ownership.
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.text('主题'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭').last);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
