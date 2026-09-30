import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

String v(int value) => '${value.toString().padLeft(19, '0')}:0000000000';
Instrument instrument({String contract = 'LINEAR_PERPETUAL'}) =>
    Instrument.fromJson({
      'instrumentId': '42',
      'symbol': 'BTC-USDT',
      'contractType': contract,
      'changeId': 45,
      'notionalMultiplierUnits': 1000000,
      'priceTickUnits': 1000000,
      'pricePrecision': 2,
      'quantityStepUnits': 100000,
      'quantityPrecision': 3,
      'settleScaleUnits': 100000000,
    });
Map<String, dynamic> frame(
  String channel,
  int version,
  Object value, {
  String? period,
  String? eventTime,
}) => {
  'op': 'event',
  'channel': channel,
  'productLine': 'LINEAR_PERPETUAL',
  'instrumentId': '42',
  'userId': 1,
  'period': period,
  'eventTime': eventTime,
  'data': {'version': v(version), 'entityId': 'user', 'value': value},
};
Map<String, dynamic> position({int quantity = 2}) => {
  'instrumentId': '42',
  'positionSide': 'LONG',
  'marginMode': 'ISOLATED',
  'signedQuantitySteps': quantity,
  'entryPriceTicks': 100,
  'realizedPnlUnits': 2000000,
  'positionMarginUnits': 3000000,
  'marginAsset': 'USDT',
};
Map<String, dynamic> snapshot({bool risk = false}) => {
  'op': 'snapshot',
  'productLine': 'LINEAR_PERPETUAL',
  'userId': 1,
  'data': {
    'status': 'READY',
    'snapshotVersion': v(1),
    'account': {
      'positionMode': 'HEDGE',
      'balances': [
        {'asset': 'USDT', 'availableUnits': 100000000, 'lockedUnits': 0},
      ],
      'positions': [position()],
      'leverages': [
        {
          'instrumentId': '42',
          'marginMode': 'ISOLATED',
          'leveragePpm': 5000000,
        },
      ],
    },
    'openOrders': [],
    'triggerOrders': [],
    'positionRisks': risk
        ? [
            {
              'instrumentId': '42',
              'positionSide': 'LONG',
              'unrealizedPnlUnits': 1000000,
              'maintenanceMarginUnits': 1000000,
              'marginRatioPpm': 250000,
              'status': 'NORMAL',
            },
          ]
        : [],
  },
};
AppState state() => AppState(offline: true)
  ..instruments = [instrument()]
  ..session = const AuthSession(
    user: AuthUser(userId: 1, username: 'test', email: '', status: 'NORMAL'),
    accessToken: 'test',
    refreshToken: 'test',
  );
Map<String, dynamic> order({String status = 'OPEN', int executed = 2}) => {
  'orderId': 9007199254740993,
  'instrumentId': '42',
  'symbol': 'BTC-USDT',
  'side': 'BUY',
  'orderType': 'LIMIT',
  'timeInForce': 'GTC',
  'priceTicks': 100,
  'quantitySteps': 5,
  'executedQuantitySteps': executed,
  'remainingQuantitySteps': 5 - executed,
  'averagePriceTicks': '99.5',
  'executedValueTicks': '199',
  'cumulativeFeeUnits': -100000,
  'createdAtEpochMillis': 1790755200000,
  'updatedAtEpochMillis': 1790755260000,
  'marginMode': 'ISOLATED',
  'positionSide': 'LONG',
  'reduceOnly': true,
  'postOnly': false,
  'status': status,
};
void main() {
  testWidgets(
    'liquidation requests are fenced across product switches and restored on return',
    (tester) async {
      final api = RiskApi();
      final s = RiskState(api)
        ..session = const AuthSession(
          user: AuthUser(
            userId: 1,
            username: 'test',
            email: '',
            status: 'NORMAL',
          ),
          accessToken: 'test',
          refreshToken: 'test',
        );
      addTearDown(s.dispose);
      s.handleRealtimeMessage(snapshot());
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.pending, hasLength(1));
      await s.selectMode(ProductMode.option);
      api.pending[0].complete([
        PositionRisk.fromJson({
          'symbol': 'BTC-USDT',
          'positionSide': 'LONG',
          'liquidationPriceTicks': 50,
        }),
      ]);
      await tester.pump(const Duration(milliseconds: 250));
      expect(s.queriedPositionRisks, isEmpty);
      await s.selectMode(ProductMode.linear);
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.pending, hasLength(2));
      api.pending[1].complete([
        PositionRisk.fromJson({
          'symbol': 'BTC-USDT',
          'positionSide': 'LONG',
          'liquidationPriceTicks': 60,
        }),
      ]);
      await tester.pump(const Duration(milliseconds: 250));
      expect(s.queriedPositionRisks.single.liquidationPriceTicks, 60);
      s.handleRealtimeMessage(frame('mark', 2, {'markPriceTicks': 120}));
      s.handleRealtimeMessage(frame('mark', 3, {'markPriceTicks': 130}));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        api.pending,
        hasLength(2),
      ); // Mark ticks must not start REST polling.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'leverage editor validates range, submits ppm once and scopes the product',
    (tester) async {
      final api = LeverageApi();
      final s = AppState(offline: true, apiClient: api)
        ..session = const AuthSession(
          user: AuthUser(
            userId: 1,
            username: 'test',
            email: '',
            status: 'NORMAL',
          ),
          accessToken: 'test',
          refreshToken: 'test',
        );
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TradingLeverageSheet(
                    state: s,
                    instrument: instrument(),
                    marginMode: 'ISOLATED',
                  ),
                ),
                child: const Text('调整杠杆'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('调整杠杆'));
      await tester.pumpAndSettle();
      expect(find.text('允许范围 1–20.0×'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '21');
      await tester.tap(find.text('保存杠杆'));
      await tester.pump();
      expect(api.calls, 0);
      expect(find.text('请输入有效范围内的杠杆倍数'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '10.5');
      await tester.tap(find.text('保存杠杆'));
      await tester.pump();
      expect(api.calls, 1);
      expect(api.ppm, 10500000);
      expect(api.product, ProductMode.linear);
      expect(api.margin, 'ISOLATED');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      api.saved.complete({});
      await tester.pumpAndSettle();
      expect(find.byType(TradingLeverageSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'book aggregation rounds bids down and asks up and preserves quantities',
    () {
      final levels = [
        const OrderBookLevel(priceTicks: 101, quantitySteps: 2, orderCount: 1),
        const OrderBookLevel(priceTicks: 109, quantitySteps: 3, orderCount: 1),
        const OrderBookLevel(priceTicks: 110, quantitySteps: 4, orderCount: 1),
      ];
      final bids = aggregateBookLevels(levels, 10, bids: true);
      final asks = aggregateBookLevels(levels, 10, bids: false);
      expect(bids.map((l) => l.priceTicks), [110, 100]);
      expect(bids.map((l) => l.quantitySteps), [4, 5]);
      expect(asks.single.priceTicks, 110);
      expect(asks.single.quantitySteps, 9);
    },
  );

  testWidgets('mark push repaints PnL in an observing position card', (
    tester,
  ) async {
    final s = state();
    addTearDown(s.dispose);
    s.handleRealtimeMessage(snapshot());
    s.handleRealtimeMessage(frame('mark', 2, {'markPriceTicks': 120}));
    await tester.pumpWidget(
      AppScope(
        notifier: s,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: PositionHarness())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0.4 USDT'), findsOneWidget);
    s.handleRealtimeMessage(frame('mark', 3, {'markPriceTicks': 130}));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0.6 USDT'), findsOneWidget);
    expect(find.text('0.4 USDT'), findsNothing);
  });

  testWidgets('full book price selection fills callback and closes sheet', (
    tester,
  ) async {
    final s = state();
    addTearDown(s.dispose);
    s.orderBook = OrderBook.fromJson({
      'symbol': 'BTC-USDT',
      'sequence': 1,
      'bids': [
        {'priceTicks': 101, 'quantitySteps': 2},
      ],
      'asks': [
        {'priceTicks': 102, 'quantitySteps': 3},
      ],
    });
    String? chosen;
    await tester.pumpWidget(
      AppScope(
        notifier: s,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AppScope(
                    notifier: s,
                    child: FullOrderBookSheet(
                      onPrice: (value) => chosen = value,
                    ),
                  ),
                ),
                child: const Text('打开盘口'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开盘口'));
    await tester.pumpAndSettle();
    expect(find.text('累计 2 张'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '1.01'));
    await tester.pumpAndSettle();
    expect(chosen, '1.01');
    expect(find.byType(FullOrderBookSheet), findsNothing);
  });

  test(
    'actual core position shape without change ID reprices PnL without risk snapshot',
    () {
      final s = state();
      addTearDown(s.dispose);
      s.handleRealtimeMessage(snapshot());
      expect(s.unrealizedPnlFor(s.positions.single), isNull);
      s.handleRealtimeMessage(frame('mark', 2, {'markPriceTicks': 120}));
      expect(s.unrealizedPnlFor(s.positions.single), 40000000);
      expect(s.balances.single.equityUnits, 140000000);
      s.handleRealtimeMessage(frame('mark', 3, {'markPriceTicks': 90}));
      expect(s.unrealizedPnlFor(s.positions.single), -20000000);
      expect(s.balances.single.equityUnits, 80000000);
      s.handleRealtimeMessage(frame('mark', 2, {'markPriceTicks': 150}));
      expect(s.unrealizedPnlFor(s.positions.single), -20000000);
      expect(s.positionRisks, isEmpty); // Never fabricate other risk metrics.
      s.handleRealtimeMessage(
        frame('positions', 4, {
          'positions': [position(quantity: 0)],
        }),
      );
      s.handleRealtimeMessage(frame('mark', 5, {'markPriceTicks': 200}));
      expect(s.positions, isEmpty);
      expect(s.positionPnlUnits, isEmpty);
      expect(s.balances.single.equityUnits, 100000000);
    },
  );
  test(
    'explicit mismatched instrument revision fails closed and stale private view hides PnL',
    () {
      final s = state();
      addTearDown(s.dispose);
      s.handleRealtimeMessage(snapshot());
      s.handleRealtimeMessage(
        frame('positions', 2, {
          'positions': [
            {...position(), 'instrumentChangeId': 44},
          ],
        }),
      );
      s.handleRealtimeMessage(frame('mark', 3, {'markPriceTicks': 120}));
      expect(s.unrealizedPnlFor(s.positions.single), isNull);
      s.handleRealtimeMessage(
        frame('positions', 4, {
          'positions': [position()],
        }),
      );
      s.handleRealtimeMessage(frame('mark', 5, {'markPriceTicks': 120}));
      expect(s.unrealizedPnlFor(s.positions.single), 40000000);
      s.privateViews[ProductMode.linear]!.receivedAt = DateTime.now().subtract(
        const Duration(seconds: 16),
      );
      s.handleRealtimeMessage(frame('mark', 6, {'markPriceTicks': 130}));
      expect(s.unrealizedPnlFor(s.positions.single), isNull);
    },
  );
  test(
    'leverage deltas and bounded order history retain latest terminal update',
    () {
      final view = PrivateView()..apply(snapshot());
      expect(view.rows('leverage').single['leveragePpm'], 5000000);
      view.apply(
        frame('accountState', 2, {
          'leverages': [
            {
              'instrumentId': '42',
              'marginMode': 'ISOLATED',
              'leveragePpm': 8000000,
            },
          ],
        }),
      );
      expect(view.rows('leverage').single['leveragePpm'], 8000000);
      view.apply(frame('orders', 3, order()));
      view.apply(frame('orders', 5, order(status: 'FILLED', executed: 5)));
      view.apply(frame('orders', 4, order()));
      expect(view.rows('order'), isEmpty);
      expect(view.orderUpdates.single['status'], 'FILLED');
      for (var i = 0; i < 105; i++) {
        view.apply(frame('orders', 10 + i, {...order(), 'orderId': i}));
      }
      expect(view.orderUpdates, hasLength(100));
      expect(view.orderUpdates.first['orderId'], 104);
    },
  );
  test(
    'book snapshot sorts, bounds, clears, and rejects reversed or gapped legacy deltas',
    () {
      final s = DepthState()..instruments = [instrument()];
      addTearDown(s.dispose);
      s.handleRealtimeMessage(
        frame('depth', 1, {
          'sequence': 10,
          'levels': [
            for (var i = 1; i < 30; i++)
              {'side': 'BUY', 'priceTicks': i, 'quantitySteps': i},
            {'side': 'SELL', 'priceTicks': 32, 'quantitySteps': 2},
            {'side': 'SELL', 'priceTicks': 31, 'quantitySteps': 2},
          ],
        }),
      );
      expect(s.orderBook.bids, hasLength(20));
      expect(s.orderBook.bids.first.priceTicks, 29);
      expect(s.orderBook.asks.first.priceTicks, 31);
      s.handleRealtimeMessage(
        frame('depth', 2, {
          'updateType': 'DELTA',
          'sequence': 9,
          'previousSequence': 10,
          'bids': [
            {'priceTicks': 99, 'quantitySteps': 1},
          ],
        }),
      );
      expect(s.orderBook.sequence, 10);
      s.handleRealtimeMessage(
        frame('depth', 3, {
          'updateType': 'DELTA',
          'sequence': 11,
          'bids': [
            {'priceTicks': 99, 'quantitySteps': 1},
          ],
        }),
      );
      expect(s.refreshes, 1);
      expect(s.orderBook.sequence, 10);
      s.handleRealtimeMessage(
        frame('depth', 4, {'sequence': 12, 'levels': []}),
      );
      expect(s.orderBook.bids, isEmpty);
      expect(s.orderBook.asks, isEmpty);
      s.handleRealtimeMessage(
        frame('depth', 1, {
          'updateType': 'SNAPSHOT',
          'sequence': 1,
          'levels': [
            {'side': 'BUY', 'priceTicks': 10, 'quantitySteps': 1},
          ],
        }),
      );
      expect(s.orderBook.sequence, 1);
    },
  );
  test(
    'trade tape dedupes and orders multiple fills with identical sequence/time exactly',
    () {
      final rows = mergeRecentTrades(
        [
          {
            'tradeId': '9007199254740993',
            'sequence': 1,
            'eventTime': '2026-09-30T00:00:00Z',
          },
        ],
        [
          {
            'tradeId': '9007199254740994',
            'sequence': 1,
            'eventTime': '2026-09-30T00:00:00Z',
          },
          {
            'tradeId': '9007199254740993',
            'sequence': 1,
            'eventTime': '2026-09-30T00:00:00Z',
          },
        ],
      );
      expect(rows.map((r) => r['tradeId']), [
        '9007199254740994',
        '9007199254740993',
      ]);
      expect(tradingQuantity(instrument(contract: 'SPOT'), 12), '0.012 BTC');
      expect(tradingQuantity(instrument(), 12), '12 张');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'complete trading fields fit compact ${brightness.name} cards',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = state();
        addTearDown(s.dispose);
        s.handleRealtimeMessage(snapshot(risk: true));
        s.handleRealtimeMessage(frame('mark', 2, {'markPriceTicks': 120}));
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    OrderRow(
                      order: OrderModel.fromJson(order()),
                      instrument: instrument(),
                      onCancel: () {},
                    ),
                    PositionRow(position: s.positions.single, state: s),
                  ],
                ),
              ),
            ),
          ),
        );
        for (final label in [
          '成交均价',
          '剩余数量',
          '成交进度',
          '累计手续费',
          '委托时间',
          '更新时间',
          '订单编号',
          '标记价格',
          '杠杆',
          '持仓保证金',
          '维持保证金',
          '保证金率',
          '强平价格（快照）',
          '止盈止损',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('40.0%'), findsOneWidget);
        expect(find.text('9007199254740993'), findsOneWidget);
        expect(find.text('0.4 USDT'), findsOneWidget);
        expect(find.text('5.0×'), findsOneWidget);
        expect(find.text('-0.001 USDT'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class DepthState extends AppState {
  DepthState() : super(offline: true);
  int refreshes = 0;
  @override
  Future<void> refreshPublicData({bool silent = false}) async {
    refreshes++;
  }
}

class PositionHarness extends StatelessWidget {
  const PositionHarness({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return PositionRow(position: s.positions.single, state: s);
  }
}

class LeverageApi extends ApiClient {
  LeverageApi() : super(const AppConfig());
  int calls = 0;
  int? ppm;
  ProductMode? product;
  String? margin;
  final saved = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> leverageSetting(
    int userId,
    Instrument instrument,
    String marginMode,
  ) async => {'leveragePpm': 5000000, 'maxLeveragePpm': 20000000};
  @override
  Future<Map<String, dynamic>> updateLeverage(
    int userId,
    Instrument instrument,
    String marginMode,
    int leveragePpm,
  ) {
    calls++;
    ppm = leveragePpm;
    product = instrument.mode;
    margin = marginMode;
    return saved.future;
  }
}

class RiskApi extends ApiClient {
  RiskApi() : super(const AppConfig());
  final pending = <Completer<List<PositionRisk>>>[];
  @override
  Future<List<PositionRisk>> positionRisks(int userId, {String? productLine}) {
    final request = Completer<List<PositionRisk>>();
    pending.add(request);
    return request.future;
  }
}

class RiskState extends AppState {
  RiskState(ApiClient api)
    : super(
        config: const AppConfig(websocketUrl: ''),
        apiClient: api,
        seedInstruments: [instrument()],
      );
  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshPrivateData() async {}
}
