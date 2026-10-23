import 'support/authentication.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

import 'transfer_page_test.dart' show MemorySettings;

// Explicit contract samples for unit/widget tests, never financial runtime responses.
Map<String, dynamic> row({String status = 'RUNNING'}) => {
  'algoOrderId': '9007199254740993',
  'userId': '1',
  'clientAlgoOrderId': 'original-algo',
  'instrumentId': '868',
  'algoType': 'ICEBERG',
  'side': 'BUY',
  'priceTicks': '9007199254740993',
  'quantitySteps': '100',
  'childQuantitySteps': '10',
  'intervalSeconds': '0',
  'durationSeconds': '60',
  'marginMode': 'CROSS',
  'positionSide': 'NET',
  'reduceOnly': false,
  'postOnly': false,
  'timeInForce': 'GTC',
  'status': status,
  'executedQuantitySteps': '25',
  'activeQuantitySteps': status == 'CANCELED' ? '0' : '10',
  'childOrderCount': '4',
  'currentOrderId': '9223372036854775807',
};
AlgoOrderModel model(Map<String, dynamic> value) =>
    AlgoOrderModel.fromJson(value, product: ProductMode.spot);
Instrument instrument([String id = '868', String symbol = 'BTC-USDT']) =>
    Instrument.fromJson({
      'instrumentId': id,
      'symbol': symbol,
      'instrumentType': 'SPOT',
      'contractType': 'SPOT',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'settleAsset': 'USDT',
      'priceTickUnits': 5,
      'quantityStepUnits': 20,
      'baseScaleUnits': 1000000,
      'quoteScaleUnits': 1000,
      'status': 'TRADING',
    });
AuthSession authSession(int id) => AuthSession(
  user: AuthUser(userId: id, username: 'qa', email: '', status: 'ACTIVE'),
  accessToken: 'qa-$id',
  refreshToken: 'qa-$id',
);

void main() {
  test(
    'algo identity and progress preserve int64 without counting working quantity as fills',
    () {
      final o = model(row());
      expect(o.algoOrderId, 9007199254740993);
      expect(o.currentOrderId, 9223372036854775807);
      expect(o.userId, 1);
      expect(o.instrumentId, '868');
      expect(o.executedQuantitySteps, 25);
      expect(o.activeQuantitySteps, 10);
    },
  );
  for (final invalid in [
    {'algoOrderId': '9223372036854775808'},
    {'quantitySteps': 1.5},
    {'executedQuantitySteps': '-1'},
    {'activeQuantitySteps': '76'},
    {'childQuantitySteps': '101'},
    {'intervalSeconds': '5'},
    {'userId': 0},
    {'instrumentId': ''},
    {'productLine': 'OPTION'},
    {'status': 'UNKNOWN'},
    {'algoType': 'OTHER'},
    {'positionSide': 'LONG'},
    {'reduceOnly': true},
    {'postOnly': 'false'},
    {'currentOrderId': '1e3'},
    {'clientAlgoOrderId': ''},
  ]) {
    test('algo model rejects malformed $invalid', () {
      expect(() => model({...row(), ...invalid}), throwsFormatException);
    });
  }

  test(
    'real HTTP adapter sends product, owner and permanent instrument query',
    () async {
      final body = {
        'count': 1,
        'orders': [row()],
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      server.listen((r) async {
        requests.add(r);
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _Http(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api =
          ApiClient(
              AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
              httpClient: http,
            )
            ..instrumentCatalog = [instrument()]
            ..setSession(authSession(1));
      final values = await api.openAlgoOrders(
        1,
        symbol: 'BTC-USDT',
        productLine: 'SPOT',
      );
      expect(values.single.symbol, 'BTC-USDT');
      expect(requests.single.uri.path, '/api/v1/gateway/trading/algo/open');
      expect(requests.single.uri.queryParameters, {
        'userId': '1',
        'instrumentId': '868',
        'limit': '1000',
      });
      expect(requests.single.headers.value('Authorization'), 'Bearer qa-1');
      expect(requests.single.headers.value('X-User-Id'), '1');
      expect(requests.single.headers.value('X-Product-Line'), 'SPOT');
      for (final bad in [
        {...row(), 'userId': '2'},
        {...row(), 'instrumentId': '869'},
        {...row(), 'status': 'CANCELED'},
      ]) {
        body['orders'] = [bad];
        await expectLater(
          api.openAlgoOrders(1, symbol: 'BTC-USDT', productLine: 'SPOT'),
          throwsFormatException,
        );
      }
      body['orders'] = [row(), row()];
      body['count'] = 2;
      await expectLater(
        api.openAlgoOrders(1, productLine: 'SPOT'),
        throwsFormatException,
      );
      body['orders'] = [row()];
      await expectLater(
        api.openAlgoOrders(1, productLine: 'SPOT'),
        throwsFormatException,
      );
      final sent = requests.length;
      await expectLater(
        api.openAlgoOrders(1, symbol: 'MISSING', productLine: 'SPOT'),
        throwsFormatException,
      );
      expect(requests.length, sent);
    },
  );

  test(
    'spot private refresh loads algo reads without derivative liquidation calls',
    () async {
      final api = _Api()..rows = [model(row())];
      final state = _State(api);
      addTearDown(state.dispose);
      await state.refreshPrivateData();
      expect(api.reads, [(1, 'BTC-USDT', 'SPOT')]);
      expect(state.visibleAlgoOrders.single.algoOrderId, 9007199254740993);
      expect(state.loadingAlgoOrders, isFalse);
    },
  );
  test(
    'late responses cannot cross account, instrument, product or filter generations',
    () async {
      final api = _Api();
      final state = _State(api);
      addTearDown(state.dispose);
      final old = Completer<List<AlgoOrderModel>>();
      api.nextRead = old.future;
      final loading = state.refreshAlgoOrders();
      await state.logout();
      await signInAs(state, authSession(2));
      api.rows = [];
      await state.refreshAlgoOrders();
      old.complete([model(row())]);
      await loading;
      expect(state.visibleAlgoOrders, isEmpty);
      await state.logout();
      await signInAs(state, authSession(1));
      final first = Completer<List<AlgoOrderModel>>();
      api.nextRead = first.future;
      final previous = state.refreshAlgoOrders();
      state.selectedSymbol = 'ETH-USDT';
      await state.refreshAlgoOrders();
      first.complete([model(row())]);
      await previous;
      expect(state.openAlgoOrders, isEmpty);
      final spot = Completer<List<AlgoOrderModel>>();
      api.nextRead = spot.future;
      final previousProduct = state.refreshAlgoOrders();
      state.mode = ProductMode.option;
      spot.complete([model(row())]);
      await previousProduct;
      expect(state.visibleAlgoOrders, isEmpty);
      state.mode = ProductMode.spot;
      state.selectedSymbol = 'BTC-USDT';
      final filtered = Completer<List<AlgoOrderModel>>();
      api.nextRead = filtered.future;
      final previousFilter = state.refreshAlgoOrders();
      state.setTradingPairFilter(false);
      filtered.complete([model(row())]);
      await previousFilter;
      expect(api.reads.last, (1, null, 'SPOT'));
      expect(state.openAlgoOrders, isEmpty);
    },
  );
  test(
    'failed refresh clears obsolete rows and exposes an error instead of an empty success',
    () async {
      final api = _Api()..rows = [model(row())];
      final state = _State(api);
      addTearDown(state.dispose);
      await state.refreshAlgoOrders();
      api.failure = ApiException(503, 'ALGO_READ_VIEW_INITIALIZING');
      await state.refreshAlgoOrders();
      expect(state.openAlgoOrders, isEmpty);
      expect(state.algoOrdersError, contains('加载算法单失败'));
      expect(state.loadingAlgoOrders, isFalse);
    },
  );
  test(
    'cancellation uses the immutable target once and reports cancel-requested truthfully',
    () async {
      final api = _Api()..rows = [model(row(status: 'CANCEL_REQUESTED'))];
      final state = _State(api)..openAlgoOrders = [model(row())];
      addTearDown(state.dispose);
      final pending = Completer<AlgoOrderModel>();
      api.nextCancel = pending.future;
      final first = state.cancelAlgoOrder(state.openAlgoOrders.single);
      await state.cancelAlgoOrder(state.openAlgoOrders.single);
      expect(api.cancels, [(1, 9007199254740993, 'SPOT')]);
      pending.complete(model(row(status: 'CANCEL_REQUESTED')));
      await first;
      expect(state.lastNotice, contains('取消中'));
      expect(state.lastNotice, isNot(contains('已确认')));
      expect(state.openAlgoOrders.single.status, 'CANCEL_REQUESTED');
      expect(state.submittingOrder, isFalse);
      final old = state.openAlgoOrders.single;
      await state.logout();
      await signInAs(state, authSession(2));
      await state.cancelAlgoOrder(old);
      expect(api.cancels.length, 1);
    },
  );
  test('cancellation replies cannot populate a switched account', () async {
    final api = _Api();
    final state = _State(api)..openAlgoOrders = [model(row())];
    addTearDown(state.dispose);
    final pending = Completer<AlgoOrderModel>();
    api.nextCancel = pending.future;
    final request = state.cancelAlgoOrder(state.openAlgoOrders.single);
    await state.logout();
    await signInAs(state, authSession(2));
    state.openAlgoOrders = [];
    final newAccountNotice = state.lastNotice;
    pending.complete(model(row(status: 'CANCELED')));
    await request;
    expect(state.visibleAlgoOrders, isEmpty);
    expect(state.lastNotice, newAccountNotice);
  });
  test(
    'an older SQL read cannot resurrect the parent after its cancellation response',
    () async {
      final api = _Api();
      final state = _State(api)..openAlgoOrders = [model(row())];
      addTearDown(state.dispose);
      final pending = Completer<List<AlgoOrderModel>>();
      api.nextRead = pending.future;
      final read = state.refreshAlgoOrders();
      await state.cancelAlgoOrder(state.openAlgoOrders.single);
      pending.complete([model(row())]);
      await read;
      expect(state.openAlgoOrders, isEmpty);
      expect(state.loadingAlgoOrders, isFalse);
      expect(state.lastNotice, contains('撤销已确认'));
    },
  );
  test(
    'halted instruments are resolved by immutable identity without entering the trading catalog',
    () async {
      final api = _Api()
        ..rows = [
          model({...row(), 'instrumentId': '999'}),
        ]
        ..metadata = instrument('999', 'HALTED-BTC-USDT');
      final state = _State(api)..onlyCurrentTradingPair = false;
      addTearDown(state.dispose);
      await state.refreshAlgoOrders();
      expect(api.metadataReads, [('999', ProductMode.spot)]);
      expect(
        state.algoInstrumentFor(state.openAlgoOrders.single)?.symbol,
        'HALTED-BTC-USDT',
      );
      expect(state.instruments.any((i) => i.instrumentId == '999'), isFalse);
      expect(state.algoOrdersError, isNull);
    },
  );
  test(
    'ordinary order pagination cannot leave private refresh loading forever',
    () async {
      final api = _Api();
      final state = _State(api);
      addTearDown(state.dispose);
      final pending = Completer<List<AlgoOrderModel>>();
      api.nextRead = pending.future;
      final refresh = state.refreshPrivateData();
      state.openOrdersHasMore = true;
      state.openOrdersNextCursor = 'next';
      await state.loadMoreOpenOrders();
      pending.complete([model(row())]);
      await refresh;
      expect(state.loadingPrivate, isFalse);
      expect(state.openAlgoOrders.single.algoOrderId, 9007199254740993);
    },
  );
  test(
    'switching product during cancellation releases its original busy flag without importing its response',
    () async {
      final api = _Api();
      final state = _State(api)..openAlgoOrders = [model(row())];
      addTearDown(state.dispose);
      final pending = Completer<AlgoOrderModel>();
      api.nextCancel = pending.future;
      final request = state.cancelAlgoOrder(state.openAlgoOrders.single);
      state.mode = ProductMode.option;
      state.openAlgoOrders = [];
      pending.complete(model(row(status: 'CANCELED')));
      await request;
      expect(state.submittingOrder, isFalse);
      expect(state.openAlgoOrders, isEmpty);
      expect(state.lastNotice, isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness strategy row separates fills and working quantity with exact precision',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _Api()..rows = [model(row(status: 'CANCEL_REQUESTED'))];
        final state = _State(api);
        state.openAlgoOrders = api.rows;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: AnimatedBuilder(
                animation: state,
                builder: (_, _) => SingleChildScrollView(
                  child: PrivateTradingPanel(state: state),
                ),
              ),
            ),
          ),
        );
        final tab = find.widgetWithText(ChoiceChip, '止盈止损 / 策略 (1)');
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(find.text('价格：45035996273704.965 USDT'), findsOneWidget);
        expect(find.text('已成交：0.0005 BTC / 总量：0.002 BTC'), findsOneWidget);
        expect(find.text('挂单中：0.0002 BTC · 每片：0.0002 BTC'), findsOneWidget);
        expect(find.text('#9007199254740993 · 取消中'), findsOneWidget);
        expect(find.text('继续撤销'), findsOneWidget);
        expect(find.textContaining('CROSS'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'unknown instrument never inherits selected precision; query errors remain visible',
    (tester) async {
      final api = _Api()
        ..rows = [
          model({...row(), 'instrumentId': '999'}),
        ];
      final state = _State(api)
        ..onlyCurrentTradingPair = false
        ..openAlgoOrders = api.rows;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: state,
              builder: (_, _) => SingleChildScrollView(
                child: PrivateTradingPanel(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '止盈止损 / 策略 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('合约资料未就绪，暂不显示价格和数量'), findsOneWidget);
      expect(find.text('价格：—'), findsOneWidget);
      expect(find.textContaining('45035996273704.965'), findsNothing);
      api.failure = ApiException(503, 'view unavailable');
      await tester.tap(find.byKey(const ValueKey('refresh-algo-orders')));
      await tester.pumpAndSettle();
      expect(find.textContaining('加载算法单失败'), findsOneWidget);
      expect(find.text('暂无止盈止损或策略委托'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Http extends HttpOverrides {}

class _Api extends TestApiClient {
  _Api() : super(const AppConfig(websocketUrl: ''));
  List<AlgoOrderModel> rows = [];
  Object? failure;
  Instrument? metadata;
  final metadataReads = <(String, ProductMode)>[];
  Future<List<AlgoOrderModel>>? nextRead;
  Future<AlgoOrderModel>? nextCancel;
  final reads = <(int, String?, String?)>[];
  final cancels = <(int, int, String?)>[];
  @override
  Future<OpenOrdersPage> openOrders(
    int userId, {
    String? symbol,
    String? productLine,
    String? cursor,
    int limit = 100,
  }) async => const OpenOrdersPage(
    orders: [],
    nextCursor: null,
    hasMore: false,
    sort: 'orderId.desc',
    limit: 100,
  );
  @override
  Future<Instrument> instrumentLatest(String id, ProductMode product) async {
    metadataReads.add((id, product));
    if (metadata == null) throw const FormatException('metadata unavailable');
    return metadata!;
  }

  @override
  Future<List<AlgoOrderModel>> openAlgoOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    reads.add((userId, symbol, productLine));
    final next = nextRead;
    nextRead = null;
    if (next != null) return next;
    if (failure != null) throw failure!;
    return rows;
  }

  @override
  Future<AlgoOrderModel> cancelAlgoOrder(
    int userId,
    int algoOrderId, {
    String? productLine,
  }) async {
    cancels.add((userId, algoOrderId, productLine));
    return nextCancel ?? model(row(status: 'CANCELED'));
  }
}

class _State extends AppState {
  _State(_Api api)
    : super(
        apiClient: api,
        initialSession: sessionForTest,
        sessionStore: MemorySessionStore(),
        settingsStore: MemorySettings(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [instrument(), instrument('869', 'ETH-USDT')],
      ) {
    mode = ProductMode.spot;
  }
  static final sessionForTest = authSession(1);
  @override
  Future<void> refreshPrivateData() async {
    // Authentication is tested through the real flow; individual tests control
    // their trading reads explicitly so a login cannot consume a held response.
    if (!auth.loading) await super.refreshPrivateData();
  }

  @override
  Future<void> refreshProductAvailability() async {}
  @override
  Future<void> refreshAnnouncements() async {}
  @override
  Future<void> refreshWallet() async {}
  @override
  Future<void> refreshOrderTerms() async {}
}
