import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/affiliate/affiliate_page.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

class MemorySession implements SessionStore {
  AuthSession? session;
  @override
  Future<AuthSession?> readSession() async => session;
  @override
  Future<void> saveSession(AuthSession value) async {
    session = value;
  }

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<bool> biometricEnabled() async => false;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<bool> authenticateBiometric() async => false;
  @override
  Future<void> enableBiometric() async {}
}

class MemorySettings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => Map.of(values);
  @override
  Future<void> write(Map<String, String> input) async {
    values = Map.of(input);
  }
}

Future<void> waitFor(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for real Affiliate response');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> deviceScreenshot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  debugPrint('AFFILIATE_DEVICE_SCREENSHOT:$name');
  await tester.runAsync(() async {
    final client = HttpClient();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:19095/ack?name=$name'),
        );
        final response = await request.close();
        final ready = response.statusCode == 200;
        await response.drain<void>();
        if (ready) return;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      fail('Host did not acknowledge the real device screenshot: $name');
    } finally {
      client.close(force: true);
    }
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const gateway = String.fromEnvironment(
    'AFFILIATE_TEST_GATEWAY',
    defaultValue: 'http://127.0.0.1:19094',
  );
  const config = AppConfig(
    gatewayBaseUrl: gateway,
    websocketUrl: 'ws://127.0.0.1:19094/ws/v1',
  );
  testWidgets(
    'real Gateway registration, invitation acceptance and native team management',
    (tester) async {
      final ownerApi = ApiClient(config);
      final ownerSession = await ownerApi.login(
        username: 'affiliate-owner@qa.test',
        password: 'AffiliateQA2026!',
      );
      ownerApi.setSession(ownerSession);
      final owner = await ownerApi.get('/api/v1/affiliate/me');
      final invite = asMap(owner['profile'])['inviteCode'].toString();
      final guestApi = ApiClient(config);
      final guest = AppState(
        config: config,
        apiClient: guestApi,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      guest.pendingInvitationCode = invite;
      await tester.pumpWidget(
        AppScope(
          notifier: guest,
          child: MaterialApp(
            theme: buildClientTheme(ClientTheme.light),
            home: AffiliatePage(invitation: invite),
          ),
        ),
      );
      await waitFor(tester, () => find.text('登录或注册后接受').evaluate().isNotEmpty);
      await tester.tap(find.text('登录或注册后接受'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('没有账户，去注册'));
      await tester.tap(find.text('没有账户，去注册'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AuthSheet),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(fields.at(2)).controller!.text, invite);
      await tester.enterText(
        fields.at(0),
        'affiliate-native-${Platform.operatingSystem}-${DateTime.now().microsecondsSinceEpoch}@qa.test',
      );
      await tester.enterText(fields.at(1), 'AffiliateQA2026!');
      await tester.ensureVisible(find.text('创建账户'));
      await tester.tap(find.text('创建账户'));
      await waitFor(
        tester,
        () => guest.isLoggedIn && find.byType(AuthSheet).evaluate().isEmpty,
      );
      final memberSession = guest.session!;
      final memberId = memberSession.user.userId;
      final ownerMembers = await ownerApi.get('/api/v1/affiliate/members');
      expect(
        asList(
          ownerMembers['items'],
        ).map(asMap).any((row) => row['userId'] == '$memberId'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      guest.dispose();
      final ownerState = AppState(
        config: config,
        apiClient: ownerApi,
        initialSession: ownerSession,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      await tester.pumpWidget(
        AppScope(
          notifier: ownerState,
          child: MaterialApp(
            theme: buildClientTheme(ClientTheme.light),
            home: const AffiliatePage(),
          ),
        ),
      );
      final memberLabel = find.text('UID $memberId · 直接邀请 0 人');
      await waitFor(tester, () => find.text('我的推广').evaluate().isNotEmpty);
      await reveal(tester, memberLabel);
      final memberCard = find
          .ancestor(of: memberLabel, matching: find.byType(Column))
          .first;
      final promote = find.descendant(
        of: memberCard,
        matching: find.text('邀请成为下级'),
      );
      await tester.tap(promote);
      await tester.pump();
      final share = find.widgetWithText(TextField, '下级获得上级佣金的比例（%）');
      await reveal(tester, share);
      await tester.enterText(share, '60');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final generate = find.text('生成合作邀请');
      await reveal(tester, generate);
      await tester.tap(generate);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      final copy = find.text('复制合作邀请链接');
      await waitFor(tester, () => copy.evaluate().isNotEmpty);
      await reveal(tester, copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      final shared = await Clipboard.getData(Clipboard.kTextPlain);
      expect(
        shared?.text,
        startsWith('https://ex.tokdou.com/affiliate?invite='),
      );
      final token = Uri.parse(shared!.text!).queryParameters['invite']!;
      await deviceScreenshot(
        tester,
        'affiliate-${Platform.operatingSystem}-owner',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      ownerState.dispose();
      final memberApi = ApiClient(config)..setSession(memberSession);
      final memberState = AppState(
        config: config,
        apiClient: memberApi,
        initialSession: memberSession,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      await tester.pumpWidget(
        AppScope(
          notifier: memberState,
          child: MaterialApp(
            theme: buildClientTheme(ClientTheme.dark),
            home: AffiliatePage(invitation: token),
          ),
        ),
      );
      await waitFor(tester, () => find.text('确认接受邀请').evaluate().isNotEmpty);
      await tester.tap(find.text('确认接受邀请'));
      await waitFor(tester, () => find.text('邀请已接受').evaluate().isNotEmpty);
      final accepted = await memberApi.get('/api/v1/affiliate/me');
      expect(asList(accepted['teamPath']).map(asMap).last['sharePpm'], 600000);
      expect(asMap(accepted['profile'])['kolEnabled'], isTrue);
      await tester.pumpAndSettle();
      await deviceScreenshot(
        tester,
        'affiliate-${Platform.operatingSystem}-member-dark',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      memberState.dispose();
      final reviewApi = ApiClient(config)..setSession(ownerSession);
      final reviewState = AppState(
        config: config,
        apiClient: reviewApi,
        initialSession: ownerSession,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      await tester.pumpWidget(
        AppScope(
          notifier: reviewState,
          child: MaterialApp(
            theme: buildClientTheme(ClientTheme.light),
            home: const AffiliatePage(),
          ),
        ),
      );
      await waitFor(tester, () => find.text('我的推广').evaluate().isNotEmpty);
      await reveal(tester, memberLabel);
      final branchCard = find
          .ancestor(of: memberLabel, matching: find.byType(Column))
          .first;
      await tester.tap(
        find.descendant(of: branchCard, matching: find.text('查看贡献')),
      );
      await waitFor(
        tester,
        () => find.text('成员 UID $memberId').evaluate().isNotEmpty,
      );
      await reveal(tester, find.text('返回我的团队'));
      await tester.tap(find.text('返回我的团队'));
      await waitFor(tester, () => find.text('我的推广').evaluate().isNotEmpty);
      await reveal(tester, memberLabel);
      final editCard = find
          .ancestor(of: memberLabel, matching: find.byType(Column))
          .first;
      await tester.tap(
        find.descendant(of: editCard, matching: find.text('调整比例')),
      );
      await tester.pumpAndSettle();
      final editShare = find.widgetWithText(TextField, '下级获得上级佣金的比例（%）');
      await reveal(tester, editShare);
      await tester.enterText(editShare, '50');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('保存未来分配比例'));
      await tester.tap(find.text('保存未来分配比例'));
      await waitFor(
        tester,
        () => find.text('合作设置已保存，首次入队须对方接受').evaluate().isNotEmpty,
      );
      final changed = await reviewApi.get(
        '/api/v1/affiliate/members/$memberId',
      );
      expect(asList(changed['teamPath']).map(asMap).last['sharePpm'], 500000);
      final cleared = find.widgetWithText(TextField, '合作用户 UID（留空生成链接）');
      expect(tester.widget<TextField>(cleared).controller!.text, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      reviewState.dispose();
    },
  );
  testWidgets(
    'native deep link opens the full app and preserves registration attribution',
    (tester) async {
      final api = ApiClient(config);
      final state = AppState(
        config: config,
        apiClient: api,
        sessionStore: MemorySession(),
        settingsStore: MemorySettings(),
      );
      await tester.pumpWidget(SurprisingClientApp(state: state));
      await tester.pump(const Duration(seconds: 2));
      // The host runner opens the real OS URI after this marker; no link channel is mocked.
      debugPrint('AFFILIATE_DEEP_LINK_READY');
      await waitFor(
        tester,
        () => find.text('登录或注册后接受').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 120),
      );
      expect(state.pendingInvitationCode, matches(RegExp(r'^[A-Z0-9]{32}$')));
      await tester.tap(find.text('登录或注册后接受'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('没有账户，去注册'));
      await tester.tap(find.text('没有账户，去注册'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AuthSheet),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(fields.at(2)).controller!.text,
        state.pendingInvitationCode,
      );
      await deviceScreenshot(
        tester,
        'affiliate-${Platform.operatingSystem}-deep-link',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
}
