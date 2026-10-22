import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

import 'financial_boundary_test.dart' as boundary;
import 'linear_delivery_trading_test.dart' show actor;
import 'support/authentication.dart';
import 'transfer_page_test.dart' show MemorySettings;

Instrument riskInstrument({
  String asset = 'USDT',
  int? scale = 1000000,
  String? optionType,
}) => Instrument.fromJson({
  'instrumentId': '73',
  'symbol': 'RISK-$asset',
  'contractType': optionType == null ? 'LINEAR_PERPETUAL' : 'VANILLA_OPTION',
  'instrumentType': optionType == null ? 'PERPETUAL' : 'OPTION',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': asset,
  'baseScaleUnits': 100000000,
  'quoteScaleUnits': 1000000,
  'settleScaleUnits': scale,
  'priceTickUnits': 10000,
  'quantityStepUnits': 1,
  'status': 'TRADING',
  'optionType': optionType,
  if (optionType != null) 'expiryTime': '2035-01-01T00:00:00Z',
});

Map<String, dynamic> riskBody({
  int userId = 1,
  String asset = 'USDT',
  int equity = 1234567,
  int maintenance = 100000,
}) => {
  'snapshotId': 1,
  'userId': userId,
  'accountType': 'USDT_PERPETUAL',
  'settleAsset': asset,
  'walletBalanceUnits': equity,
  'unrealizedPnlUnits': 0,
  'equityUnits': equity,
  'maintenanceMarginUnits': maintenance,
  'marginRatioPpm': 100000,
  'status': 'NORMAL',
  'eventTime': DateTime.now().toUtc().toIso8601String(),
};

class RiskApi extends TestApiClient {
  RiskApi() : super(const AppConfig(websocketUrl: ''));
  final reads =
      <({int? userId, String? product, Map<String, String>? query})>[];
  Map<String, dynamic> Function()? reply;
  Completer<Map<String, dynamic>>? held;
  bool unavailable = false;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    if (path != '/api/v1/gateway/risk/account/latest') {
      throw StateError('Unexpected endpoint $path');
    }
    reads.add((userId: userId, product: productLine, query: query));
    final waiting = held;
    held = null;
    if (waiting != null) return waiting.future;
    if (unavailable) throw ApiException(503, 'risk unavailable');
    return reply?.call() ??
        riskBody(userId: userId!, asset: query!['settleAsset']!);
  }

  @override
  Future<List<LiquidationOrder>> liquidationOrders(
    int userId, {
    String? productLine,
  }) async => [];
}

class RiskState extends AppState {
  RiskState(RiskApi api, Instrument instrument)
    : super(
        apiClient: api,
        initialSession: actor,
        settingsStore: MemorySettings(),
        sessionStore: MemorySessionStore(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [instrument],
      ) {
    mode = instrument.mode;
  }
  @override
  Future<void> refreshWallet() async {}
  @override
  Future<void> refreshPortfolioIncome() async {}
  @override
  Future<void> refreshBalanceScales() async {}
  @override
  Future<void> refreshOrderTerms() async {}
  @override
  Future<void> refreshAlgoOrders() async {}
  bool closed = false;
  @override
  void dispose() {
    if (closed) return;
    closed = true;
    super.dispose();
  }
}

void acceptRiskAccount(AppState state, {int sequence = 1}) {
  state.handleRealtimeMessage({'op': 'authenticated', 'userId': state.userId});
  state.handleRealtimeMessage(
    boundary.snapshot(sequence)
      ..['userId'] = state.userId
      ..['productLine'] = state.mode.productLine,
  );
}

Widget riskPage(AppState state) => AppScope(
  notifier: state,
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Builder(
          builder: (context) =>
              PrivateTradingPanel(state: AppScope.of(context)),
        ),
      ),
    ),
  ),
);

void main() {
  for (final (
        asset,
        scale,
        equity,
        maintenance,
        expectedEquity,
        expectedMaintenance,
      )
      in [
        ('USDT', 1000000, 1234567, 100000, '1.234567 USDT', '0.1 USDT'),
        ('BTC', 100000000, 123456789, 1000000, '1.23456789 BTC', '0.01 BTC'),
        ('UNKNOWN', null, 1234567, 100000, '--', '--'),
      ]) {
    testWidgets(
      'private refresh loads real risk endpoint and $asset units reach the card',
      (tester) async {
        final api = RiskApi()
          ..reply = () =>
              riskBody(asset: asset, equity: equity, maintenance: maintenance);
        final state = RiskState(
          api,
          riskInstrument(asset: asset, scale: scale),
        );
        addTearDown(state.dispose);
        acceptRiskAccount(state);
        await state.refreshPrivateData();
        expect(api.reads, hasLength(1));
        expect(api.reads.single.userId, 1);
        expect(api.reads.single.product, 'LINEAR_PERPETUAL');
        expect(api.reads.single.query, {
          'userId': '1',
          'settleAsset': asset,
          'accountType': 'USDT_PERPETUAL',
        });
        expect(state.accountRisk, isNotNull);
        await tester.pumpWidget(riskPage(state));
        final values = tester.widgetList<MetricPill>(find.byType(MetricPill));
        expect(
          values.firstWhere((item) => item.label == '权益').value,
          expectedEquity,
        );
        expect(
          values.firstWhere((item) => item.label == '维持保证金').value,
          expectedMaintenance,
        );
        expect(tester.takeException(), isNull);
        state.dispose();
      },
    );
  }

  testWidgets(
    'bad risk reads are unavailable and explicit refresh restores the real card',
    (tester) async {
      final api = RiskApi()..unavailable = true;
      final state = RiskState(api, riskInstrument());
      addTearDown(state.dispose);
      acceptRiskAccount(state);
      await state.refreshRiskDetails();
      await tester.pumpWidget(riskPage(state));
      expect(find.textContaining('账户风险暂不可用'), findsOneWidget);
      expect(find.byType(MetricPill), findsNothing);
      api.unavailable = false;
      await tester.tap(find.text('刷新风险'));
      await tester.pumpAndSettle();
      expect(state.accountRisk, isNotNull);
      expect(find.text('1.234567 USDT'), findsOneWidget);
      state.handleRealtimeMessage({
        'op': 'event',
        'channel': 'accountState',
        'userId': 1,
        'productLine': 'LINEAR_PERPETUAL',
        'data': {'version': 'bad'},
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(state.accountRisk, isNull);
      expect(find.text('1.234567 USDT'), findsNothing);
      expect(find.text('账户风险等待账户同步'), findsOneWidget);
      state.dispose();
    },
  );

  testWidgets(
    'a delayed risk response cannot cross an actual account login transition',
    (tester) async {
      final api = RiskApi();
      final state = RiskState(api, riskInstrument());
      addTearDown(state.dispose);
      acceptRiskAccount(state);
      final old = Completer<Map<String, dynamic>>();
      api.held = old;
      final loading = state.refreshRiskDetails();
      await tester.pump();
      await state.logout();
      final other = AuthSession(
        user: const AuthUser(
          userId: 2,
          username: 'other',
          email: '',
          status: 'ACTIVE',
        ),
        accessToken: 'other-access',
        refreshToken: 'other-refresh',
      );
      await signInAs(state, other);
      acceptRiskAccount(state, sequence: 2);
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNotNull);
      final current = state.accountRisk;
      old.complete(riskBody());
      await loading;
      expect(state.session, same(other));
      expect(state.accountRisk, same(current));
      expect(tester.takeException(), isNull);
      state.dispose();
    },
  );

  testWidgets(
    'risk expires locally even while a new private baseline is fresh',
    (tester) async {
      final api = RiskApi();
      final state = RiskState(api, riskInstrument());
      addTearDown(state.dispose);
      acceptRiskAccount(state);
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNotNull);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 16)),
      );
      state.handleRealtimeMessage(
        boundary.snapshot(2)
          ..['userId'] = 1
          ..['productLine'] = 'LINEAR_PERPETUAL',
      );
      expect(state.privateViews[ProductMode.linear]!.ready, isTrue);
      expect(state.accountRisk, isNull);
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNotNull);
      state.mode = ProductMode.spot;
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNull);
      expect(api.reads, hasLength(2));
      state.dispose();
    },
  );

  for (final patch in <Map<String, dynamic>>[
    {'userId': 2},
    {'accountType': 'COIN_PERPETUAL'},
    {'settleAsset': 'BTC'},
    {'equityUnits': 'NaN'},
    {'maintenanceMarginUnits': -1},
    {'marginRatioPpm': '1.5'},
    {
      'eventTime': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String(),
    },
    {
      'eventTime': DateTime.now()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    },
    {'status': 'UNKNOWN'},
  ]) {
    test(
      'invalid account risk identity, freshness or units fail closed: $patch',
      () async {
        final api = RiskApi()..reply = () => {...riskBody(), ...patch};
        addTearDown(api.dispose);
        expect(
          await api.accountRisk(
            1,
            'USDT',
            accountType: 'USDT_PERPETUAL',
            productLine: 'LINEAR_PERPETUAL',
          ),
          isNull,
        );
      },
    );
  }

  for (final (type, label) in [
    ('CALL', '看涨 CALL'),
    ('PUT', '看跌 PUT'),
    ('UNKNOWN', '--'),
  ]) {
    testWidgets(
      'option lifecycle states its contract type $type without relying on symbol',
      (tester) async {
        final instrument = riskInstrument(optionType: type);
        final state = RiskState(RiskApi(), instrument);
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProductLifecyclePanel(
                  state: state,
                  instrument: instrument,
                  latestPrice: null,
                ),
              ),
            ),
          ),
        );
        final chip = tester.widget<LifecycleChip>(
          find.byWidgetPredicate(
            (w) => w is LifecycleChip && w.label == '期权类型',
          ),
        );
        expect(chip.value, label);
        expect(tester.takeException(), isNull);
        state.dispose();
      },
    );
  }
}
