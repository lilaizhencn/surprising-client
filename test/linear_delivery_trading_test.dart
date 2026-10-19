import 'dart:io';
import 'package:flutter/material.dart';
import 'package:surprising_client/src/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

Instrument delivery({
  String status = 'SETTLING',
  ProductMode mode = ProductMode.linearDelivery,
}) => Instrument.fromJson({
  'instrumentId': '73',
  'symbol': 'BTC-USDT-261225',
  'instrumentType': 'DELIVERY',
  'contractType': mode.contractType,
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': mode == ProductMode.inverseDelivery ? 'BTC' : 'USDT',
  'priceTickUnits': 10000000,
  'quantityStepUnits': 100000,
  'pricePrecision': 1,
  'quantityPrecision': 0,
  'status': status,
  'expiryTime': '2026-12-25T08:00:00Z',
  'deliveryTime': '2026-12-25T08:05:00Z',
  'quoteScaleUnits': 100000000,
  'settleScaleUnits': 100000000,
  'notionalMultiplierUnits': mode == ProductMode.inverseDelivery
      ? 100000000000
      : 10000,
  'changeId': 3,
});
const actor = AuthSession(
  user: AuthUser(userId: 1, username: 'delivery', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);
Position position({ProductMode mode = ProductMode.linearDelivery}) =>
    Position.fromJson({
      'instrumentId': '73',
      'symbol': 'BTC-USDT-261225',
      'signedQuantitySteps': 2,
      'positionSide': 'LONG',
      'marginMode': 'ISOLATED',
      'entryPriceTicks': 500000,
      'marginAsset': mode == ProductMode.inverseDelivery ? 'BTC' : 'USDT',
    });
void main() {
  for (final product in [
    ProductMode.linearDelivery,
    ProductMode.inverseDelivery,
  ]) {
    test(
      '${product.name} delivery state policy blocks new exposure and all orders after halt',
      () {
        expect(
          Instrument.fromJson({
            'contractType': product.productLine,
          }).canPlaceOrder(reduceOnly: true),
          false,
        );
        expect(delivery(mode: product).canPlaceOrder(reduceOnly: false), false);
        expect(delivery(mode: product).canPlaceOrder(reduceOnly: true), true);
        for (final status in [
          'DRAFT',
          'PRE_TRADING',
          'HALT',
          'SETTLED',
          'EXPIRED',
          'UNAVAILABLE',
        ]) {
          expect(
            delivery(
              mode: product,
              status: status,
            ).canPlaceOrder(reduceOnly: true),
            false,
          );
        }
      },
    );
    test(
      '${product.name} catalog refresh retains visible settling delivery contracts and validates product identity',
      () async {
        final api = _Catalog(mode: product);
        final state = AppState(
          apiClient: api,
          settingsStore: _Settings(),
          sessionStore: _Sessions(),
          seedInstruments: [delivery(mode: product)],
          config: const AppConfig(websocketUrl: ''),
        )..mode = product;
        addTearDown(state.dispose);
        api.onDeliveryLoad = () =>
            expect(api.instrumentCatalog, state.instruments);
        await state.refreshInstruments();
        expect(state.selectedInstrument.status, 'SETTLING');
        expect(api.instrumentCatalog, state.instruments);
        api.wrongProduct = true;
        await state.refreshInstruments();
        expect(state.selectedInstrument.status, 'SETTLING');
        expect(api.instrumentCatalog, state.instruments);
        expect(state.lastError, contains('产品线不匹配'));
      },
    );
    test(
      '${product.name} closed delivery refresh retains selected identity and rejects all new orders',
      () async {
        final api = _Catalog(mode: product)..ended = true;
        final state = AppState(
          apiClient: api,
          settingsStore: _Settings(),
          sessionStore: _Sessions(),
          seedInstruments: [delivery(mode: product)],
          config: const AppConfig(websocketUrl: ''),
        )..mode = product;
        addTearDown(state.dispose);
        await state.refreshInstruments();
        expect(state.selectedInstrument.instrumentId, '73');
        expect(state.selectedInstrument.status, 'CLOSED');
        expect(state.selectedInstrument.canPlaceOrder(reduceOnly: true), false);
        expect(api.instrumentCatalog, state.instruments);
      },
    );
    test(
      '${product.name} settling reductions require matching margin, direction and position capacity',
      () async {
        final api = _Api(mode: product);
        final state = _State(api, mode: product)
          ..session = actor
          ..positions = [position(mode: product)];
        addTearDown(state.dispose);
        for (final params in [
          (side: 'BUY', qty: 1, margin: 'ISOLATED'),
          (side: 'SELL', qty: 3, margin: 'ISOLATED'),
          (side: 'SELL', qty: 1, margin: 'CROSS'),
        ]) {
          await state.placeOrder(
            side: params.side,
            orderType: 'MARKET',
            timeInForce: 'IOC',
            price: 0,
            quantitySteps: params.qty,
            marginMode: params.margin,
            positionSide: 'NET',
            reduceOnly: true,
            postOnly: false,
          );
        }
        expect(api.calls, 0);
        expect(state.lastError, contains('当前持仓'));
        await state.placeOrder(
          side: 'SELL',
          orderType: 'MARKET',
          timeInForce: 'IOC',
          price: 0,
          quantitySteps: 1,
          marginMode: 'ISOLATED',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
        );
        expect(api.calls, 0);
        expect(state.lastError, contains('仅允许减仓'));
      },
    );
    test(
      '${product.name} hedge closing direction is explicitly reduce-only just as Core normalizes it',
      () async {
        final api = _Api(mode: product);
        final state = _State(api, mode: product)
          ..session = actor
          ..positionMode = 'HEDGE'
          ..positions = [position(mode: product)];
        addTearDown(state.dispose);
        await state.placeOrder(
          side: 'SELL',
          orderType: 'MARKET',
          timeInForce: 'IOC',
          price: 0,
          quantitySteps: 1,
          marginMode: 'ISOLATED',
          positionSide: 'LONG',
          reduceOnly: false,
          postOnly: false,
        );
        expect(api.calls, 1);
        expect(api.sent?['reduceOnly'], true);
        expect(api.sent?['positionSide'], 'LONG');
      },
    );
    for (final brightness in Brightness.values) {
      testWidgets(
        '${product.name} 320px $brightness delivery ticket permits reductions and blocks opens',
        (tester) async {
          tester.view.physicalSize = const Size(320, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = _State(_Api(mode: product), mode: product)
            ..session = actor;
          addTearDown(state.dispose);
          final price = TextEditingController(),
              quantity = TextEditingController();
          addTearDown(price.dispose);
          addTearDown(quantity.dispose);
          Widget page(bool reduce) => AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: OrderTicket(
                  side: 'SELL',
                  orderType: 'MARKET',
                  timeInForce: 'IOC',
                  marginMode: 'ISOLATED',
                  positionMode: 'ONE_WAY',
                  positionSide: 'NET',
                  reduceOnly: reduce,
                  postOnly: false,
                  bboEnabled: false,
                  bboPriceMode: 'OPPONENT_1',
                  onBboEnabled: (_) {},
                  onBboPriceMode: (_) {},
                  priceController: price,
                  quantityController: quantity,
                  instrument: delivery(mode: product),
                  loggedIn: true,
                  onSide: (_) {},
                  onOrderType: (_) {},
                  onTimeInForce: (_) {},
                  onMarginMode: (_) {},
                  onPositionSide: (_) {},
                  onReduceOnly: (_) {},
                  onPostOnly: (_) {},
                  onSubmit: () {},
                ),
              ),
            ),
          );
          await tester.pumpWidget(page(false));
          expect(
            tester
                .widget<FilledButton>(
                  find.ancestor(
                    of: find.byIcon(Icons.flash_on),
                    matching: find.byType(FilledButton),
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.pumpWidget(page(true));
          expect(
            tester
                .widget<FilledButton>(
                  find.ancestor(
                    of: find.byIcon(Icons.flash_on),
                    matching: find.byType(FilledButton),
                  ),
                )
                .onPressed,
            isNotNull,
          );
          expect(tester.takeException(), isNull);
          if (product == ProductMode.inverseDelivery) {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(brightness: brightness),
                home: Scaffold(
                  body: ProductLifecyclePanel(
                    state: state,
                    instrument: delivery(mode: product),
                    latestPrice: 50000,
                  ),
                ),
              ),
            );
            expect(find.text('1000 USDT'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
    test(
      '${product.name} settling delivery can close its existing position with a product-scoped reduce-only order',
      () async {
        final api = _Api(mode: product);
        final state = _State(api, mode: product)
          ..session = actor
          ..positions = [position(mode: product)];
        addTearDown(state.dispose);
        await state.closePosition(position(mode: product));
        expect(api.calls, 1);
        expect(api.sent?['reduceOnly'], true);
        expect(api.sent?['productLine'], product.productLine);
        expect(api.sent?['positionSide'], 'NET');
        expect(api.sent?['side'], 'SELL');
        expect(api.sent?['quantitySteps'], 2);
      },
    );
    test(
      '${product.name} delivery persists an ordinary order before sending and survives a response lost before command ID',
      () async {
        final store = _Settings(), api = _Api(mode: product)..lost = true;
        var state = _State(api, mode: product, store: store, status: 'TRADING')
          ..session = actor;
        await state.placeOrder(
          side: 'BUY',
          orderType: 'LIMIT',
          timeInForce: 'GTC',
          price: 50000,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
        );
        expect(state.tradingCommandPending, true);
        final key = state.pendingTradingCommand?.clientOrderId;
        expect(key, isNotEmpty);
        expect(api.calls, 1);
        state.dispose();
        state = _State(api, mode: product, store: store, status: 'TRADING');
        addTearDown(state.dispose);
        await state.bootstrap();
        state.session = actor;
        expect(state.pendingTradingCommand?.clientOrderId, key);
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, true);
        api.terminal = true;
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, false);
        expect(api.calls, 1);
      },
    );
    test(
      '${product.name} delivery restores a lost cancellation and rejects an unrelated receipt',
      () async {
        final store = _Settings(), api = _Api(mode: product)..lost = true;
        const orderId = 9007199254740993;
        api.onCancel = () =>
            expect(store.values['pendingTradingOrders'], contains('$orderId'));
        var state = _State(api, mode: product, store: store)..session = actor;
        final target = OrderModel.fromJson({
          'orderId': orderId,
          'instrumentId': '73',
          'symbol': delivery(mode: product).symbol,
          'status': 'ACCEPTED',
        });
        await state.cancelOrder(target);
        expect(state.pendingTradingCommand?.cancelOrderId, orderId);
        expect(api.calls, 1);
        state.dispose();
        state = _State(api, mode: product, store: store);
        addTearDown(state.dispose);
        await state.bootstrap();
        state.session = actor;
        expect(state.pendingTradingCommand?.cancelOrderId, orderId);
        await state.cancelOrder(target);
        expect(api.calls, 1);
        api.terminal = true;
        api.wrongReceipt = true;
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, true);
        api.wrongReceipt = false;
        await state.checkPendingTradingCommand();
        expect(state.tradingCommandPending, false);
        expect(api.calls, 1);
      },
    );
    for (final cancel in [false, true]) {
      test(
        '${product.name} delivery sends no ${cancel ? 'cancellation' : 'order'} if durable storage fails',
        () async {
          final api = _Api(mode: product),
              store = _Settings()..rejectWrites = true;
          final state = _State(
            api,
            mode: product,
            store: store,
            status: 'TRADING',
          )..session = actor;
          addTearDown(state.dispose);
          if (cancel) {
            await state.cancelOrder(
              OrderModel.fromJson({
                'orderId': 91,
                'symbol': delivery(mode: product).symbol,
                'status': 'ACCEPTED',
              }),
            );
          } else {
            await state.placeOrder(
              side: 'BUY',
              orderType: 'MARKET',
              timeInForce: 'IOC',
              price: 0,
              quantitySteps: 1,
              marginMode: 'CROSS',
              positionSide: 'NET',
              reduceOnly: false,
              postOnly: false,
            );
          }
          expect(api.calls, 0);
          expect(state.lastError, contains(cancel ? '未发送撤单' : '未发送订单'));
          expect(state.tradingCommandPending, false);
        },
      );
    }
  }
}

class _Api extends ApiClient {
  _Api({required this.mode}) : super(const AppConfig());
  final ProductMode mode;
  int calls = 0;
  bool lost = false, terminal = false, wrongReceipt = false;
  void Function()? onCancel;
  Map<String, dynamic>? sent;
  String? client;
  @override
  Future<OrderModel> cancelOrder(
    int userId,
    int orderId, {
    String? productLine,
  }) async {
    expect(productLine, mode.productLine);
    onCancel?.call();
    calls++;
    if (lost) throw const SocketException('lost cancellation reply');
    return OrderModel.fromJson({'orderId': orderId, 'status': 'CANCELED'});
  }

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
    calls++;
    client = clientOrderId;
    sent = {
      'reduceOnly': reduceOnly,
      'productLine': productLine,
      'positionSide': positionSide,
      'side': side,
      'quantitySteps': quantitySteps,
    };
    if (lost) throw const SocketException('response lost');
    return OrderModel.fromJson({
      'orderId': 9007199254740993,
      'status': 'FILLED',
      'instrumentId': '73',
      'symbol': symbol,
    });
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
    expect(productLine, mode.productLine);
    if (path.contains('/cancellations/')) {
      return {
        'commandId': 'cancel-delivery',
        'prospectiveOrderIds': [wrongReceipt ? 92 : 9007199254740993],
        'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
        'code': terminal ? 'NONE' : 'RESULT_UNKNOWN',
      };
    }
    if (path.endsWith('by-client-order-id')) {
      throw ApiException(404, 'not found');
    }
    return {
      'userId': userId,
      'productLine': productLine,
      'clientOrderId': client,
      'instrumentId': terminal ? '73' : null,
      'commandId': 'receipt-73',
      'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
      'code': terminal ? 'NONE' : 'RESULT_UNKNOWN',
    };
  }
}

class _State extends AppState {
  _State(
    ApiClient api, {
    ClientSettingsStore? store,
    String status = 'SETTLING',
    ProductMode mode = ProductMode.linearDelivery,
  }) : super(
         apiClient: api,
         settingsStore: store ?? _Settings(),
         sessionStore: _Sessions(),
         seedInstruments: [delivery(status: status, mode: mode)],
         config: const AppConfig(websocketUrl: ''),
       ) {
    this.mode = mode;
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
  bool rejectWrites = false;
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    if (rejectWrites) throw const FileSystemException('storage unavailable');
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

class _Catalog extends ApiClient {
  _Catalog({required this.mode}) : super(const AppConfig());
  final ProductMode mode;
  bool wrongProduct = false;
  bool ended = false;
  @override
  Future<Instrument> instrumentLatest(String id, ProductMode product) async {
    expect(id, '73');
    expect(product, mode);
    return delivery(status: 'CLOSED', mode: mode);
  }

  void Function()? onDeliveryLoad;
  @override
  Future<Map<String, String>> assetScales() async => {
    'USDT': '100000000',
    'BTC': '100000000',
  };
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    if (query?['productLine'] != mode.productLine) return {'instruments': []};
    onDeliveryLoad?.call();
    if (ended) return {'instruments': []};
    return {
      'instruments': [
        {
          'instrumentId': '73',
          'symbol': 'BTC-USDT-261225',
          'contractType': wrongProduct ? 'SPOT' : mode.contractType,
          'instrumentType': 'DELIVERY',
          'baseAsset': 'BTC',
          'quoteAsset': 'USDT',
          'settleAsset': 'USDT',
          'priceTickUnits': 10000000,
          'quantityStepUnits': 100000,
          'status': 'SETTLING',
          'changeId': 4,
        },
      ],
    };
  }
}
