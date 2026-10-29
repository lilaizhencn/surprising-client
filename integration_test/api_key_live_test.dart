import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/account/api_key_edit_dialog.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.testTextInput.register();
  const token = String.fromEnvironment('OPEN_PLATFORM_QA_TOKEN');
  const gateway = String.fromEnvironment(
    'OPEN_PLATFORM_QA_GATEWAY',
    defaultValue: 'http://127.0.0.1:19084',
  );
  testWidgets('device edits a PostgreSQL-backed Key through the real Gateway', (
    tester,
  ) async {
    expect(
      token,
      isNotEmpty,
      reason: 'Use the owned loopback OpenPlatformBrowserQaTest fixture',
    );
    final api = ApiClient(const AppConfig(gatewayBaseUrl: gateway));
    api.setSession(
      AuthSession.fromJson({
        'accessToken': token,
        'refreshToken': '',
        'user': {
          'userId': 7,
          'username': 'openplatformqa',
          'email': '',
          'status': 'NORMAL',
        },
      }),
    );
    final created = await api.createApiKey(
      label: 'device-${Platform.operatingSystem}',
      permissions: ['READ'],
      ipAllowlist: [],
      emailCode: '123456',
      totpCode: '',
    );
    final key = asMap(created['apiKey']);
    addTearDown(() async {
      try {
        await api.revokeApiKey(
          apiKey: asString(key['apiKey']),
          emailCode: '123456',
          totpCode: '',
        );
      } finally {
        api.dispose();
      }
    });
    for (final theme in [ClientTheme.light, ClientTheme.dark]) {
      bool? saved;
      final current = (await api.apiKeys()).firstWhere(
        (row) => row['apiKey'] == key['apiKey'],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildClientTheme(theme),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    saved = await showDialog<bool>(
                      context: context,
                      builder: (_) => ApiKeyEditDialog(
                        apiKey: current,
                        mfaRequired: false,
                        onSendCode: () async {
                          await api.issueSecurityChallenge('SECURITY_SETTINGS');
                        },
                        onSave: (settings) => api.updateApiKey(
                          apiKey: asString(key['apiKey']),
                          label: settings.label,
                          permissions: settings.permissions,
                          ipAllowlist: settings.ipAllowlist,
                          emailCode: settings.emailCode,
                          totpCode: settings.totpCode,
                        ),
                      ),
                    );
                  },
                  child: const Text('编辑密钥'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑密钥'));
      await tester.pumpAndSettle();
      Finder input(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.enterText(
        input('名称'),
        'edited-${Platform.operatingSystem}-${theme.name}',
      );
      await tester.enterText(input('IP 白名单'), '127.0.0.1, 127.0.0.1');
      await tester.ensureVisible(find.text('允许交易'));
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile).first,
      );
      if (!toggle.value) {
        await tester.tap(find.text('允许交易'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(input('邮箱验证码'), '000000');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pump();
      final rejectedDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (find.text('处理中…').evaluate().isNotEmpty &&
          DateTime.now().isBefore(rejectedDeadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('编辑 API 密钥'), findsOneWidget);
      expect(saved, isNull);
      debugPrint(
        'OPEN_PLATFORM_CAPTURE:${Platform.operatingSystem}-${theme.name}',
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.ensureVisible(input('邮箱验证码'));
      await tester.pumpAndSettle();
      await tester.enterText(input('邮箱验证码'), '123456');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('邮箱验证码')).controller!.text,
        '123456',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (saved == null && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (saved != true) {
        debugPrint('OPEN_PLATFORM_CAPTURE:${Platform.operatingSystem}-failure');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      expect(saved, isTrue);
      final stored = (await api.apiKeys()).firstWhere(
        (row) => row['apiKey'] == key['apiKey'],
      );
      expect(
        stored['label'],
        'edited-${Platform.operatingSystem}-${theme.name}',
      );
      expect(stored['permissions'], 'READ,TRADE');
      expect(stored['ipAllowlist'], ['127.0.0.1']);
      expect(tester.takeException(), isNull);
    }
  });
}
