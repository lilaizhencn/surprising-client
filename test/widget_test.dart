import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  testWidgets('renders the mobile client shell without network', (
    tester,
  ) async {
    final state = AppState(offline: true);

    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );

    expect(find.text('Surprising'), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('交易'), findsWidgets);
  });

  testWidgets('opens the deposit coin and network selection flow', (
    tester,
  ) async {
    final state = AppState(offline: true)
      ..session = const AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'demo_user',
          email: 'demo@example.com',
          status: 'ACTIVE',
        ),
        accessToken: 'access',
        refreshToken: 'refresh',
      )
      ..walletPortfolio = WalletPortfolio.fromJson({
        'generatedAt': '2026-07-06T00:00:00Z',
        'assetCount': 1,
        'assets': [
          {
            'symbol': 'USDT',
            'availableBalance': '12.5',
            'lockedBalance': 0,
            'totalBalance': '12.5',
            'chains': [
              {
                'chain': 'ETH',
                'symbol': 'USDT',
                'network': 'Ethereum',
                'nativeAsset': false,
                'nativeSymbol': 'ETH',
                'availableBalance': '12.5',
                'lockedBalance': 0,
                'totalBalance': '12.5',
                'addresses': const [],
              },
            ],
          },
        ],
      });

    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsWidgets);
    expect(find.text('行情'), findsWidgets);
    expect(find.text('合约'), findsWidgets);
    await tester.tap(find.text('充币').first);
    await tester.pumpAndSettle();

    expect(find.text('选择资产'), findsOneWidget);
    expect(find.text('USDT'), findsWidgets);

    await tester.tap(find.text('USDT').first);
    await tester.pumpAndSettle();

    expect(find.text('选择网络'), findsOneWidget);
    expect(find.text('Ethereum (ERC20)'), findsOneWidget);
  });

  testWidgets('shows fallback deposit networks for an empty wallet', (
    tester,
  ) async {
    final state = AppState(offline: true)
      ..session = const AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'demo_user',
          email: 'demo@example.com',
          status: 'ACTIVE',
        ),
        accessToken: 'access',
        refreshToken: 'refresh',
      );

    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('充币').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USDT').first);
    await tester.pumpAndSettle();

    expect(find.text('选择网络'), findsOneWidget);
    expect(find.text('Surprising Chain (USDT)'), findsOneWidget);
    expect(find.text('Tron (TRC20)'), findsOneWidget);
    expect(find.text('Ethereum (ERC20)'), findsOneWidget);
  });

  testWidgets('renders the deposit address show page details', (tester) async {
    final state = AppState(offline: true)
      ..session = const AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'demo_user',
          email: 'demo@example.com',
          status: 'ACTIVE',
        ),
        accessToken: 'access',
        refreshToken: 'refresh',
      )
      ..walletDepositAddress = const WalletDepositAddress(
        chain: 'Surprising Chain',
        symbol: 'USDT',
        network: 'Surprising Chain',
        standard: 'SPEX',
        nativeAsset: false,
        nativeSymbol: 'SPEX',
        address: 'SX00861E9d78139CD68Ae6C78A5b5F7384325e60950',
        qrCodeDataUrl: '',
        ownerAddress: '',
        accountId: '1',
        addressIndex: 0,
        memo: '',
        warnings: [],
      );

    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RechargeAddressPage(symbol: 'USDT', chain: 'Surprising Chain'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('充值 USDT'), findsOneWidget);
    expect(
      find.text('SX00861E9d78139CD68Ae6C78A5b5F7384325e60950'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();

    expect(find.text('Surprising Chain (USDT)'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsNWidgets(3));
  });

  testWidgets('opens product pages from the trade product selector', (
    tester,
  ) async {
    final state = AppState(offline: true);

    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );

    await tester.tap(find.text('合约').last);
    await tester.pumpAndSettle();

    expect(find.text('交易产品页'), findsOneWidget);
    expect(find.text('U本位永续'), findsWidgets);
    expect(state.mode, ProductMode.linear);

    await tester.tap(find.text('交易产品页'));
    await tester.pumpAndSettle();
    expect(find.text('打开产品页'), findsOneWidget);
    await tester.tap(find.text('币本位永续').last);
    await tester.pumpAndSettle();
    expect(state.mode, ProductMode.inverse);

    await tester.tap(find.text('交易产品页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('U本位交割').last);
    await tester.pumpAndSettle();
    expect(state.mode, ProductMode.linearDelivery);

    await tester.tap(find.text('交易产品页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('期权').last);
    await tester.pumpAndSettle();
    expect(state.mode, ProductMode.option);

    await tester.tap(find.text('交易产品页'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('现货').last);
    await tester.pumpAndSettle();
    expect(state.mode, ProductMode.spot);
  });

  test('converts price decimals to backend ticks', () {
    final instrument = fallbackInstruments().first;

    expect(instrument.ticksFromPrice(65000), 650000);
    expect(instrument.priceFromTicks(650000), 65000);
  });

  test('maps trading modes to backend account types', () {
    expect(ProductMode.spot.accountType, 'SPOT');
    expect(ProductMode.linear.accountType, 'USDT_PERPETUAL');
    expect(ProductMode.inverse.accountType, 'COIN_PERPETUAL');
    expect(ProductMode.linearDelivery.accountType, 'USDT_DELIVERY');
    expect(ProductMode.inverseDelivery.accountType, 'COIN_DELIVERY');
    expect(ProductMode.option.accountType, 'OPTION');
  });

  test('maps trading modes to backend product lines', () {
    expect(ProductMode.spot.productLine, 'SPOT');
    expect(ProductMode.linear.productLine, 'LINEAR_PERPETUAL');
    expect(ProductMode.inverse.productLine, 'INVERSE_PERPETUAL');
    expect(ProductMode.linearDelivery.productLine, 'LINEAR_DELIVERY');
    expect(ProductMode.inverseDelivery.productLine, 'INVERSE_DELIVERY');
    expect(ProductMode.option.productLine, 'OPTION');
  });

  test(
    'reconnects realtime subscriptions when opening another product page',
    () async {
      final publicRealtime = _RecordingRealtimeClient();
      final privateRealtime = _RecordingRealtimeClient();
      final state = AppState(
        apiClient: _RealtimeSwitchApiClient(),
        publicRealtimeClient: publicRealtime,
        privateRealtimeClient: privateRealtime,
      );

      await state.selectMode(ProductMode.option);

      expect(state.mode, ProductMode.option);
      expect(publicRealtime.closeCount, 1);
      expect(publicRealtime.connectCount, 1);
      expect(
        publicRealtime.subscriptions.any(
          (item) =>
              item.channel == 'depth' &&
              item.symbol == state.selectedSymbol &&
              item.productLine == 'OPTION',
        ),
        isTrue,
      );
      expect(
        publicRealtime.subscriptions.any(
          (item) => item.productLine == 'LINEAR_PERPETUAL',
        ),
        isFalse,
      );
    },
  );

  test(
    'subscribes authenticated derivative sessions to trigger updates',
    () async {
      final privateRealtime = _RecordingRealtimeClient();
      final state = AppState(
        apiClient: _PrivateRealtimeApiClient(),
        privateRealtimeClient: privateRealtime,
      );

      await state.login('demo_user', 'password');

      expect(
        privateRealtime.subscriptions.any(
          (item) =>
              item.channel == 'triggerOrders' &&
              item.symbol == state.selectedSymbol &&
              item.productLine == 'LINEAR_PERPETUAL',
        ),
        isTrue,
      );
    },
  );

  test('parses expiring and option instrument metadata', () {
    final delivery = Instrument.fromJson({
      'symbol': 'BTC-USDT-260925',
      'instrumentType': 'DELIVERY',
      'contractType': 'LINEAR_DELIVERY',
      'expiryTime': '2026-09-25T08:00:00Z',
      'deliveryTime': '2026-09-25T09:00:00Z',
      'underlyingSymbol': 'BTC-USDT',
      'settlementMethod': 'CASH',
    });

    expect(delivery.mode, ProductMode.linearDelivery);
    expect(delivery.contractLabel, '交割');
    expect(delivery.expiryTime?.toUtc().year, 2026);
    expect(delivery.underlyingSymbol, 'BTC-USDT');

    final option = Instrument.fromJson({
      'symbol': 'BTC-USDT-260925-70000-C',
      'instrumentType': 'OPTION',
      'contractType': 'VANILLA_OPTION',
      'strikePriceUnits': 7000000000000,
      'optionType': 'CALL',
      'optionExerciseStyle': 'EUROPEAN',
      'settlementMethod': 'CASH',
    });

    expect(option.mode, ProductMode.option);
    expect(option.contractLabel, '期权');
    expect(option.strikePrice, 70000);
    expect(option.optionExerciseStyle, 'EUROPEAN');
  });

  test('scopes selected instrument lookup by current product mode', () {
    final state = AppState(offline: true)
      ..instruments = [
        Instrument.fromJson({
          'symbol': 'BTC-USDT',
          'instrumentType': 'PERPETUAL',
          'contractType': 'LINEAR_PERPETUAL',
        }),
        Instrument.fromJson({
          'symbol': 'BTC-USDT',
          'instrumentType': 'SPOT',
          'contractType': 'SPOT',
        }),
      ]
      ..mode = ProductMode.spot
      ..selectedSymbol = 'BTC-USDT';

    expect(state.selectedInstrument.mode, ProductMode.spot);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'productLine': 'LINEAR_PERPETUAL',
      'data': {'symbol': 'BTC-USDT', 'price': 65000.0},
    });
    expect(state.latestPrices, isNot(contains('BTC-USDT')));

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'productLine': 'SPOT',
      'data': {'symbol': 'BTC-USDT', 'price': 65001.0},
    });
    expect(state.latestPrices['BTC-USDT'], 65001.0);
  });

  test('spot private refresh skips derivative-only product services', () async {
    final api = _SpotRefreshApiClient();
    final state = AppState(apiClient: api)
      ..session = const AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'demo_user',
          email: 'demo@example.com',
          status: 'ACTIVE',
        ),
        accessToken: 'access',
        refreshToken: 'refresh',
      )
      ..mode = ProductMode.spot
      ..selectedSymbol = fallbackInstruments()
          .firstWhere((instrument) => instrument.mode == ProductMode.spot)
          .symbol;

    await state.refreshPrivateData();

    expect(api.productBalanceProductLine, 'SPOT');
    expect(api.openOrdersProductLine, 'SPOT');
    expect(api.derivativeCalls, isZero);
    expect(state.positionMode, 'ONE_WAY');
    expect(state.accountRisk, isNull);
    expect(state.positionRisks, isEmpty);
    expect(state.liquidationOrders, isEmpty);
  });

  test('loads open-order cursor pages and removes cancel-requested orders', () async {
    final api = _SpotRefreshApiClient();
    final spotSymbol = fallbackInstruments()
        .firstWhere((instrument) => instrument.mode == ProductMode.spot)
        .symbol;
    api.openOrderPages.addAll([
      OpenOrdersPage(
        orders: [_openOrder(11, spotSymbol), _openOrder(10, spotSymbol)],
        nextCursor: 'cursor-10',
        hasMore: true,
        sort: 'orderId.desc',
        limit: 100,
      ),
      OpenOrdersPage(
        orders: [_openOrder(10, spotSymbol), _openOrder(9, spotSymbol)],
        nextCursor: null,
        hasMore: false,
        sort: 'orderId.desc',
        limit: 100,
      ),
    ]);
    final state = AppState(apiClient: api)
      ..session = const AuthSession(
        user: AuthUser(
          userId: 1,
          username: 'demo_user',
          email: 'demo@example.com',
          status: 'ACTIVE',
        ),
        accessToken: 'access',
        refreshToken: 'refresh',
      )
      ..mode = ProductMode.spot
      ..selectedSymbol = spotSymbol;

    await state.refreshPrivateData();
    await state.loadMoreOpenOrders();

    expect(api.openOrderCursors, [null, 'cursor-10']);
    expect(state.openOrders.map((order) => order.orderId), [11, 10, 9]);
    expect(state.openOrdersHasMore, isFalse);
    expect(state.openOrdersNextCursor, isNull);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'orders',
      'productLine': 'SPOT',
      'data': _openOrderJson(10, spotSymbol, status: 'CANCEL_REQUESTED'),
    });

    expect(state.openOrders.map((order) => order.orderId), [11, 9]);
  });

  test('parses wallet portfolio and order records', () {
    final portfolio = WalletPortfolio.fromJson({
      'generatedAt': '2026-07-03T00:00:00Z',
      'assetCount': 1,
      'assets': [
        {
          'symbol': 'USDT',
          'availableBalance': '12.5',
          'lockedBalance': 0,
          'totalBalance': '12.5',
          'chains': [
            {
              'chain': 'ETH',
              'symbol': 'USDT',
              'network': 'sepolia',
              'nativeAsset': false,
              'nativeSymbol': 'ETH',
              'availableBalance': '12.5',
              'lockedBalance': 0,
              'totalBalance': '12.5',
              'addresses': [
                {'chain': 'ETH', 'symbol': 'USDT', 'address': '0xabc'},
              ],
            },
          ],
        },
      ],
    });
    final order = WalletOrderRecord.fromJson({
      'type': 'WITHDRAW',
      'ref_no': 'WD-1',
      'chain': 'ETH',
      'asset_symbol': 'USDT',
      'amount': '1.25',
      'fee': '0.01',
      'status': 'PENDING_REVIEW',
    });

    expect(portfolio.assetCount, 1);
    expect(portfolio.assets.first.chains.first.chain, 'ETH');
    expect(order.refNo, 'WD-1');
    expect(order.symbol, 'USDT');
    expect(order.amount, 1.25);
  });

  test('parses trigger orders with position side', () {
    final order = TriggerOrderModel.fromJson({
      'triggerOrderId': 7,
      'symbol': 'BTC-USDT',
      'side': 'SELL',
      'triggerType': 'TAKE_PROFIT',
      'triggerPriceTicks': 705000,
      'orderType': 'MARKET',
      'timeInForce': 'IOC',
      'quantitySteps': 3,
      'marginMode': 'ISOLATED',
      'positionSide': 'LONG',
      'status': 'NEW',
    });

    expect(order.triggerOrderId, 7);
    expect(order.positionSide, 'LONG');
    expect(triggerTypeLabel(order.triggerType), '止盈');
    expect(triggerCloseLabel(order.side, order.positionSide), '平多');
  });

  test('applies pushed trigger snapshots and removes terminal orders', () {
    Map<String, dynamic> orderJson(String status) => {
      'triggerOrderId': 7,
      'symbol': 'BTC-USDT',
      'side': 'SELL',
      'triggerType': 'STOP_LOSS',
      'triggerCondition': 'LESS_OR_EQUAL',
      'triggerPriceTicks': 605000,
      'orderType': 'MARKET',
      'timeInForce': 'IOC',
      'priceTicks': 0,
      'quantitySteps': 3,
      'marginMode': 'CROSS',
      'positionSide': 'NET',
      'status': status,
    };
    Map<String, dynamic> event(int eventId, String status) => {
      'op': 'event',
      'channel': 'triggerOrders',
      'symbol': 'BTC-USDT',
      'productLine': 'LINEAR_PERPETUAL',
      'data': {
        'eventId': eventId,
        'productLine': 'LINEAR_PERPETUAL',
        'order': orderJson(status),
      },
    };
    final state = AppState(offline: true)
      ..openTriggerOrders = [TriggerOrderModel.fromJson(orderJson('PENDING'))];

    state.handleRealtimeMessage(event(10, 'CANCELED'));

    expect(state.openTriggerOrders, isEmpty);

    state.handleRealtimeMessage(event(9, 'PENDING'));
    expect(
      state.openTriggerOrders,
      isEmpty,
      reason: 'older replay must not restore a terminal order',
    );

    state.handleRealtimeMessage(event(11, 'PENDING'));
    expect(state.openTriggerOrders.single.triggerOrderId, 7);
    expect(state.openTriggerOrders.single.status, 'PENDING');
  });

  test('parses amend order batch responses', () {
    Map<String, dynamic> orderJson({
      required int orderId,
      required int priceTicks,
      required int quantitySteps,
      required int remainingQuantitySteps,
      required String status,
      bool postOnly = false,
    }) {
      return {
        'orderId': orderId,
        'symbol': 'BTC-USDT',
        'side': 'BUY',
        'orderType': 'LIMIT',
        'timeInForce': 'GTC',
        'priceTicks': priceTicks,
        'quantitySteps': quantitySteps,
        'executedQuantitySteps': 0,
        'remainingQuantitySteps': remainingQuantitySteps,
        'marginMode': 'CROSS',
        'positionSide': 'NET',
        'status': status,
        'reduceOnly': false,
        'postOnly': postOnly,
      };
    }

    final result = AmendOrderBatchResult.fromJson({
      'requested': 2,
      'completed': 1,
      'failed': 1,
      'results': [
        {
          'index': 0,
          'success': true,
          'message': 'cancel requested; replacement submitted',
          'amend': {
            'originalOrder': orderJson(
              orderId: 11,
              priceTicks: 650000,
              quantitySteps: 2,
              remainingQuantitySteps: 0,
              status: 'CANCEL_REQUESTED',
            ),
            'replacementOrder': orderJson(
              orderId: 12,
              priceTicks: 649000,
              quantitySteps: 1,
              remainingQuantitySteps: 1,
              status: 'ACCEPTED',
              postOnly: true,
            ),
            'cancelRequested': true,
            'message': 'cancel requested; replacement submitted',
          },
        },
        {
          'index': 1,
          'success': false,
          'message': 'userId and orderId must be positive',
        },
      ],
    });

    expect(result.completed, 1);
    expect(result.failed, 1);
    expect(result.results.first.amend?.cancelRequested, isTrue);
    expect(result.results.first.amend?.replacementOrder.priceTicks, 649000);
    expect(result.results.first.amend?.replacementOrder.postOnly, isTrue);
    expect(result.results.last.amend, isNull);
  });

  test('updates latest price from public trade events', () {
    final state = AppState(offline: true);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'symbol': 'BTC-USDT',
      'productLine': 'LINEAR_PERPETUAL',
      'data': {'priceTicks': 650123},
    });

    expect(state.latestPriceFor(state.selectedInstrument), 65012.3);
  });

  test('ignores realtime events without product line', () {
    final state = AppState(offline: true);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'symbol': 'BTC-USDT',
      'data': {'priceTicks': 650123},
    });

    expect(state.latestPrices, isNot(contains('BTC-USDT')));
  });

  test('ignores realtime market events from another product line', () {
    final state = AppState(offline: true);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'symbol': 'BTC-USDT',
      'productLine': 'OPTION',
      'data': {'priceTicks': 650123},
    });

    expect(state.latestPrices, isNot(contains('BTC-USDT')));
  });

  test('merges depth deltas into the existing order book', () {
    final state = AppState(offline: true);
    state.orderBook = const OrderBook(
      symbol: 'BTC-USDT',
      sequence: 10,
      bids: [
        OrderBookLevel(priceTicks: 650000, quantitySteps: 5, orderCount: 1),
        OrderBookLevel(priceTicks: 649990, quantitySteps: 2, orderCount: 1),
      ],
      asks: [
        OrderBookLevel(priceTicks: 650010, quantitySteps: 4, orderCount: 1),
      ],
    );

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'depth',
      'symbol': 'BTC-USDT',
      'productLine': 'LINEAR_PERPETUAL',
      'data': {
        'updateType': 'DELTA',
        'sequence': 11,
        'previousSequence': 10,
        'depth': 50,
        'bids': [
          {'priceTicks': 650000, 'quantitySteps': 0, 'orderCount': 0},
          {'priceTicks': 650005, 'quantitySteps': 8, 'orderCount': 2},
        ],
        'asks': [
          {'priceTicks': 650010, 'quantitySteps': 6, 'orderCount': 3},
        ],
      },
    });

    expect(state.orderBook.sequence, 11);
    expect(state.orderBook.bids.map((level) => level.priceTicks), [
      650005,
      649990,
    ]);
    expect(state.orderBook.bids.first.quantitySteps, 8);
    expect(state.orderBook.asks.first.quantitySteps, 6);
  });

  test('ignores realtime depth deltas from another product line', () {
    final state = AppState(offline: true);
    state.orderBook = const OrderBook(
      symbol: 'BTC-USDT',
      sequence: 10,
      bids: [
        OrderBookLevel(priceTicks: 650000, quantitySteps: 5, orderCount: 1),
      ],
      asks: [
        OrderBookLevel(priceTicks: 650010, quantitySteps: 4, orderCount: 1),
      ],
    );

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'depth',
      'symbol': 'BTC-USDT',
      'productLine': 'OPTION',
      'data': {
        'updateType': 'DELTA',
        'sequence': 11,
        'previousSequence': 10,
        'depth': 50,
        'bids': [
          {'priceTicks': 650000, 'quantitySteps': 0, 'orderCount': 0},
        ],
        'asks': [
          {'priceTicks': 650010, 'quantitySteps': 9, 'orderCount': 2},
        ],
      },
    });

    expect(state.orderBook.sequence, 10);
    expect(state.orderBook.bids.first.quantitySteps, 5);
    expect(state.orderBook.asks.first.quantitySteps, 4);
  });

  test('ignores realtime account risk from another product line', () {
    final state = AppState(offline: true)
      ..mode = ProductMode.linear
      ..selectedSymbol = 'BTC-USDT';

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'accountRisk',
      'productLine': 'OPTION',
      'data': {
        'userId': 1001,
        'accountType': 'OPTION',
        'settleAsset': 'USDT',
        'riskStatus': 'NORMAL',
        'totalEquityUnits': 100,
        'totalMaintenanceMarginUnits': 10,
        'marginRatioPpm': 100000,
        'eventTime': '2026-07-01T00:00:00Z',
      },
    });

    expect(state.accountRisk, isNull);
  });
}

class _SpotRefreshApiClient extends ApiClient {
  _SpotRefreshApiClient() : super(const AppConfig());

  String? productBalanceProductLine;
  String? openOrdersProductLine;
  final List<OpenOrdersPage> openOrderPages = [];
  final List<String?> openOrderCursors = [];
  int derivativeCalls = 0;

  @override
  Future<List<ProductBalance>> productBalances(
    int userId, {
    String? accountType,
    String? productLine,
  }) async {
    productBalanceProductLine = productLine;
    return const [];
  }

  @override
  Future<OpenOrdersPage> openOrders(
    int userId, {
    String? symbol,
    String? productLine,
    String? cursor,
    int limit = 100,
  }) async {
    openOrdersProductLine = productLine;
    openOrderCursors.add(cursor);
    if (openOrderPages.isNotEmpty) return openOrderPages.removeAt(0);
    return OpenOrdersPage(
      orders: const [],
      nextCursor: null,
      hasMore: false,
      sort: 'orderId.desc',
      limit: limit,
    );
  }

  @override
  Future<List<Position>> positions(int userId, {String? productLine}) async {
    derivativeCalls++;
    return const [];
  }

  @override
  Future<List<AlgoOrderModel>> openAlgoOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    derivativeCalls++;
    return const [];
  }

  @override
  Future<List<TriggerOrderModel>> openTriggerOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    derivativeCalls++;
    return const [];
  }

  @override
  Future<String> positionMode(int userId, {String? productLine}) async {
    derivativeCalls++;
    return 'HEDGE';
  }

  @override
  Future<AccountRisk?> accountRisk(
    int userId,
    String settleAsset, {
    String? accountType,
    String? productLine,
  }) async {
    derivativeCalls++;
    return null;
  }

  @override
  Future<List<PositionRisk>> positionRisks(
    int userId, {
    String? productLine,
  }) async {
    derivativeCalls++;
    return const [];
  }

  @override
  Future<List<LiquidationOrder>> liquidationOrders(
    int userId, {
    String? productLine,
  }) async {
    derivativeCalls++;
    return const [];
  }

  @override
  Future<WalletPortfolio> walletPortfolio(
    int userId, {
    bool hideZero = false,
  }) async {
    return WalletPortfolio.empty();
  }

  @override
  Future<List<WalletOrderRecord>> walletOrders(
    int userId, {
    int limit = 30,
  }) async {
    return const [];
  }
}

OrderModel _openOrder(int orderId, String symbol) {
  return OrderModel.fromJson(_openOrderJson(orderId, symbol));
}

Map<String, dynamic> _openOrderJson(
  int orderId,
  String symbol, {
  String status = 'ACCEPTED',
}) {
  return {
    'orderId': orderId,
    'symbol': symbol,
    'side': 'BUY',
    'orderType': 'LIMIT',
    'timeInForce': 'GTC',
    'priceTicks': 100,
    'quantitySteps': 10,
    'executedQuantitySteps': 0,
    'remainingQuantitySteps': 10,
    'marginMode': 'CROSS',
    'positionSide': 'NET',
    'status': status,
    'reduceOnly': false,
    'postOnly': false,
  };
}

class _PrivateRealtimeApiClient extends _SpotRefreshApiClient {
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    return AuthSession(
      user: AuthUser(
        userId: 1001,
        username: username,
        email: 'demo@example.com',
        status: 'ACTIVE',
      ),
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );
  }
}

class _RealtimeSwitchApiClient extends ApiClient {
  _RealtimeSwitchApiClient() : super(const AppConfig());

  @override
  Future<OrderBook> orderBook(
    String symbol, {
    int depth = 50,
    String? productLine,
  }) async {
    final instrument = fallbackInstruments().firstWhere(
      (item) => item.symbol == symbol && item.mode.productLine == productLine,
      orElse: () => fallbackInstruments().first,
    );
    return fallbackOrderBook(instrument);
  }

  @override
  Future<List<Candle>> candles(
    String symbol,
    String period, {
    String? productLine,
  }) async {
    return fallbackCandles();
  }
}

class _RecordingRealtimeClient extends RealtimeClient {
  _RecordingRealtimeClient() : super(const AppConfig());

  int connectCount = 0;
  int closeCount = 0;
  final List<_RecordedSubscription> subscriptions = [];

  @override
  Future<void> connect({
    int? userId,
    String? accessToken,
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(Object error) onError,
    void Function()? onDone,
  }) async {
    connectCount++;
  }

  @override
  void subscribe(
    String channel, {
    String? symbol,
    String? period,
    String? productLine,
  }) {
    subscriptions.add(
      _RecordedSubscription(
        channel: channel,
        symbol: symbol,
        period: period,
        productLine: productLine,
      ),
    );
  }

  @override
  Future<void> close() async {
    closeCount++;
    subscriptions.clear();
  }
}

class _RecordedSubscription {
  const _RecordedSubscription({
    required this.channel,
    this.symbol,
    this.period,
    this.productLine,
  });

  final String channel;
  final String? symbol;
  final String? period;
  final String? productLine;
}
