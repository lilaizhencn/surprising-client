import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

String version(int n) => '${n.toString().padLeft(19, '0')}:0000000000';
Map<String, dynamic> event(String channel, int n, dynamic value) => {
  'op': 'event',
  'channel': channel,
  'userId': 1,
  'productLine': 'LINEAR_PERPETUAL',
  'data': {'version': version(n), 'entityId': 'user', 'value': value},
};
Map<String, dynamic> snapshot(
  int n, {
  Map<String, dynamic>? account,
  List<dynamic>? orders,
}) => {
  'op': 'snapshot',
  'userId': 1,
  'productLine': 'LINEAR_PERPETUAL',
  'data': {
    'status': 'READY',
    'snapshotVersion': version(n),
    'account': account ?? {'balances': [], 'positions': []},
    'openOrders': orders ?? [],
  },
};

void main() {
  for (final product in ProductMode.values) {
    test(
      '${product.name}: fence preserves newer updates, tombstones and gap repair',
      () {
        final view = PrivateView();
        view.apply(
          event('orders', 12, {'orderId': 9007199254740993, 'status': 'OPEN'}),
        );
        view.apply(snapshot(10));
        expect(view.rows('order').single['orderId'], 9007199254740993);
        view.apply(
          event('orders', 14, {
            'orderId': 9007199254740993,
            'status': 'FILLED',
          }),
        );
        view.apply(
          event('orders', 13, {'orderId': 9007199254740993, 'status': 'OPEN'}),
        );
        view.apply(
          snapshot(
            11,
            orders: [
              {'orderId': 9007199254740993, 'status': 'OPEN'},
            ],
          ),
        );
        expect(view.rows('order'), isEmpty);
        view.apply(event('orders', 15, {'orderId': 2, 'status': 'OPEN'}));
        view.apply(snapshot(20));
        expect(view.rows('order'), isEmpty);
        view.apply(
          snapshot(
            19,
            orders: [
              {'orderId': 3, 'status': 'OPEN'},
            ],
          ),
        );
        expect(view.rows('order'), isEmpty);
      },
    );
  }
  test(
    'zero balances persist, zero positions and terminal triggers disappear',
    () {
      final view = PrivateView();
      view.apply(
        snapshot(
          1,
          account: {
            'balances': [
              {'asset': 'USDT', 'availableUnits': 10},
              {'asset': 'BTC', 'availableUnits': 20},
            ],
            'positions': [],
          },
        ),
      );
      view.apply(
        event('accountState', 2, {
          'balances': [
            {'asset': 'USDT', 'availableUnits': 0, 'lockedUnits': 0},
          ],
        }),
      );
      expect(view.rows('balance').length, 2);
      expect(
        view
            .rows('balance')
            .firstWhere((b) => b['asset'] == 'USDT')['availableUnits'],
        0,
      );
      view.apply(
        event('positions', 3, {
          'positions': [
            {'symbol': 'BTC', 'signedQuantitySteps': 2},
          ],
        }),
      );
      view.apply(
        event('positions', 5, {
          'positions': [
            {'symbol': 'BTC', 'signedQuantitySteps': 0},
          ],
        }),
      );
      view.apply(
        event('positions', 4, {
          'positions': [
            {'symbol': 'BTC', 'signedQuantitySteps': 2},
          ],
        }),
      );
      expect(view.rows('position'), isEmpty);
      for (final status in [
        'TRIGGERED',
        'TRIGGER_FAILED',
        'CANCELED',
        'EXPIRED',
      ]) {
        view.apply(
          event('triggerOrders', 6, [
            {'triggerOrderId': status, 'status': 'PENDING'},
          ]),
        );
        view.apply(
          event('triggerOrders', 8, [
            {'triggerOrderId': status, 'status': status},
          ]),
        );
        view.apply(
          event('triggerOrders', 7, [
            {'triggerOrderId': status, 'status': 'PENDING'},
          ]),
        );
      }
      expect(view.rows('trigger'), isEmpty);
      view.receivedAt = DateTime.now().subtract(const Duration(seconds: 16));
      expect(view.ready, isFalse);
    },
  );

  test(
    'linear, inverse and premium-paid option valuation uses integer units',
    () {
      final p = {'signedQuantitySteps': 2, 'entryPriceTicks': 100};
      Instrument instrument(String type, [int? scale]) => Instrument.fromJson({
        'contractType': type,
        'priceTickUnits': 1,
        'notionalMultiplierUnits': 10,
        'settleScaleUnits': scale,
      });
      expect(positionValuation(p, instrument('LINEAR_PERPETUAL'), 120), (
        pnl: 400,
        value: 400,
      ));
      expect(positionValuation(p, instrument('VANILLA_OPTION'), 120), (
        pnl: 400,
        value: 2400,
      ));
      expect(positionValuation(p, instrument('INVERSE_PERPETUAL', 1000), 120), (
        pnl: 33,
        value: 33,
      ));
      expect(
        positionValuation(p, instrument('INVERSE_PERPETUAL'), 120),
        isNull,
      );
    },
  );

  test(
    'six products share a symbol without mixing balances, marks or closing PnL',
    () {
      final state = AppState(offline: true)
        ..session = const AuthSession(
          user: AuthUser(
            userId: 1,
            username: 'test',
            email: 'test@example.com',
            status: 'ACTIVE',
          ),
          accessToken: 'access',
          refreshToken: 'refresh',
        )
        ..instruments = [
          for (final p in ProductMode.values)
            Instrument.fromJson({
              'symbol': 'BTC-USDT',
              'contractType': p.contractType,
              'version': 1,
              'notionalMultiplierUnits': 10,
              'priceTickUnits': 1,
            }),
        ];
      addTearDown(state.dispose);
      state.handleRealtimeMessage({'op': 'authenticated', 'userId': 1});
      for (final p in ProductMode.values) {
        state.handleRealtimeMessage({
          ...snapshot(
            1,
            account: {
              'balances': [
                {'asset': 'USDT', 'availableUnits': 1000, 'lockedUnits': 100},
              ],
              'positions': [],
            },
          ),
          'productLine': p.productLine,
        });
      }
      expect(state.allProductBalances.length, 6);
      expect(state.assetsReady, isTrue);
      final position = {
        'symbol': 'BTC-USDT',
        'instrumentVersion': 1,
        'signedQuantitySteps': 2,
        'entryPriceTicks': 100,
        'marginAsset': 'USDT',
      };
      state.handleRealtimeMessage(
        event('positions', 2, {
          'positions': [position],
        }),
      );
      state.handleRealtimeMessage({
        ...event('mark', 3, {'markPriceTicks': 120}),
        'symbol': 'BTC-USDT',
      });
      expect(
        state.productBalances[ProductMode.linear]!.single.equityUnits,
        1500,
      );
      expect(state.productBalances[ProductMode.spot]!.single.equityUnits, 1100);
      state.handleRealtimeMessage(
        event('positions', 4, {
          'positions': [
            {...position, 'signedQuantitySteps': 0},
          ],
        }),
      );
      state.handleRealtimeMessage(
        event('accountState', 5, {
          'balances': [
            {'asset': 'USDT', 'availableUnits': 1500, 'lockedUnits': 0},
          ],
        }),
      );
      expect(
        state.productBalances[ProductMode.linear]!.single.equityUnits,
        1500,
      );
      expect(state.positions, isEmpty);
    },
  );

  test(
    'real WS waits for auth, diffs subscriptions and omits token from URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final messages = <Map<String, dynamic>>[];
      final auth = Completer<WebSocket>();
      final subscribed = Completer<void>(), unsubscribed = Completer<void>();
      server.listen((request) async {
        expect(request.uri.queryParameters.containsKey('token'), isFalse);
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          final m = jsonDecode(raw as String) as Map<String, dynamic>;
          messages.add(m);
          if (m['op'] == 'authenticate') auth.complete(socket);
          if (m['op'] == 'subscribe') subscribed.complete();
          if (m['op'] == 'unsubscribe') unsubscribed.complete();
        });
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      await client.connect(
        userId: 1,
        accessToken: 'test',
        onEvent: (_) {},
        onError: (e) => fail('$e'),
      );
      client.replaceSubscriptions([
        {'channel': 'accountState', 'productLine': 'SPOT'},
      ]);
      final socket = await auth.future.timeout(const Duration(seconds: 3));
      expect(messages.map((m) => m['op']), ['authenticate']);
      socket.add(jsonEncode({'op': 'authenticated', 'userId': 1}));
      await subscribed.future.timeout(const Duration(seconds: 3));
      client.replaceSubscriptions([]);
      await unsubscribed.future.timeout(const Duration(seconds: 3));
      expect(messages.map((m) => m['op']), [
        'authenticate',
        'subscribe',
        'unsubscribe',
      ]);
    },
  );
}
