import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

String version(int n) => '${n.toString().padLeft(19, '0')}:0000000000';
final catalog = [
  for (final p in ProductMode.values)
    Instrument.fromJson({
      'instrumentId': '${100 + p.index}',
      'symbol': 'BTC-USDT',
      'instrumentType': p.isSpot
          ? 'SPOT'
          : p.isOption
          ? 'OPTION'
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
Map<String, dynamic> snapshot(ProductMode p) => {
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
};
Map<String, dynamic> event(
  ProductMode p,
  String channel,
  int n,
  dynamic value,
) => {
  'op': 'event',
  'productLine': p.productLine,
  'userId': 1,
  'channel': channel,
  'data': {'version': version(n), 'entityId': 'user', 'value': value},
};

void main() {
  test(
    'late cancellation responses cannot remove same IDs in another product',
    () async {
      final api = DeferredCancelApi();
      final state = SelectionState(api: api)..session = session;
      addTearDown(state.dispose);
      for (final p in [ProductMode.linear, ProductMode.option]) {
        final frame = snapshot(p);
        final data = asMap(frame['data']);
        asMap(asList(data['openOrders']).single)['orderId'] = 1;
        asMap(asList(data['triggerOrders']).single)['triggerOrderId'] = 2;
        state.handleRealtimeMessage(frame);
      }
      await state.selectMode(ProductMode.linear);
      final order = state.cancelOrder(state.openOrders.single);
      final trigger = state.cancelTriggerOrder(state.openTriggerOrders.single);
      await state.selectMode(ProductMode.option);
      api.order.complete(
        OrderModel.fromJson({
          'orderId': 1,
          'symbol': 'BTC-USDT',
          'status': 'CANCELLED',
        }),
      );
      api.trigger.complete(
        TriggerOrderModel.fromJson({
          'triggerOrderId': 2,
          'symbol': 'BTC-USDT',
          'status': 'CANCELLED',
        }),
      );
      await Future.wait([order, trigger]);
      expect(api.products, ['LINEAR_PERPETUAL', 'LINEAR_PERPETUAL']);
      expect(state.openOrders.single.orderId, 1);
      expect(state.openTriggerOrders.single.triggerOrderId, 2);
    },
  );
  test(
    'all product pages isolate identical symbols, positions, orders, triggers and risk pushes',
    () async {
      final state = SelectionState()..session = session;
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
      final state = SelectionState()..session = session;
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
      final state = SelectionState(api: api)..session = session;
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
  SelectionState({ApiClient? api})
    : super(
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: catalog,
        apiClient: api,
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
    String? productLine,
  }) async {
    this.symbol = symbol;
    product = productLine;
    reduce = reduceOnly;
    return OrderModel.fromJson({
      'orderId': 1,
      'symbol': symbol,
      'status': 'NEW',
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
