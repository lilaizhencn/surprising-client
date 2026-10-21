import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

const actor = AuthSession(
  user: AuthUser(userId: 1, username: 'delivery', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);
Instrument contract({
  ProductMode product = ProductMode.linearDelivery,
  String status = 'TRADING',
  String? expiry = '2035-12-25T08:00:00Z',
}) => Instrument.fromJson({
  'instrumentId': '73',
  'symbol': product == ProductMode.inverseDelivery
      ? 'BTC-USD-351225'
      : 'BTC-USDT-351225',
  'instrumentType': product.isSpot
      ? 'SPOT'
      : product.isPerpetual
      ? 'PERPETUAL'
      : 'DELIVERY',
  'contractType': product.contractType,
  'productLine': product.productLine,
  'baseAsset': 'BTC',
  'quoteAsset': product == ProductMode.inverseDelivery ? 'USD' : 'USDT',
  'settleAsset': product == ProductMode.inverseDelivery ? 'BTC' : 'USDT',
  'quoteScaleUnits': 1000,
  'settleScaleUnits': product == ProductMode.inverseDelivery ? 100000000 : 1000,
  'priceTickUnits': 5,
  'notionalMultiplierUnits': 1,
  'pricePrecision': 3,
  'status': status,
  'expiryTime': expiry,
  'changeId': 3,
});
TriggerOrderDraft leg(
  String type,
  int price, {
  int quantity = 1,
  String side = 'SELL',
}) => TriggerOrderDraft(
  side: side,
  triggerType: type,
  triggerPriceTicks: price,
  quantitySteps: quantity,
  marginMode: 'ISOLATED',
  positionSide: 'LONG',
  priceSource: 'LAST',
  orderType: 'LIMIT',
  priceTicks: 20000,
);
List<TriggerOrderDraft> pair() => [
  leg('TAKE_PROFIT', 24690),
  leg('STOP_LOSS', 19100),
];
void main() {
  for (final product in [
    ProductMode.spot,
    ProductMode.linear,
    ProductMode.inverse,
  ]) {
    test(
      '${product.productLine} trigger receipts survive restart without enabling spot position protection',
      () async {
        final settings = _Settings(), api = _Api(product)..lose = true;
        var state = _State(api, settings)..session = actor;
        final draft = TriggerOrderDraft(
          side: 'SELL',
          triggerType: 'TAKE_PROFIT',
          triggerPriceTicks: 24690,
          quantitySteps: 1,
          marginMode: product.isSpot ? 'CROSS' : 'ISOLATED',
          positionSide: product.isSpot ? 'NET' : 'LONG',
          priceSource: 'LAST',
          orderType: 'LIMIT',
          priceTicks: 24680,
        );
        String? original;
        if (product.isDerivative) {
          expect(await state.placeTriggerOrders([draft]), 0);
          original = state.pendingTradingCommand?.clientTriggerOrderId;
          expect(original, isNotNull);
          expect(api.posts.length, 1);
          await state.placeTriggerOrders([draft]);
          expect(api.posts.length, 1);
          state.dispose();
          state = _State(api, settings);
          await state.bootstrap();
          state.session = actor;
          expect(state.pendingTradingCommand?.clientTriggerOrderId, original);
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, true);
          api.terminal = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, false);
          expect(api.reads.last['query'], {
            'userId': '1',
            'clientTriggerOrderId': original,
          });
        } else {
          // Recovery support does not enable a position TP/SL form for spot balances.
          expect(await state.placeTriggerOrders([draft]), 0);
          expect(api.posts, isEmpty);
        }
        final order = TriggerOrderModel.fromJson(
          api.order({'clientTriggerOrderId': original}, id: 9007199254740993),
        );
        api.terminal = false;
        await state.cancelTriggerOrder(order);
        expect(
          state.pendingTradingCommand?.cancelTriggerOrderId,
          9007199254740993,
        );
        state.dispose();
        state = _State(api, settings);
        addTearDown(state.dispose);
        await state.bootstrap();
        state.session = actor;
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, true);
        api.terminal = true;
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, false);
        expect(api.posts.length, product.isSpot ? 1 : 2);
        expect(
          api.reads.last['path'],
          '/api/v1/gateway/trading-trigger/cancellations/9007199254740993',
        );
      },
    );
    test(
      '${product.productLine} storage failure prevents trigger creation and cancellation',
      () async {
        final api = _Api(product), settings = _Settings()..fail = true;
        final state = _State(api, settings)..session = actor;
        addTearDown(state.dispose);
        await state.placeTriggerOrders([leg('TAKE_PROFIT', 24690)]);
        await state.cancelTriggerOrder(
          TriggerOrderModel.fromJson(api.order({})),
        );
        expect(api.posts, isEmpty);
        expect(state.tradingCommandPending, false);
      },
    );
  }
  for (final product in [ProductMode.linear, ProductMode.inverse]) {
    for (final brightness in Brightness.values) {
      _testOcoLayout(product, brightness);
    }
  }
  for (final product in [
    ProductMode.linearDelivery,
    ProductMode.inverseDelivery,
  ]) {
    group(product.productLine, () {
      test(
        'SETTLING permits direct reductions but never sends a newly created condition',
        () async {
          final state = _State(
            _Api(product),
            _Settings(),
            instrument: contract(product: product, status: 'SETTLING'),
          )..session = actor;
          addTearDown(state.dispose);
          expect(
            state.selectedInstrument.canPlaceOrder(reduceOnly: true),
            true,
          );
          expect(await state.placeTriggerOrders([pair().first]), 0);
          expect((state.api as _Api).posts, isEmpty);
        },
      );
      test(
        'delivery exposes one atomic pair instead of rejecting the product',
        () async {
          final state = _State(_Api(product), _Settings())..session = actor;
          addTearDown(state.dispose);
          expect(await state.placeOco(pair()), 2);
          expect((state.api as _Api).posts.single['atomic'], true);
        },
      );
      test(
        'a lost independent delivery request retains identity and stops later tiers',
        () async {
          final api = _Api(product)..lose = true, settings = _Settings();
          final state = _State(api, settings)..session = actor;
          addTearDown(state.dispose);
          expect(await state.placeTriggerOrders(pair()), 0);
          expect(api.posts.length, 1);
          expect(state.tradingCommandPending, true);
          expect(
            asMap(
              asList(
                jsonDecode(settings.values['pendingTradingOrders']!),
              ).single,
            )['clientTriggerOrderId'],
            api.posts.single['clientTriggerOrderId'],
          );
        },
      );
      test(
        'delivery OCO is durable across reconstruction and confirmation storage failure',
        () async {
          final api = _Api(product)..lose = true, settings = _Settings();
          var state = _State(api, settings)..session = actor;
          expect(await state.placeOco(pair()), 0);
          expect(api.posts.length, 1);
          final original = state.pendingTradingCommand!.ocoTakeProfitClientId;
          expect(
            original,
            isNot(state.pendingTradingCommand!.ocoStopLossClientId),
          );
          state.dispose();
          state = _State(api, settings);
          addTearDown(state.dispose);
          await state.bootstrap();
          state.session = actor;
          expect(state.pendingTradingCommand!.ocoTakeProfitClientId, original);
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, true);
          api.terminal = true;
          settings.fail = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, true);
          settings.fail = false;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, false);
          expect(api.posts.length, 1);
          expect(api.reads.last['query']['takeProfitClientId'], original);
          expect(
            api.reads.last['path'],
            '/api/v1/gateway/trading-trigger/oco-submission',
          );
        },
      );
      test(
        'delivery normal atomic acknowledgment saves both identities before one request',
        () async {
          final api = _Api(product), settings = _Settings();
          final active = _State(api, settings)..session = actor;
          addTearDown(active.dispose);
          api.before = () {
            final stored = asMap(
              asList(
                jsonDecode(settings.values['pendingTradingOrders']!),
              ).single,
            );
            final body = api.posts.single, orders = asList(body['orders']);
            expect(stored['productLine'], product.productLine);
            expect(
              stored['ocoTakeProfitClientId'],
              asMap(orders.first)['clientTriggerOrderId'],
            );
            expect(
              stored['ocoStopLossClientId'],
              asMap(orders.last)['clientTriggerOrderId'],
            );
            expect(
              orders.every((row) => asMap(row)['instrumentId'] == '73'),
              true,
            );
            expect(active.submittingOrder, true);
          };
          expect(await active.placeOco(pair()), 2);
          expect(api.posts.length, 1);
          expect(active.tradingCommandPending, false);
          expect(active.openTriggerOrders.length, 2);
        },
      );
      test(
        'a confirmed OCO whose storage update fails remains recoverable',
        () async {
          final api = _Api(product), settings = _Settings();
          final state = _State(api, settings)..session = actor;
          addTearDown(state.dispose);
          api.before = () => settings.fail = true;
          expect(await state.placeOco(pair()), 0);
          expect(state.tradingCommandPending, true);
          expect(api.posts.length, 1);
          settings.fail = false;
          api.terminal = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, false);
          expect(api.posts.length, 1);
        },
      );
      test(
        'delivery cancellation survives reconstruction with the exact original 64-bit trigger',
        () async {
          final api = _Api(product)..lose = true, settings = _Settings();
          var state = _State(api, settings)..session = actor;
          final order = TriggerOrderModel.fromJson(
            api.order({'clientTriggerOrderId': 'old'}, id: 9007199254740993),
          );
          await state.cancelTriggerOrder(order);
          expect(
            state.pendingTradingCommand!.cancelTriggerOrderId,
            9007199254740993,
          );
          state.dispose();
          state = _State(api, settings);
          addTearDown(state.dispose);
          await state.bootstrap();
          state.session = actor;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, true);
          api.terminal = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, false);
          expect(api.posts.length, 1);
          expect(
            api.reads.last['path'],
            '/api/v1/gateway/trading-trigger/cancellations/9007199254740993',
          );
        },
      );
      test(
        'delivery initial storage failure sends neither independent, OCO nor cancellation request',
        () async {
          final api = _Api(product), settings = _Settings()..fail = true;
          final state = _State(api, settings)..session = actor;
          addTearDown(state.dispose);
          await state.placeTriggerOrders([pair().first]);
          await state.placeOco(pair());
          await state.cancelTriggerOrder(
            TriggerOrderModel.fromJson(api.order({})),
          );
          expect(api.posts, isEmpty);
          expect(state.tradingCommandPending, false);
        },
      );
      test(
        'delivery malformed reply and unavailable lookup never clear or resend the intent',
        () async {
          final api = _Api(product)..badReply = true;
          final state = _State(api, _Settings())..session = actor;
          addTearDown(state.dispose);
          expect(await state.placeOco(pair()), 0);
          expect(state.tradingCommandPending, true);
          api.badRead = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, true);
          expect(await state.placeTriggerOrders([pair().first]), 0);
          expect(api.posts.length, 1);
        },
      );
      test(
        'delivery conditional lifecycle gate excludes expired and missing-expiry contracts',
        () async {
          for (final instrument in [
            contract(product: product, status: 'HALT'),
            contract(product: product, status: 'CLOSED'),
            contract(product: product, status: 'SETTLING'),
            contract(product: product, expiry: null),
            contract(product: product, expiry: '2020-01-01T00:00:00Z'),
          ]) {
            final state = _State(
              _Api(product),
              _Settings(),
              instrument: instrument,
            )..session = actor;
            expect(state.selectedInstrument.canPlaceTrigger(), false);
            expect(await state.placeTriggerOrders([pair().first]), 0);
            expect(await state.placeOco(pair()), 0);
            expect((state.api as _Api).posts, isEmpty);
            state.dispose();
          }
          expect(contract(product: product).canPlaceTrigger(), true);
        },
      );
      test(
        'delivery keeps close side, hedge side, margin mode and quantity tied to the same position',
        () async {
          final state = _State(_Api(product), _Settings())..session = actor;
          addTearDown(state.dispose);
          await state.placeOco([
            leg('TAKE_PROFIT', 24690, quantity: 5),
            leg('STOP_LOSS', 19100, quantity: 5),
          ]);
          await state.placeOco([
            leg('TAKE_PROFIT', 19100, side: 'BUY'),
            leg('STOP_LOSS', 24690, side: 'BUY'),
          ]);
          expect((state.api as _Api).posts, isEmpty);
        },
      );
      test(
        'delivery pending result stays bound to its product after the visible product changes',
        () async {
          final api = _Api(product)..lose = true, settings = _Settings();
          final state = _State(api, settings)..session = actor;
          addTearDown(state.dispose);
          await state.placeOco(pair());
          state.mode = ProductMode.option;
          api.terminal = true;
          await state.checkPendingTradingCommand();
          expect(state.tradingCommandPending, false);
          expect(api.reads.single['productLine'], product.productLine);
          expect(api.posts.length, 1);
        },
      );
      for (final brightness in Brightness.values) {
        _testOcoLayout(product, brightness);
        testWidgets(
          '320px $brightness settling condition form is disabled while direct reductions remain allowed',
          (tester) async {
            final api = _Api(product);
            final state = _State(
              api,
              _Settings(),
              instrument: contract(product: product, status: 'SETTLING'),
            )..session = actor;
            tester.view.physicalSize = const Size(320, 1500);
            tester.view.devicePixelRatio = 1;
            addTearDown(() {
              state.dispose();
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });
            await tester.pumpWidget(
              AppScope(
                notifier: state,
                child: MaterialApp(
                  theme: ThemeData(brightness: brightness),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: TriggerOrderPanel(
                        state: state,
                        marginMode: 'ISOLATED',
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('独立条件单'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('TP/SL 双腿 OCO').last);
            await tester.pumpAndSettle();
            final prices = find.byWidgetPredicate(
              (w) => w is AppTextField && w.label.startsWith('触发价'),
            );
            await tester.enterText(
              find.descendant(
                of: prices.first,
                matching: find.byType(TextField),
              ),
              '123.45',
            );
            await tester.enterText(
              find.descendant(
                of: prices.last,
                matching: find.byType(TextField),
              ),
              '95.5',
            );
            await tester.pump();
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, '一起提交 TP/SL'),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              state.selectedInstrument.canPlaceOrder(reduceOnly: true),
              true,
            );
            expect(api.posts, isEmpty);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    });
  }
}

void _testOcoLayout(ProductMode product, Brightness brightness) {
  testWidgets(
    '${product.productLine} 320px $brightness OCO keeps exact scales and unknown requests',
    (tester) async {
      final api = _Api(product)..lose = true;
      final state = _State(api, _Settings())..session = actor;
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        state.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: TriggerOrderPanel(state: state, marginMode: 'ISOLATED'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('独立条件单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TP/SL 双腿 OCO').last);
      await tester.pumpAndSettle();
      final prices = find.byWidgetPredicate(
        (w) => w is AppTextField && w.label.startsWith('触发价'),
      );
      await tester.enterText(
        find.descendant(of: prices.first, matching: find.byType(TextField)),
        '123.45',
      );
      await tester.enterText(
        find.descendant(of: prices.last, matching: find.byType(TextField)),
        '95.5',
      );
      await tester.pump();
      await tester.tap(find.text('一起提交 TP/SL'));
      await tester.pumpAndSettle();
      expect(api.posts.length, 1);
      final orders = asList(api.posts.single['orders']);
      expect(asMap(orders.first)['triggerPriceTicks'], 24690);
      expect(asMap(orders.last)['triggerPriceTicks'], 19100);
      expect(asMap(orders.first)['positionSide'], 'LONG');
      expect(asMap(orders.first)['marginMode'], 'ISOLATED');
      expect(state.tradingCommandPending, true);
      expect(find.text('暂无待提交档位'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Api extends ApiClient {
  _Api(this.product) : super(const AppConfig());
  final ProductMode product;
  final List<Map<String, dynamic>> posts = [];
  bool lose = false, terminal = false, badReply = false, badRead = false;
  final List<Map<String, dynamic>> reads = [];
  FutureOr<void> Function()? before;
  Map<String, dynamic> order(Map<String, dynamic> body, {int id = 99}) => {
    'userId': 1,
    'instrumentId': '73',
    'symbol': contract(product: product).symbol,
    'side': 'SELL',
    'triggerType': 'TAKE_PROFIT',
    'triggerPriceTicks': 24690,
    'quantitySteps': 1,
    'marginMode': 'ISOLATED',
    'positionSide': 'LONG',
    'status': 'PENDING',
    ...body,
    'triggerOrderId': id,
    if (badReply) 'instrumentId': 'other',
  };
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = true,
  }) async {
    expect(productLine, product.productLine);
    posts.add({...body});
    await before?.call();
    if (lose) throw const SocketException('reply lost');
    if (path.endsWith('/batch')) {
      final rows = asList(body['orders']);
      return {
        'requested': 2,
        'completed': 2,
        'failed': 0,
        'results': [
          for (var i = 0; i < rows.length; i++)
            {
              'index': i,
              'success': true,
              'order': order(asMap(rows[i]), id: 100 + i),
            },
        ],
      };
    }
    return order({...body, if (path.endsWith('/cancel')) 'status': 'CANCELED'});
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    expect(productLine, product.productLine);
    expect(userId, 1);
    reads.add({'path': path, 'query': query, 'productLine': productLine});
    if (badRead) throw ApiException(503, 'unavailable');
    return {
      'commandId': 'original-command',
      'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
      'code': terminal ? 'NONE' : 'RESULT_UNKNOWN',
    };
  }
}

class _State extends AppState {
  _State(_Api api, _Settings settings, {Instrument? instrument})
    : super(
        apiClient: api,
        settingsStore: settings,
        sessionStore: _Sessions(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [instrument ?? contract(product: api.product)],
      ) {
    mode = api.product;
    positionMode = 'HEDGE';
    positions = [
      Position.fromJson({
        'instrumentId': '73',
        'symbol': selectedSymbol,
        'signedQuantitySteps': 4,
        'marginMode': 'ISOLATED',
        'positionSide': 'LONG',
      }),
    ];
  }
  @override
  Future<void> refreshPrivateData() async {}
  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshValuation({bool silent = false}) async {}
  @override
  Future<void> refreshAnnouncements() async {}
}

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  bool fail = false;
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    if (fail) throw const FileSystemException('full');
    this.values = {...values};
  }
}

class _Sessions implements SessionStore {
  @override
  Future<AuthSession?> readSession() async => null;
  @override
  Future<void> saveSession(AuthSession session) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> biometricEnabled() async => false;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<bool> authenticateBiometric() async => false;
  @override
  Future<void> enableBiometric() async {}
}
