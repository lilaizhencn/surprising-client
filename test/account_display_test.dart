import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/asset_overview.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

const session = AuthSession(
  user: AuthUser(
    userId: 1,
    username: 'test',
    email: 'test@example.com',
    status: 'NORMAL',
  ),
  accessToken: 'test',
  refreshToken: 'test',
);
WalletPortfolio portfolio(double value) => WalletPortfolio.fromJson({
  'assets': [
    {
      'symbol': 'USDT',
      'availableBalance': value,
      'lockedBalance': 0,
      'totalBalance': value,
    },
  ],
});

void main() {
  test('one ready product can be valued while total remains unavailable', () {
    final s = AppState(offline: true)..session = session;
    addTearDown(s.dispose);
    s.handleRealtimeMessage({'op': 'authenticated', 'userId': 1});
    s.handleRealtimeMessage({
      'op': 'snapshot',
      'userId': 1,
      'productLine': 'LINEAR_PERPETUAL',
      'data': {
        'status': 'READY',
        'snapshotVersion': '0000000000000000001:0000000000',
        'account': {
          'balances': [
            {'asset': 'USDT', 'availableUnits': 700000000, 'lockedUnits': 0},
          ],
          'positions': [],
        },
        'openOrders': [],
        'triggerOrders': [],
        'positionRisks': [],
      },
    });
    expect(s.productBalancesUsdt(product: ProductMode.linear), 7);
    expect(s.productBalancesUsdt(), isNull);
    s.privateViews[ProductMode.linear]!.receivedAt = DateTime.now().subtract(
      const Duration(seconds: 20),
    );
    expect(s.productBalancesUsdt(product: ProductMode.linear), isNull);
  });

  test('funding balance survives a failed history endpoint', () async {
    final api = AccountApi()..failOrders = true;
    final s = AppState(apiClient: api)..session = session;
    addTearDown(s.dispose);
    final refresh = s.refreshWallet();
    api.walletRequests.single.complete(portfolio(15));
    await refresh;
    expect(s.walletReady, isTrue);
    expect(s.walletPortfolioUsdt(s.walletPortfolio), 15);
    expect(s.walletOrdersError, isNotNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'account filter, privacy and currency on small $brightness screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = AppState(offline: true)
          ..session = session
          ..walletReady = true
          ..walletPortfolio = portfolio(12);
        s.valuationRates[ValuationCurrency.cny] = 7;
        s.productBalances[ProductMode.linear] = [
          const ProductBalance(
            accountType: 'USDT_PERPETUAL',
            asset: 'USDT',
            availableUnits: 300000000,
            lockedUnits: 100000000,
            equityUnits: 500000000,
          ),
        ];
        s.valuedProducts.add(ProductMode.linear);
        s.privateViews[ProductMode.linear] = PrivateView()
          ..status = 'READY'
          ..receivedAt = DateTime.now();
        addTearDown(s.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: s,
                builder: (_, _) => SingleChildScrollView(
                  child: AssetOverview(
                    state: s,
                    onDeposit: () {},
                    onWithdraw: () {},
                    onTools: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
          '—',
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '资金账户'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
          '12.00',
        );
        await tester.tap(find.byTooltip('隐藏资产'));
        await tester.pumpAndSettle();
        expect(find.textContaining('12.0000'), findsNothing);
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
          '••••••',
        );
        await tester.tap(find.byTooltip('显示资产'));
        s.valuationCurrency = ValuationCurrency.cny;
        s.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
          '84.00',
        );
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'U本位永续'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'U本位永续'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
          '35.00',
        );
        expect(find.text('资金账户 · USDT'), findsNothing);
        expect(find.text('权益 5.0000'), findsOneWidget);
        expect(s.mode, ProductMode.linear);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'security loads outside initState, preserves MFA when KYC fails, retries',
    (tester) async {
      final api = AccountApi();
      final s = AppState(offline: true, apiClient: api)..session = session;
      addTearDown(s.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: s,
          child: const MaterialApp(home: Scaffold(body: SecuritySheet())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2FA 已启用'), findsOneWidget);
      expect(find.text('身份认证加载失败，请重试'), findsOneWidget);
      expect(find.textContaining('身份认证 KYC · 状态未获取'), findsOneWidget);
      expect(find.textContaining('已绑定'), findsOneWidget);
      expect(tester.takeException(), isNull);
      api.failKyc = false;
      await tester.tap(find.text('刷新安全状态'));
      await tester.pumpAndSettle();
      expect(find.textContaining('身份认证 KYC · APPROVED'), findsOneWidget);
      expect(find.text('身份认证加载失败，请重试'), findsNothing);
      s.session = null;
      s.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('登录已失效，请重新登录'), findsOneWidget);
      expect(find.text('2FA 已启用'), findsNothing);
    },
  );

  testWidgets('security late response cannot reveal an expired session', (
    tester,
  ) async {
    final api = AccountApi()..pendingMfa = Completer();
    final s = AppState(offline: true, apiClient: api)..session = session;
    addTearDown(s.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: s,
        child: const MaterialApp(home: Scaffold(body: SecuritySheet())),
      ),
    );
    await tester.pump();
    expect(find.text('2FA 状态未获取'), findsOneWidget);
    s.session = null;
    s.notifyListeners();
    await tester.pump();
    api.pendingMfa!.complete({'enabled': true});
    await tester.pumpAndSettle();
    expect(find.text('2FA 已启用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'wallet out of order results and post-dispose responses are ignored',
    () async {
      final api = AccountApi();
      final s = AppState(apiClient: api)..session = session;
      final old = s.refreshWallet();
      final latest = s.refreshWallet();
      api.walletRequests[1].complete(portfolio(9));
      await latest;
      api.walletRequests[0].complete(portfolio(100));
      await old;
      expect(s.walletPortfolio.totalBalance, 9);
      expect(s.walletReady, isTrue);
      final afterDispose = s.refreshWallet();
      s.dispose();
      api.walletRequests[2].complete(portfolio(500));
      await afterDispose;
      expect(s.walletPortfolio.totalBalance, 9);
    },
  );

  test(
    'currency failure clears stale rate without hiding successful currencies',
    () async {
      final s = AppState(apiClient: AccountApi());
      addTearDown(s.dispose);
      s.valuationRates[ValuationCurrency.cny] = 7;
      await s.refreshValuation();
      expect(s.valuationRates[ValuationCurrency.usd], 1.01);
      expect(s.valuationRates[ValuationCurrency.cny], isNull);
      expect(s.valuationRates[ValuationCurrency.usdt], 1);
    },
  );
}

class AccountApi extends ApiClient {
  AccountApi() : super(const AppConfig());
  bool failKyc = true;
  bool failOrders = false;
  Completer<Map<String, dynamic>>? pendingMfa;
  final walletRequests = <Completer<WalletPortfolio>>[];
  @override
  Future<Map<String, dynamic>> mfaStatus() async =>
      pendingMfa == null ? {'enabled': true} : pendingMfa!.future;
  @override
  Future<List<Map<String, dynamic>>> securityScenes() async => [];
  @override
  Future<List<Map<String, dynamic>>> apiKeys() async => [];
  @override
  Future<Map<String, dynamic>> kycStatus() async {
    if (failKyc) throw StateError('unavailable');
    return {'status': 'APPROVED'};
  }

  @override
  Future<List<Map<String, dynamic>>> kycDocuments() async => [];
  @override
  Future<List<Map<String, dynamic>>> loginVerificationMethods() async => [
    {'type': 'TOTP', 'bound': true, 'enabled': true},
  ];
  @override
  Future<Map<String, dynamic>> userSessions({String? cursor}) async => {
    'sessions': [],
    'hasMore': false,
  };
  @override
  Future<Map<String, dynamic>> loginHistory({String? cursor}) async => {
    'logs': [],
    'hasMore': false,
  };
  @override
  Future<WalletPortfolio> walletPortfolio(int userId, {bool hideZero = false}) {
    final pending = Completer<WalletPortfolio>();
    walletRequests.add(pending);
    return pending.future;
  }

  @override
  Future<List<WalletOrderRecord>> walletOrders(
    int userId, {
    int limit = 30,
  }) async {
    if (failOrders) throw StateError('unavailable');
    return [];
  }

  @override
  Future<double> exchangeRateConversion({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (toCurrency == 'CNY') throw StateError('unavailable');
    return 1.01;
  }
}
