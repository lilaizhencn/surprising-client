// Native presentation against the explicit local affiliate-access-fixture.py.
// Backend permission/financial correctness is tested separately with PostgreSQL.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_scope.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/affiliate/affiliate_page.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/ui/client_theme.dart';
import 'affiliate_live_test.dart' show MemorySession, MemorySettings, waitFor;

Future<void> show(WidgetTester tester, Finder finder) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    220,
    maxScrolls: 60,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String label) async {
  final name = '${Platform.operatingSystem}-$label';
  debugPrint('AFFILIATE_ACCESS_SCREENSHOT:$name');
  await tester.runAsync(() async {
    final client = HttpClient();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:19106/__qa/ack?name=$name'),
        );
        final response = await request.close();
        final ready = response.statusCode == 200;
        await response.drain<void>();
        if (ready) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('Host screenshot was not acknowledged: $name');
    } finally {
      client.close(force: true);
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'basic referral, administrator activation, branch revocation and failure recovery',
    (tester) async {
      const config = AppConfig(
        gatewayBaseUrl: 'http://127.0.0.1:19106',
        websocketUrl: '',
      );
      const session = AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'UI QA',
          email: 'ui@qa.test',
          status: 'ACTIVE',
        ),
        accessToken: 'affiliate-access-native',
        refreshToken: 'fixture-only',
      );
      final api = ApiClient(config)..setSession(session);
      Future<void> enabled(bool value, {bool error = false}) async {
        final response = await api.post('/__qa/state', {
          'enabled': value,
          'error': error,
        });
        expect(response['enabled'], value);
        expect(response['error'], error);
      }

      final state = AppState(
        config: config,
        apiClient: api,
        initialSession: session,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      Future<void> refresh() async {
        await tester.tap(find.byTooltip('刷新'));
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<void> basic() async {
        await waitFor(
          tester,
          () =>
              find.text('邀请返佣').evaluate().isNotEmpty &&
              find.text('我的推广').evaluate().isNotEmpty,
        );
        await show(tester, find.text('我邀请的好友'));
        expect(find.textContaining('为我产生的返佣 1.25'), findsOneWidget);
        expect(find.textContaining('为我产生的返佣 0.00000001'), findsOneWidget);
        expect(find.text('KOL 合作管理'), findsNothing);
        expect(find.text('当前合作分配'), findsNothing);
        expect(find.text('调整比例'), findsNothing);
        expect(tester.takeException(), isNull);
      }

      try {
        await enabled(false);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: buildClientTheme(ClientTheme.light),
              home: const AffiliatePage(),
            ),
          ),
        );
        await basic();
        await capture(tester, 'basic-light');
        await show(tester, find.text('复制邀请链接'));
        await tester.tap(find.text('复制邀请链接'));
        await waitFor(tester, () => find.text('邀请链接已复制').evaluate().isNotEmpty);
        final copied = await tester.runAsync(
          () => Clipboard.getData(Clipboard.kTextPlain),
        );
        expect(
          copied?.text,
          'https://ex.tokdou.com/affiliate?invite=${'A' * 32}',
        );
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: buildClientTheme(ClientTheme.dark),
              home: const AffiliatePage(),
            ),
          ),
        );
        await basic();
        await capture(tester, 'basic-dark');
        await show(tester, find.widgetWithText(TextField, '邀请码或邀请链接'));
        await tester.enterText(
          find.widgetWithText(TextField, '邀请码或邀请链接'),
          'B' * 32,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看邀请'));
        await waitFor(
          tester,
          () => find.text('该邀请暂不可用，请联系邀请人。').evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '确认接受邀请'))
              .onPressed,
          isNull,
        );
        await enabled(true);
        await refresh();
        await waitFor(tester, () => find.text('邀请与合作').evaluate().isNotEmpty);
        await show(tester, find.text('调整比例'));
        await tester.tap(find.text('调整比例'));
        await show(tester, find.text('KOL 合作管理'));
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, '合作用户 UID（留空生成链接）'),
              )
              .controller!
              .text,
          '2',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '下级获得上级佣金的比例（%）'),
          '60.1234',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await capture(tester, 'kol-dark');
        await show(tester, find.text('查看贡献'));
        await tester.tap(find.text('查看贡献'));
        await waitFor(
          tester,
          () => find.text('成员 UID 2').evaluate().isNotEmpty,
        );
        await show(tester, find.text('当前合作分配'));
        await enabled(false);
        await refresh();
        await basic();
        await enabled(true);
        await refresh();
        await waitFor(tester, () => find.text('邀请与合作').evaluate().isNotEmpty);
        await show(tester, find.text('KOL 合作管理'));
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, '合作用户 UID（留空生成链接）'),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, '下级获得上级佣金的比例（%）'),
              )
              .controller!
              .text,
          '50',
        );
        await enabled(true, error: true);
        await refresh();
        await waitFor(
          tester,
          () => find.textContaining('邀请资料暂不可用').evaluate().isNotEmpty,
        );
        expect(find.text('KOL 合作管理'), findsNothing);
        await enabled(false);
        await refresh();
        await basic();
        await capture(tester, 'recovered-dark');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      }
    },
  );
}
