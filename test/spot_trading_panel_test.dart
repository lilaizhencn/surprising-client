import 'support/authentication.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

AuthSession session(int id) => AuthSession(
  user: AuthUser(userId: id, username: 'qa-$id', email: '', status: 'ACTIVE'),
  accessToken: 'qa-$id',
  refreshToken: 'qa-$id',
);
AppState state() => _PanelState(initialSession: session(1));
void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness spot panel defaults to orders without position/risk controls',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = state();
        expect(s.accountRisk, isNull);
        addTearDown(s.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(child: PrivateTradingPanel(state: s)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final orders = find.widgetWithText(ChoiceChip, '当前委托 (0)');
        expect(tester.widget<ChoiceChip>(orders).selected, isTrue);
        expect(find.text('持仓 (0)'), findsNothing);
        expect(find.text('暂无仓位'), findsNothing);
        expect(find.text('维持保证金'), findsNothing);
        expect(find.text('保证金率'), findsNothing);
        expect(find.text('暂无委托'), findsOneWidget);
        expect(find.text('历史委托'), findsOneWidget);
        expect(find.text('成交记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('same mounted panel resets view on product and account changes', (
    tester,
  ) async {
    final s = state();
    addTearDown(s.dispose);
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PrivateTradingPanel(state: s)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show();
    final updates = find.widgetWithText(ChoiceChip, '最近订单更新');
    await tester.ensureVisible(updates);
    await tester.tap(updates);
    await tester.pumpAndSettle();
    expect(find.text('本次连接收到的最近 100 条订单更新'), findsOneWidget);
    await s.logout();
    await signInAs(s, session(2));
    await show();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '当前委托 (0)'))
          .selected,
      isTrue,
    );
    s.mode = ProductMode.linearDelivery;
    await show();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '持仓 (0)'))
          .selected,
      isTrue,
    );
    s.mode = ProductMode.spot;
    await show();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '当前委托 (0)'))
          .selected,
      isTrue,
    );
    expect(find.text('持仓 (0)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('spot login invites account and order access', (tester) async {
    final s = _PanelState();
    addTearDown(s.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PrivateTradingPanel(state: s)),
        ),
      ),
    );
    expect(find.text('登录查看账户与委托'), findsOneWidget);
    expect(find.text('登录查看持仓与委托'), findsNothing);
    expect(find.text('持仓 (0)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _PanelState extends AppState {
  _PanelState({super.initialSession})
    : super(
        apiClient: TestApiClient(),
        sessionStore: MemorySessionStore(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: fallbackInstruments(),
      ) {
    mode = ProductMode.spot;
  }
  @override
  Future<void> refreshPrivateData() async {}
}
