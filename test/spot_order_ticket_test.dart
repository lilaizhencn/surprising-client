import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

Instrument spot({String status = 'TRADING'}) => Instrument.fromJson({
  'instrumentId': '1',
  'symbol': 'BTC-USDT',
  'instrumentType': 'SPOT',
  'contractType': 'SPOT',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'priceTickUnits': 1000000,
  'quantityStepUnits': 10000,
  'pricePrecision': 2,
  'quantityPrecision': 4,
  'status': status,
});
const session = AuthSession(
  user: AuthUser(userId: 1, username: 'spot', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);

void main() {
  test(
    'spot BBO payload keeps product identity and decodes terminal order receipts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
        requests.add({
          ...body,
          'product': request.headers.value('X-Product-Line'),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'commandId': 'abc',
            'outcome': 'TERMINAL',
            'code': 'NONE',
            'result': {
              'resultType': 'order',
              'orderId': 42,
              'instrumentId': '1',
              'status': 'ACCEPTED',
              'side': 'BUY',
            },
          }),
        );
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..instrumentCatalog = [spot()];
      for (final mode in bboPriceModes) {
        final order = await api.placeOrder(
          userId: 1,
          symbol: 'BTC-USDT',
          side: 'BUY',
          orderType: 'LIMIT',
          timeInForce: 'GTC',
          priceTicks: 9999,
          quantitySteps: 2,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
          bboPriceMode: mode,
          productLine: 'SPOT',
        );
        expect(order.orderId, 42);
        expect(order.symbol, 'BTC-USDT');
        expect(requests.last['priceTicks'], 0);
        expect(requests.last['bboPriceMode'], mode);
        expect(requests.last['instrumentId'], '1');
        expect(requests.last['product'], 'SPOT');
      }
      await expectLater(
        api.testOrder(
          userId: 1,
          symbol: 'BTC-USDT',
          side: 'BUY',
          orderType: 'MARKET',
          timeInForce: 'GTC',
          priceTicks: 0,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
          productLine: 'SPOT',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(4));
    },
  );

  test(
    'spot uses fixed account semantics and blocks pending commands until explicitly confirmed',
    () async {
      final api = _SpotApi();
      final settings = _MemorySettings();
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      Future<void> place() => state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 0,
        quantitySteps: 2,
        marginMode: 'ISOLATED',
        positionSide: 'LONG',
        reduceOnly: true,
        postOnly: false,
        bboPriceMode: 'OPPONENT_5',
      );
      await place();
      expect(api.calls, 1);
      expect(api.last, {
        'margin': 'CROSS',
        'position': 'NET',
        'reduce': false,
        'ticks': 0,
        'bbo': 'OPPONENT_5',
        'product': 'SPOT',
      });
      expect(state.tradingCommandPending, isTrue);
      expect(settings.values['pendingTradingCommand'], '123');
      expect(settings.values['pendingTradingProduct'], 'SPOT');
      expect(settings.values['pendingTradingUser'], '1');
      expect(state.lastError, isNull);
      expect(state.lastNotice, contains('待确认'));
      await place();
      expect(api.calls, 1);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      api.terminal = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(settings.values.containsKey('pendingTradingCommand'), isFalse);
      expect(state.lastNotice, contains('已确认'));
      expect(api.commandQueries, 2);
    },
  );

  test(
    'paused spot or conflicting execution policy never reaches order submission',
    () async {
      final api = _SpotApi();
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      for (final tif in ['GTC', 'GTX']) {
        await state.placeOrder(
          side: 'BUY',
          orderType: 'MARKET',
          timeInForce: tif,
          price: 0,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
        );
        expect(state.lastError, contains('市价单'));
      }
      state.instruments = [spot(status: 'PAUSED')];
      await state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 1,
        quantitySteps: 1,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
      );
      expect(state.lastError, contains('暂停'));
      expect(api.calls, 0);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'spot BBO and market controls fit a 320px ${brightness.name} ticket',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = _SpotState(_SpotApi())..session = session;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: TradePage()),
            ),
          ),
        );
        expect(find.text('只减仓'), findsNothing);
        await tester.ensureVisible(find.text('BBO 最优价'));
        await tester.tap(find.text('BBO 最优价'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('bbo-price-mode')), findsOneWidget);
        expect(find.text('对手价 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final orderType = find.byWidgetPredicate(
          (w) => w is SmallDropdown && w.value == 'LIMIT',
        );
        for (final scroll in tester.stateList<ScrollableState>(
          find.ancestor(of: orderType, matching: find.byType(Scrollable)),
        )) {
          scroll.position.jumpTo(0);
        }
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: orderType,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('市价单').last);
        await tester.pumpAndSettle();
        final ticket = tester.widget<OrderTicket>(find.byType(OrderTicket));
        expect(ticket.timeInForce, 'IOC');
        expect(ticket.postOnly, isFalse);
        expect(ticket.bboEnabled, isFalse);
        expect(find.byKey(const ValueKey('bbo-price-mode')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RealHttp extends HttpOverrides {}

class _SpotState extends AppState {
  _SpotState(ApiClient api, {ClientSettingsStore? settings})
    : super(
        apiClient: api,
        settingsStore: settings,
        seedInstruments: [spot()],
        config: const AppConfig(websocketUrl: ''),
      ) {
    mode = ProductMode.spot;
  }
  @override
  Future<void> refreshPrivateData() async {}
}

class _SpotApi extends ApiClient {
  _SpotApi() : super(const AppConfig());
  int calls = 0, commandQueries = 0;
  bool terminal = false;
  Map<String, dynamic>? last;
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
  }) async {
    calls++;
    last = {
      'margin': marginMode,
      'position': positionSide,
      'reduce': reduceOnly,
      'ticks': priceTicks,
      'bbo': bboPriceMode,
      'product': productLine,
    };
    throw PendingTradingCommand('123');
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
    expect(path, '/api/v1/gateway/trading/commands/123');
    expect(productLine, 'SPOT');
    commandQueries++;
    return {
      'outcome': terminal ? 'TERMINAL' : 'MATCHING_PENDING',
      'code': terminal ? 'NONE' : 'MATCHING_PENDING',
    };
  }
}

class _MemorySettings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    this.values = {...values};
  }
}
