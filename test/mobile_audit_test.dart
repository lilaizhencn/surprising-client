import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  testWidgets('long position symbols fit compact screens', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = AppState(offline: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PositionRow(
            state: state,
            position: Position.fromJson({
              'symbol': 'BTC-USDT-261225-100000-C',
              'positionSide': 'LONG',
              'marginMode': 'ISOLATED',
              'signedQuantitySteps': 10,
              'entryPriceTicks': 100,
            }),
          ),
        ),
      ),
    );
    expect(find.text('平仓'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scrollable product tabs switch all six complete pages and reset the ticket',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = AppState(offline: true);
      state.instruments = [
        ...state.instruments,
        Instrument.fromJson({
          'instrumentId': 'inverse-1',
          'symbol': 'BTC-USD',
          'instrumentType': 'PERPETUAL',
          'contractType': 'INVERSE_PERPETUAL',
          'baseAsset': 'BTC',
          'quoteAsset': 'USD',
          'settleAsset': 'BTC',
          'priceTickUnits': 10000000,
          'quantityStepUnits': 1,
          'pricePrecision': 1,
          'quantityPrecision': 0,
        }),
      ];
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.tap(find.text('合约').last);
      await tester.pumpAndSettle();
      final tabs = find.byKey(const ValueKey('product-line-tabs'));
      await tester.drag(tabs, const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('product-tab-option')).hitTestable(),
        findsOneWidget,
      );
      for (final mode in [
        ProductMode.option,
        ProductMode.inverseDelivery,
        ProductMode.linearDelivery,
        ProductMode.inverse,
        ProductMode.linear,
        ProductMode.spot,
      ]) {
        tester
                .widget<OrderTicket>(find.byType(OrderTicket))
                .quantityController
                .text =
            '7';
        final tab = find.byKey(ValueKey('product-tab-${mode.name}'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(state.mode, mode);
        expect(state.selectedInstrument.mode, mode);
        expect(state.orderBook.symbol, state.selectedSymbol);
        expect(
          find.byType(ProductLifecyclePanel),
          mode.isDelivery || mode.isOption ? findsOneWidget : findsNothing,
        );
        await tester.scrollUntilVisible(
          find.byType(OrderTicket),
          200,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(
          tester
              .widget<OrderTicket>(find.byType(OrderTicket))
              .quantityController
              .text,
          isEmpty,
        );
        expect(tester.widget<ChoiceChip>(tab).selected, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'unconfigured product retains its tab with an empty book and no trade ticket',
    (tester) async {
      final state = AppState(offline: true);
      state.instruments = state.instruments
          .where((i) => i.mode == ProductMode.linear)
          .toList();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.tap(find.text('合约').last);
      await tester.pumpAndSettle();
      final tab = find.byKey(const ValueKey('product-tab-option'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(state.mode, ProductMode.option);
      expect(state.selectedSymbol, isEmpty);
      expect(state.selectedInstrument.symbol, isEmpty);
      expect(state.orderBook.bids, isEmpty);
      expect(state.candles, isEmpty);
      expect(find.text('期权暂无可交易合约'), findsOneWidget);
      expect(find.byType(OrderTicket), findsNothing);
    },
  );

  test(
    'refreshing an unavailable product never switches to another product',
    () async {
      final api = InstrumentApi();
      final state = AppState(
        apiClient: api,
        seedInstruments: fallbackInstruments(),
      )..mode = ProductMode.option;
      addTearDown(state.dispose);
      await state.refreshInstruments();
      expect(state.mode, ProductMode.option);
      expect(state.selectedSymbol, isEmpty);
      api.rows = [];
      await state.refreshInstruments();
      expect(state.instruments, isEmpty);
      expect(state.mode, ProductMode.option);
    },
  );

  test(
    'latest market selection wins and stale selection stops follow-up work',
    () async {
      final state = DelayedSelectionState();
      addTearDown(state.dispose);
      final markets = state.instruments
          .where((i) => i.mode == ProductMode.linear)
          .take(2)
          .toList();
      expect(markets, hasLength(2));
      final first = state.selectInstrument(markets[0]);
      final second = state.selectInstrument(markets[1]);
      expect(state.selectedSymbol, markets[1].symbol);
      await Future<void>.delayed(Duration.zero);
      state.requests[markets[1].symbol]!.complete();
      await second;
      state.requests[markets[0].symbol]?.complete();
      await first;
      expect(state.selectedSymbol, markets[1].symbol);
      expect(state.privateRefreshes, [markets[1].symbol]);
    },
  );

  test(
    'trigger batch rejects duplicate submissions and preserves partial success',
    () async {
      final api = TriggerApi();
      final state = TriggerState(api);
      addTearDown(state.dispose);
      final first = state.placeTriggerOrders([draft(), draft()]);
      expect(state.submittingTriggers, isTrue);
      expect(await state.placeTriggerOrders([draft()]), 0);
      expect(api.calls, 1);
      api.first.complete(
        TriggerOrderModel.fromJson({
          'triggerOrderId': 99,
          'symbol': state.selectedSymbol,
          'status': 'PENDING',
        }),
      );
      expect(await first, 1);
      expect(api.calls, 2);
      expect(state.openTriggerOrders.single.triggerOrderId, 99);
      expect(state.lastError, contains('已提交 1 档'));
      expect(state.submittingTriggers, isFalse);
    },
  );

  test(
    'logout during trigger batch prevents remaining requests and stale updates',
    () async {
      final api = TriggerApi();
      final state = TriggerState(api);
      addTearDown(state.dispose);
      final pending = state.placeTriggerOrders([draft(), draft()]);
      state.session = null;
      api.first.complete(
        TriggerOrderModel.fromJson({
          'triggerOrderId': 99,
          'symbol': state.selectedSymbol,
          'status': 'PENDING',
        }),
      );
      expect(await pending, 1);
      expect(api.calls, 1);
      expect(state.openTriggerOrders, isEmpty);
    },
  );

  testWidgets(
    'closing password reset while request is pending does not touch disposed fields',
    (tester) async {
      final state = DelayedResetState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: AuthSheet())),
        ),
      );
      await tester.tap(find.text('忘记密码？'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'test@example.com');
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), 'password');
      await tester.enterText(find.byType(TextField).at(2), '123456');
      await tester.tap(find.text('更新密码'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      state.result.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full depth view updates to empty snapshots without stale levels',
    (tester) async {
      final state = AppState(offline: true);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: FullOrderBookSheet())),
        ),
      );
      expect(find.text('暂无盘口'), findsNothing);
      state.orderBook = OrderBook.empty(state.selectedSymbol);
      state.notifyListeners();
      await tester.pump();
      expect(find.text('暂无盘口'), findsOneWidget);
    },
  );
}

TriggerOrderDraft draft() => const TriggerOrderDraft(
  side: 'SELL',
  triggerType: 'STOP_LOSS',
  triggerPriceTicks: 100,
  quantitySteps: 1,
  marginMode: 'CROSS',
  positionSide: 'NET',
);

class DelayedSelectionState extends AppState {
  DelayedSelectionState() : super(offline: true);
  final requests = <String, Completer<void>>{};
  final privateRefreshes = <String>[];
  @override
  Future<void> refreshPublicData({bool silent = false}) =>
      (requests[selectedSymbol] = Completer<void>()).future;
  @override
  Future<void> refreshPrivateData() async {
    privateRefreshes.add(selectedSymbol);
  }
}

class TriggerState extends AppState {
  TriggerState(ApiClient api) : super(offline: true, apiClient: api) {
    mode = ProductMode.linear;
    selectedSymbol = visibleInstruments.first.symbol;
    session = const AuthSession(
      user: AuthUser(
        userId: 1,
        username: 'test',
        email: 'test@example.com',
        status: 'ACTIVE',
      ),
      accessToken: 'test',
      refreshToken: 'refresh',
    );
    positions = [
      Position(
        symbol: selectedSymbol,
        marginMode: 'CROSS',
        positionSide: 'NET',
        signedQuantitySteps: 2,
        entryPriceTicks: 100,
        realizedPnlUnits: 0,
      ),
    ];
  }
  @override
  Future<void> refreshPrivateData() async {}
}

class TriggerApi extends ApiClient {
  TriggerApi() : super(const AppConfig());
  final first = Completer<TriggerOrderModel>();
  int calls = 0;
  @override
  Future<TriggerOrderModel> placeTriggerOrder({
    required int userId,
    required String symbol,
    required String side,
    required String triggerType,
    required int triggerPriceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    int? activationPriceTicks,
    int? callbackRatePpm,
    String? productLine,
  }) {
    calls++;
    if (calls == 1) return first.future;
    return Future.error(StateError('second request rejected'));
  }
}

class DelayedResetState extends AppState {
  DelayedResetState() : super(offline: true);
  final result = Completer<bool>();
  @override
  Future<bool> requestPasswordReset(String identifier) async => true;
  @override
  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) => result.future;
}

class InstrumentApi extends ApiClient {
  InstrumentApi() : super(const AppConfig());
  List<Instrument> rows = fallbackInstruments()
      .where((i) => i.mode == ProductMode.linear)
      .toList();
  @override
  Future<List<Instrument>> instruments() async => rows;
}
