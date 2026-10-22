import 'support/core_snapshot_fixture.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/realtime_state.dart';

String version(int n) => '${n.toString().padLeft(19, '0')}:0000000000';
final catalog = [
  for (final p in ProductMode.values)
    Instrument.fromJson({
      'instrumentId': '${100 + p.index}',
      'symbol': 'BTC-USDT',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'settleAsset': 'USDT',
      'status': 'TRADING',
      'instrumentType': p.isSpot
          ? 'SPOT'
          : p.isOption
          ? 'OPTION'
          : p.isDelivery
          ? 'DELIVERY'
          : 'PERPETUAL',
      'contractType': p.contractType,
      'priceTickUnits': 1000000 * (p.index + 1),
      'quantityStepUnits': 10000,
      'pricePrecision': 2,
      'quantityPrecision': 4,
    }),
];
const session = AuthSession(
  user: AuthUser(userId: 1, username: 'test', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);
Map<String, dynamic> position(
  ProductMode p, {
  int quantity = 10,
  String margin = 'ISOLATED',
}) => {
  'instrumentId': '${100 + p.index}',
  'positionSide': 'LONG',
  'marginMode': margin,
  'signedQuantitySteps': quantity,
  'entryPriceTicks': 100,
  'marginAsset': 'USDT',
};
Map<String, dynamic> snapshot(ProductMode p) => completeCoreSnapshot({
  'op': 'snapshot',
  'productLine': p.productLine,
  'userId': 1,
  'data': {
    'status': 'READY',
    'snapshotVersion': version(1),
    'account': {
      'positionMode': 'HEDGE',
      'balances': [
        {'asset': 'USDT', 'availableUnits': 1000},
      ],
      'positions': [position(p)],
    },
    'openOrders': [
      {
        'instrumentId': '${100 + p.index}',
        'orderId': 20 + p.index,
        'status': 'OPEN',
        'executedQuantitySteps': 2,
      },
    ],
    'triggerOrders': [
      {
        'instrumentId': '${100 + p.index}',
        'triggerOrderId': 30 + p.index,
        'status': 'PENDING',
      },
    ],
    'positionRisks': [
      {
        'instrumentId': '${100 + p.index}',
        'positionSide': 'LONG',
        'unrealizedPnlUnits': 123 + p.index,
      },
    ],
  },
});
Map<String, dynamic> event(
  ProductMode p,
  String channel,
  int n,
  dynamic value,
) => completeCoreEvent({
  'op': 'event',
  'productLine': p.productLine,
  'userId': 1,
  'channel': channel,
  'data': {'version': version(n), 'entityId': 'user', 'value': value},
});

void main() {
  test(
    'retains all fifty snapshot levels so deltas reveal previously hidden levels',
    () async {
      final state = SelectionState();
      addTearDown(state.dispose);
      await state.selectMode(ProductMode.linear);
      void depth(int sequence, String type, List<Map<String, int>> levels) {
        state.handleRealtimeMessage({
          'op': 'event',
          'channel': 'depth',
          'productLine': 'LINEAR_PERPETUAL',
          'instrumentId': '${100 + ProductMode.linear.index}',
          'data': {
            'version': version(sequence),
            'value': {
              'updateType': type,
              'sequence': '$sequence',
              'previousSequence': '1',
              'depth': 50,
              'bids': levels,
              'asks': [],
            },
          },
        });
      }

      depth(1, 'SNAPSHOT', [
        for (var price = 1; price <= 60; price++)
          {'priceTicks': price, 'quantitySteps': 2},
      ]);
      expect(state.orderBook.bids, hasLength(50));
      depth(2, 'DELTA', [
        for (var price = 31; price <= 60; price++)
          {'priceTicks': price, 'quantitySteps': 0},
      ]);
      expect(state.orderBook.bids, hasLength(20));
      expect(state.orderBook.bids.first.priceTicks, 30);
      expect(state.orderBook.bids.last.priceTicks, 11);
    },
  );

  test(
    'an initializing realtime book does not discard loaded candles and trades',
    () async {
      final state = AppState(
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: catalog,
        apiClient: UnavailableBookApi(),
      );
      addTearDown(state.dispose);
      await state.refreshPublicData();
      expect(state.candles, hasLength(1));
      expect(state.recentTrades.single['tradeId'], 'LINEAR_PERPETUAL:1:1:1:0');
      expect(state.orderBook.bids, isEmpty);
      expect(state.realtimeLog.any((line) => line.contains('加载盘口失败')), isTrue);
    },
  );

  test(
    'bad trade history keeps the last tape and does not hide valid candles',
    () async {
      final state =
          AppState(
              config: const AppConfig(websocketUrl: ''),
              seedInstruments: catalog,
              apiClient: InvalidTradeHistoryApi(),
            )
            ..recentTrades = [
              {
                'tradeId': 'before-refresh',
                'sequence': 1,
                'price': 2,
                'quantity': '0.01',
              },
            ];
      addTearDown(state.dispose);
      await state.refreshPublicData();
      expect(state.candles, hasLength(1));
      expect(state.candles.single.close, 2);
      expect(state.recentTrades.single['tradeId'], 'before-refresh');
      expect(
        state.realtimeLog.any((line) => line.contains('最新成交的价格或数量无效')),
        isTrue,
      );
      expect(state.loadingPublic, isFalse);
    },
  );

  test(
    'depth gap only resubscribes its channel and waits for a replacement snapshot',
    () async {
      final transport = DepthProbe();
      final state = SelectionState(realtime: transport);
      addTearDown(state.dispose);
      await state.selectMode(ProductMode.linear);
      void depth(
        int n, {
        String type = 'DELTA',
        int? previous,
        int quantity = 2,
      }) {
        state.handleRealtimeMessage({
          'op': 'event',
          'channel': 'depth',
          'productLine': 'LINEAR_PERPETUAL',
          'instrumentId': '${100 + ProductMode.linear.index}',
          'data': {
            'version': version(n),
            'value': {
              'updateType': type,
              'sequence': '$n',
              'previousSequence': previous == null ? null : '$previous',
              'depth': 50,
              'bids': [
                {'priceTicks': 100, 'quantitySteps': quantity},
              ],
              'asks': [],
            },
          },
        });
      }

      depth(10, type: 'SNAPSHOT');
      depth(12, previous: 11);
      depth(13, previous: 12);
      expect(state.orderBook.sequence, 0);
      expect(state.orderBook.bids, isEmpty);
      expect(state.market.depthRecovering, isTrue);
      expect(transport.recovered, hasLength(1));
      expect(transport.recovered.single, {
        'channel': 'depth',
        'productLine': 'LINEAR_PERPETUAL',
        'instrumentId': '${100 + ProductMode.linear.index}',
      });
      depth(2, type: 'SNAPSHOT');
      depth(3, previous: 2, quantity: 0);
      expect(state.orderBook.sequence, 3);
      expect(state.orderBook.bids, isEmpty);
      depth(1, type: 'SNAPSHOT', quantity: 0);
      expect(state.orderBook.sequence, 1);
      expect(state.orderBook.bids, isEmpty);
    },
  );

  test(
    'trade tape merges reliable history with WS identities across sequence domains',
    () {
      const old = 'SPOT:9007199254740993:1:100:0';
      const current = 'SPOT:9007199254740994:1:101:0';
      const fill = 'SPOT:9007199254740994:1:101:1';
      final rows = mergeRecentTrades(
        [
          {'tradeId': old, 'sequence': 99999},
          {'tradeId': current, 'sequence': 100000, 'quantity': '0.2'},
        ],
        [
          {'tradeId': fill, 'coreSequence': '1'},
          {'tradeId': current, 'coreSequence': '1'},
        ],
      );
      expect(rows.map((r) => r['tradeId']), [fill, current, old]);
      expect(rows[1]['quantity'], '0.2');
    },
  );

  for (final cancelTrigger in [false, true]) {
    test(
      'late ${cancelTrigger ? "trigger" : "order"} cancellation cannot remove same IDs in another product',
      () async {
        final api = DeferredCancelApi();
        final state = SelectionState(initialSession: session, api: api);
        addTearDown(state.dispose);
        for (final p in [ProductMode.linear, ProductMode.option]) {
          final frame = snapshot(p);
          asMap(asList(asMap(frame['data'])['openOrders']).single)['orderId'] =
              1;
          asMap(
            asList(asMap(frame['data'])['triggerOrders']).single,
          )['triggerOrderId'] = 2;
          state.handleRealtimeMessage(frame);
        }
        await state.selectMode(ProductMode.linear);
        final pending = cancelTrigger
            ? state.cancelTriggerOrder(state.openTriggerOrders.single)
            : state.cancelOrder(state.openOrders.single);
        await Future<void>.delayed(Duration.zero);
        expect(api.products, ['LINEAR_PERPETUAL']);
        await state.selectMode(ProductMode.option);
        if (cancelTrigger) {
          api.trigger.complete(
            TriggerOrderModel.fromJson({
              ...completeCoreRow('trigger', {}),
              'userId': session.user.userId,
              'instrumentId': '101',
              'triggerOrderId': 2,
              'symbol': 'BTC-USDT',
              'status': 'CANCELED',
            }),
          );
        } else {
          api.order.complete(
            OrderModel.fromJson({
              ...completeCoreRow('order', {}),
              'orderId': 1,
              'symbol': 'BTC-USDT',
              'status': 'CANCELED',
            }),
          );
        }
        await pending;
        expect(state.tradingCommandPending, false);
        expect(api.products, ['LINEAR_PERPETUAL']);
        expect(state.openOrders.single.orderId, 1);
        expect(state.openTriggerOrders.single.triggerOrderId, 2);
      },
    );
  }
  test(
    'all product pages isolate identical symbols, positions, orders, triggers and risk pushes',
    () async {
      final state = SelectionState(initialSession: session);
      addTearDown(state.dispose);
      for (final p in ProductMode.values) {
        state.handleRealtimeMessage(snapshot(p));
      }
      for (final p in ProductMode.values) {
        await state.selectMode(p);
        expect(state.selectedInstrument.instrumentId, '${100 + p.index}');
        expect(state.positions.single.marginMode, 'ISOLATED');
        expect(state.positionRisks.single.unrealizedPnlUnits, 123 + p.index);
        expect(state.openOrders.single.orderId, 20 + p.index);
        expect(state.openOrders.single.status, 'PARTIALLY_FILLED');
        expect(state.openTriggerOrders.single.triggerOrderId, 30 + p.index);
        state.handleRealtimeMessage(
          event(p, 'accountState', 2, {
            'balances': [
              {'asset': 'USDT', 'availableUnits': 0},
            ],
          }),
        );
        expect(state.positionMode, 'HEDGE');
        expect(state.balances.single.availableUnits, 0);
        state.handleRealtimeMessage(
          event(p, 'positions', 3, {
            'positions': [position(p, margin: 'CROSS')],
          }),
        );
        expect(state.positions, hasLength(1));
        expect(state.positions.single.marginMode, 'CROSS');
        expect(state.positionRisks, hasLength(1));
        state.handleRealtimeMessage(
          event(p, 'orders', 4, {'orderId': 20 + p.index, 'status': 'FILLED'}),
        );
        state.handleRealtimeMessage(
          event(p, 'orders', 3, {'orderId': 20 + p.index, 'status': 'OPEN'}),
        );
        expect(state.openOrders, isEmpty);
        state.handleRealtimeMessage(
          event(p, 'triggerOrders', 5, [
            {
              'triggerOrderId': 30 + p.index,
              'status': 'TRIGGERING',
              'instrumentId': '${100 + p.index}',
            },
          ]),
        );
        expect(state.openTriggerOrders.single.status, 'TRIGGERING');
        state.handleRealtimeMessage(
          event(p, 'triggerOrders', 6, [
            {'triggerOrderId': 30 + p.index, 'status': 'TRIGGERED'},
          ]),
        );
        expect(state.openTriggerOrders, isEmpty);
        state.handleRealtimeMessage(
          event(p, 'positions', 7, {
            'positions': [position(p, quantity: 0)],
          }),
        );
        expect(state.positions, isEmpty);
        expect(state.positionRisks, isEmpty);
        state.handleRealtimeMessage(snapshot(p));
        expect(state.positions, isEmpty);
        expect(state.openOrders, isEmpty);
        expect(state.openTriggerOrders, isEmpty);
      }
    },
  );

  test(
    'wrong user events and late depth from another product cannot overwrite active page',
    () async {
      final state = SelectionState(initialSession: session);
      addTearDown(state.dispose);
      await state.selectMode(ProductMode.linear);
      state.handleRealtimeMessage(snapshot(ProductMode.linear));
      state.handleRealtimeMessage({
        ...event(ProductMode.linear, 'positions', 10, {
          'positions': [position(ProductMode.linear, quantity: 0)],
        }),
        'userId': 99,
      });
      expect(state.positions, hasLength(1));
      Map<String, dynamic> depth(ProductMode p, int price) => {
        'op': 'event',
        'channel': 'depth',
        'productLine': p.productLine,
        'instrumentId': '${100 + p.index}',
        'data': {
          'sequence': price,
          'bids': [
            {'priceTicks': price, 'quantitySteps': 2},
          ],
          'asks': [],
        },
      };
      state.handleRealtimeMessage(depth(ProductMode.linear, 100));
      expect(state.orderBook.bids.single.priceTicks, 100);
      state.handleRealtimeMessage(depth(ProductMode.spot, 200));
      expect(state.orderBook.bids.single.priceTicks, 100);
      await state.selectMode(ProductMode.option);
      expect(state.orderBook.bids, isEmpty);
      state.handleRealtimeMessage(depth(ProductMode.linear, 300));
      expect(state.orderBook.bids, isEmpty);
      state.handleRealtimeMessage(depth(ProductMode.option, 400));
      expect(state.orderBook.bids.single.priceTicks, 400);
    },
  );

  test(
    'closing a different position keeps current market and uses current product metadata',
    () async {
      final api = CloseApi();
      final state = SelectionState(initialSession: session, api: api);
      addTearDown(state.dispose);
      await state.selectMode(ProductMode.linear);
      state.selectedSymbol = 'ETH-USDT';
      await state.closePosition(
        Position.fromJson({
          ...position(ProductMode.linear),
          'symbol': 'BTC-USDT',
        }),
      );
      expect(state.selectedSymbol, 'ETH-USDT');
      expect(api.symbol, 'BTC-USDT');
      expect(api.product, 'LINEAR_PERPETUAL');
      expect(api.reduce, isTrue);
      expect(state.openOrders, isEmpty);
    },
  );

  test('missing positionMode in account delta preserves previous mode', () {
    final view = PrivateView()..apply(snapshot(ProductMode.linear));
    view.apply(event(ProductMode.linear, 'accountState', 2, {'balances': []}));
    expect(view.positionMode, 'HEDGE');
  });
}

class SelectionState extends AppState {
  SelectionState({
    ApiClient? api,
    RealtimeClient? realtime,
    super.initialSession,
  }) : super(
         config: const AppConfig(websocketUrl: ''),
         seedInstruments: catalog,
         apiClient: api,
         realtimeClient: realtime,
         settingsStore: _RecoverySettings(),
       );
  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshPrivateData() async {}
}

class CloseApi extends ApiClient {
  CloseApi() : super(const AppConfig());
  String? symbol, product;
  bool? reduce;
  @override
  Future<OrderModel> placeOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? bboPriceMode,
    String? productLine,
    String? clientOrderId,
  }) async {
    this.symbol = symbol;
    product = productLine;
    reduce = reduceOnly;
    return OrderModel.fromJson({
      ...completeCoreRow('order', {}),
      'orderId': 1,
      'symbol': symbol,
      'status': 'ACCEPTED',
    });
  }
}

class DeferredCancelApi extends ApiClient {
  DeferredCancelApi() : super(const AppConfig());
  final order = Completer<OrderModel>();
  final trigger = Completer<TriggerOrderModel>();
  final products = <String?>[];
  @override
  Future<OrderModel> cancelOrder(
    int userId,
    int orderId, {
    String? productLine,
  }) {
    products.add(productLine);
    return order.future;
  }

  @override
  Future<TriggerOrderModel> cancelTriggerOrder(
    int userId,
    int triggerOrderId, {
    String? productLine,
  }) {
    products.add(productLine);
    return trigger.future;
  }
}

class DepthProbe extends RealtimeClient {
  DepthProbe() : super(const AppConfig(websocketUrl: ''));
  final recovered = <Map<String, String>>[];
  @override
  void resubscribe(Map<String, String> subscription) =>
      recovered.add(subscription);
}

class UnavailableBookApi extends ApiClient {
  UnavailableBookApi() : super(const AppConfig());
  @override
  Future<OrderBook> orderBook(
    String symbol, {
    int depth = 50,
    String? productLine,
  }) async => throw StateError('MARKET_BOOK_UNAVAILABLE');
  @override
  Future<List<Candle>> candles(
    String symbol,
    String period, {
    String? productLine,
  }) async => [
    Candle.fromJson({
      'openTime': '2026-10-19T00:00:00Z',
      'openPrice': 1,
      'highPrice': 2,
      'lowPrice': 1,
      'closePrice': 2,
      'baseVolume': 3,
    }),
  ];
  @override
  Future<List<Map<String, dynamic>>> recentTrades(
    String symbol, {
    String? productLine,
  }) async => [
    {
      'tradeId': 'LINEAR_PERPETUAL:1:1:1:0',
      'sequence': 1,
      'price': 2,
      'quantity': '0.01',
    },
  ];
}

class _RecoverySettings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> next) async {
    values = {...next};
  }
}

class InvalidTradeHistoryApi extends UnavailableBookApi {
  @override
  Future<List<Map<String, dynamic>>> recentTrades(
    String symbol, {
    String? productLine,
  }) async => [
    {
      'tradeId': 'bad-history',
      'sequence': 2,
      'price': 'NaN',
      'quantity': '0.01',
    },
  ];
}
