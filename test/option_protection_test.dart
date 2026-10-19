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

const session = AuthSession(
  user: AuthUser(userId: 1, username: 'option', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);
Instrument contract({String status = 'TRADING'}) => Instrument.fromJson({
  'instrumentId': '74',
  'symbol': 'BTC-CALL-50000',
  'productLine': 'OPTION',
  'instrumentType': 'OPTION',
  'contractType': 'VANILLA_OPTION',
  'status': status,
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
  'quoteScaleUnits': 1000,
  'settleScaleUnits': 1000,
  'priceTickUnits': 5,
  'notionalMultiplierUnits': 1,
  'pricePrecision': 3,
  'changeId': 7,
  'expiryTime': '2035-01-01T00:00:00Z',
});
TriggerOrderDraft leg(
  String type,
  int ticks, {
  String side = 'SELL',
  int quantity = 2,
  String orderType = 'LIMIT',
}) => TriggerOrderDraft(
  side: side,
  triggerType: type,
  triggerPriceTicks: ticks,
  quantitySteps: quantity,
  marginMode: 'CROSS',
  positionSide: 'NET',
  priceSource: 'LAST',
  orderType: orderType,
  priceTicks: orderType == 'LIMIT' ? 20000 : 0,
);
List<TriggerOrderDraft> pair() => [
  leg('TAKE_PROFIT', 24690),
  leg('STOP_LOSS', 19100),
];

void main() {
  test(
    'atomic result never accepts defaulted counts, indexes or success fields',
    () {
      final response = {
        'requested': 2,
        'completed': 2,
        'failed': 0,
        'results': [
          {'index': 0, 'success': true, 'order': {}},
          {'index': 1, 'success': true, 'order': {}},
        ],
      };
      expect(
        () => TriggerOrderBatchResult.fromAtomicOcoJson(
          {...response}..remove('failed'),
        ),
        throwsFormatException,
      );
      expect(
        () => TriggerOrderBatchResult.fromAtomicOcoJson({
          ...response,
          'results': [
            {'success': true, 'order': {}},
            {'index': 1, 'success': true, 'order': {}},
          ],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'atomic pair persists original identities before exactly one canonical product request',
    () async {
      final settings = _Settings(), api = _Api();
      final state = _State(api, settings)..session = session;
      addTearDown(state.dispose);
      api.before = () {
        final stored = asMap(
          asList(jsonDecode(settings.values['pendingTradingOrders']!)).single,
        );
        expect(
          stored['ocoTakeProfitClientId'],
          api.orders.first['clientTriggerOrderId'],
        );
        expect(stored['instrumentId'], '74');
        expect(state.tradingCommandPending, true);
      };
      expect(await state.placeOptionOco(pair()), 2);
      expect(api.posts, 1);
      expect(api.atomic, true);
      expect(api.product, 'OPTION');
      expect(
        api.orders.every(
          (r) =>
              r['instrumentId'] == '74' &&
              !r.containsKey('symbol') &&
              r['priceSource'] == 'LAST',
        ),
        true,
      );
      expect(api.orders.map((r) => r['orderType']), ['LIMIT', 'LIMIT']);
      expect(api.orders.map((r) => r['quantitySteps']), [2, 2]);
      expect(api.orders.map((r) => r['ocoGroupId']).toSet().length, 1);
      expect(state.openTriggerOrders.length, 2);
      expect(state.tradingCommandPending, false);
    },
  );

  test(
    'lost reply survives reconstruction and unknown/terminal reads never resend either leg',
    () async {
      final settings = _Settings(), api = _Api()..lose = true;
      var state = _State(api, settings)..session = session;
      expect(await state.placeOptionOco(pair()), 0);
      final original = state.pendingTradingCommand!.ocoTakeProfitClientId;
      expect(await state.placeOptionOco(pair()), 0);
      state.dispose();
      state = _State(api, settings);
      addTearDown(state.dispose);
      await state.bootstrap();
      state.session = session;
      expect(state.pendingTradingCommand!.ocoTakeProfitClientId, original);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, true);
      api.terminal = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, false);
      expect(api.posts, 1);
      expect(api.reads, 2);
      expect(api.query!['takeProfitClientId'], original);
      expect(
        api.query!['stopLossClientId'],
        api.orders.last['clientTriggerOrderId'],
      );
    },
  );

  test(
    'malformed accepted response and failed lookup retain the original OCO',
    () async {
      final api = _Api()..badReply = true;
      final state = _State(api, _Settings())..session = session;
      addTearDown(state.dispose);
      await state.placeOptionOco(pair());
      api.badRead = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, true);
      expect(api.posts, 1);
    },
  );

  test('storage failure stops the pair before any write', () async {
    final api = _Api();
    final settings = _Settings()..fail = true;
    final state = _State(api, settings)..session = session;
    addTearDown(state.dispose);
    await state.placeOptionOco(pair());
    expect(api.posts, 0);
    expect(state.lastError, contains('未发送'));
  });

  test(
    'lifecycle, leg ordering, close direction and available position reject before writing',
    () async {
      for (final status in ['HALT', 'CLOSED']) {
        final api = _Api();
        final state = _State(
          api,
          _Settings(),
          instrument: contract(status: status),
        )..session = session;
        await state.placeOptionOco(pair());
        expect(api.posts, 0);
        state.dispose();
      }
      final api = _Api();
      final state = _State(api, _Settings())..session = session;
      addTearDown(state.dispose);
      for (final invalid in [
        [leg('TAKE_PROFIT', 100), leg('STOP_LOSS', 200)],
        [
          leg('TAKE_PROFIT', 300, quantity: 5),
          leg('STOP_LOSS', 100, quantity: 5),
        ],
        [
          leg('TAKE_PROFIT', 100, side: 'BUY'),
          leg('STOP_LOSS', 200, side: 'BUY'),
        ],
      ]) {
        await state.placeOptionOco(invalid);
      }
      expect(api.posts, 0);
    },
  );

  test(
    'single condition API sends permanent instrument, actual source and selected limit execution',
    () async {
      final api = _PayloadApi();
      await api.placeTriggerOrder(
        userId: 1,
        instrumentId: '74',
        side: 'SELL',
        triggerType: 'TAKE_PROFIT',
        triggerPriceTicks: 24690,
        quantitySteps: 1,
        marginMode: 'CROSS',
        positionSide: 'NET',
        productLine: 'OPTION',
        priceSource: 'LAST',
        orderType: 'LIMIT',
        priceTicks: 24680,
      );
      expect(api.body, containsPair('instrumentId', '74'));
      expect(api.body!.containsKey('symbol'), false);
      expect(api.body, containsPair('priceSource', 'LAST'));
      expect(api.body, containsPair('timeInForce', 'GTC'));
      expect(api.body, containsPair('priceTicks', 24680));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness OCO source/limit controls use actual three-decimal scale',
      (tester) async {
        final api = _Api();
        final state = _State(api, _Settings())..session = session;
        tester.view.physicalSize = const Size(320, 1600);
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
                  child: TriggerOrderPanel(state: state, marginMode: 'CROSS'),
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
          find.descendant(of: prices.at(0), matching: find.byType(TextField)),
          '123.45',
        );
        await tester.enterText(
          find.descendant(of: prices.at(1), matching: find.byType(TextField)),
          '95.5',
        );
        await tester.tap(find.text('触发源：标记价格'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('触发源：最新成交价').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('触发后市价执行').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('触发后限价执行').last);
        await tester.pumpAndSettle();
        final limit = find.byWidgetPredicate(
          (w) => w is AppTextField && w.label.startsWith('委托限价'),
        );
        await tester.enterText(
          find.descendant(of: limit, matching: find.byType(TextField)),
          '123.4',
        );
        await tester.pump();
        await tester.tap(find.text('一起提交 TP/SL'));
        await tester.pumpAndSettle();
        expect(api.posts, 1);
        expect(api.orders.first['triggerPriceTicks'], 24690);
        expect(api.orders.last['triggerPriceTicks'], 19100);
        expect(api.orders.first['priceTicks'], 24680);
        expect(api.orders.first['orderType'], 'LIMIT');
        expect(api.orders.last['orderType'], 'MARKET');
        expect(api.orders.every((r) => r['priceSource'] == 'LAST'), true);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Api extends ApiClient {
  _Api() : super(const AppConfig());
  int posts = 0, reads = 0;
  bool lose = false,
      terminal = false,
      badReply = false,
      badRead = false,
      atomic = false;
  String? product;
  Map<String, String>? query;
  List<Map<String, dynamic>> orders = [];
  FutureOr<void> Function()? before;
  @override
  Future<TriggerOrderBatchResult> placeTriggerOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    bool atomic = false,
    String? productLine,
  }) async {
    this.orders = orders;
    this.atomic = atomic;
    product = productLine;
    posts++;
    await before?.call();
    if (lose) throw const SocketException('lost reply');
    return TriggerOrderBatchResult.fromJson({
      'requested': 2,
      'completed': 2,
      'failed': 0,
      'results': [
        for (var i = 0; i < 2; i++)
          {
            'index': i,
            'success': true,
            'message': 'completed',
            'order': {
              ...orders[i],
              'instrumentId': badReply ? '99' : orders[i]['instrumentId'],
              'triggerOrderId': 100 + i,
              'status': 'PENDING',
            },
          },
      ],
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
    expect(path, '/api/v1/gateway/trading-trigger/oco-submission');
    expect(productLine, 'OPTION');
    expect(userId, 1);
    this.query = query;
    reads++;
    if (badRead) throw ApiException(503, 'unavailable');
    return {
      'commandId': 'original-command',
      'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
      'code': terminal ? 'NONE' : 'RESULT_UNKNOWN',
    };
  }
}

class _PayloadApi extends ApiClient {
  _PayloadApi() : super(const AppConfig());
  Map<String, dynamic>? body;
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = true,
  }) async {
    expect(path, '/api/v1/gateway/trading-trigger');
    expect(productLine, 'OPTION');
    this.body = body;
    return {...body, 'triggerOrderId': 99, 'status': 'PENDING'};
  }
}

class _State extends AppState {
  _State(ApiClient api, _Settings settings, {Instrument? instrument})
    : super(
        apiClient: api,
        settingsStore: settings,
        sessionStore: _Sessions(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [instrument ?? contract()],
      ) {
    mode = ProductMode.option;
    positions = [
      Position.fromJson({
        'instrumentId': '74',
        'symbol': selectedSymbol,
        'signedQuantitySteps': 4,
        'marginMode': 'CROSS',
        'positionSide': 'NET',
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
