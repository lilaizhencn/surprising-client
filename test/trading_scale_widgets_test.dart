import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

import 'linear_delivery_trading_test.dart' show actor;
import 'transfer_page_test.dart' show MemorySettings;

Instrument contract(
  ProductMode product, {
  int? quoteScale = 1000000,
  int baseScale = 1000000,
}) => Instrument.fromJson({
  'instrumentId': '73',
  'symbol': 'QA-${product.productLine}',
  'productLine': product.productLine,
  'contractType': product.contractType,
  'instrumentType': product.isSpot
      ? 'SPOT'
      : product.isOption
      ? 'OPTION'
      : product.isDelivery
      ? 'DELIVERY'
      : 'PERPETUAL',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
  'priceTickUnits': 10000,
  'pricePrecision': 2,
  'quoteScaleUnits': quoteScale,
  'settleScaleUnits': 1000000,
  'baseScaleUnits': baseScale,
  'quantityStepUnits': 1,
  'notionalMultiplierUnits': 1,
  'status': 'TRADING',
  if (product.isExpiring) 'expiryTime': '2035-01-01T00:00:00Z',
});

void main() {
  for (final product in ProductMode.values) {
    testWidgets('${product.productLine} ticket sends exact six-decimal price', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(392, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CaptureOrderApi();
      final state = TicketState(initialSession: actor, api, contract(product));
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: TradePage())),
        ),
      );
      await tester.pumpAndSettle();
      final vertical = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.byType(OrderTicket),
        250,
        scrollable: vertical.first,
      );
      final ticket = tester.widget<OrderTicket>(find.byType(OrderTicket));
      Finder input(TextEditingController controller) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && identical(widget.controller, controller),
      );
      await tester.enterText(input(ticket.priceController), '1.01');
      await tester.enterText(input(ticket.quantityController), '1');
      final submit = find.byKey(const ValueKey('order-ticket-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.priceTicks, 101);
      expect(api.productLine, product.productLine);
      expect(state.lastError, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320dp ticket keeps order types readable at enlarged font size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = TicketState(CaptureOrderApi(), contract(ProductMode.linear));
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: TradePage()),
        ),
      ),
    );
    final priceField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == '价格 (USDT)',
    );
    await tester.ensureVisible(priceField);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(priceField).dy -
          tester.getBottomLeft(find.byType(BestPriceButton)).dy,
      greaterThanOrEqualTo(10),
    );
    await tester.ensureVisible(find.text('Post Only'));
    await tester.pumpAndSettle();
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Post Only'))
          .didExceedMaxLines,
      isFalse,
    );
    final limitLabel = find.text('限价单');
    await tester.ensureVisible(limitLabel);
    await tester.pumpAndSettle();
    expect(
      tester.renderObject<RenderParagraph>(limitLabel).didExceedMaxLines,
      isFalse,
    );
    await tester.tap(limitLabel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('市价单').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<OrderTicket>(find.byType(OrderTicket)).orderType,
      'MARKET',
    );
    expect(
      tester.renderObject<RenderParagraph>(find.text('市价单')).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing quote scale disables the order and exposes recovery', (
    tester,
  ) async {
    final api = CaptureOrderApi();
    final state = TicketState(
      initialSession: actor,
      api,
      contract(ProductMode.linear, quoteScale: null),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const MaterialApp(home: Scaffold(body: TradePage())),
      ),
    );
    final submit = find.byKey(const ValueKey('order-ticket-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.text('价格精度未同步，请刷新合约资料'), findsOneWidget);
    expect(api.priceTicks, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order prices and average ticks retain their decimal digits', (
    tester,
  ) async {
    final instrument = contract(ProductMode.linear);
    final order = OrderModel(
      orderId: 1,
      symbol: instrument.symbol,
      side: 'BUY',
      orderType: 'LIMIT',
      timeInForce: 'GTC',
      priceTicks: 101,
      quantitySteps: 2,
      executedQuantitySteps: 1,
      remainingQuantitySteps: 1,
      marginMode: 'CROSS',
      positionSide: 'NET',
      status: 'OPEN',
      reduceOnly: false,
      postOnly: false,
      averagePriceTicks: '9007199254740993.01',
      cumulativeFeeUnits: 1000000,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OrderRow(
              order: order,
              instrument: instrument,
              onCancel: null,
            ),
          ),
        ),
      ),
    );
    expect(find.text('1.01'), findsOneWidget);
    expect(find.text('90071992547409.9301'), findsOneWidget);
    expect(find.text('1 USDT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class TicketState extends AppState {
  TicketState(ApiClient api, Instrument instrument, {super.initialSession})
    : super(
        apiClient: api,
        settingsStore: MemorySettings(),
        seedInstruments: [instrument],
      ) {
    mode = instrument.mode;
    selectedSymbol = instrument.symbol;
  }

  @override
  Future<void> refreshPrivateData() async {}
}

class CaptureOrderApi extends ApiClient {
  CaptureOrderApi() : super(const AppConfig());

  int? priceTicks;
  String? productLine;

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
    this.priceTicks = priceTicks;
    this.productLine = productLine;
    return OrderModel(
      orderId: 1,
      symbol: symbol,
      side: side,
      orderType: orderType,
      timeInForce: timeInForce,
      priceTicks: priceTicks,
      quantitySteps: quantitySteps,
      executedQuantitySteps: 0,
      remainingQuantitySteps: quantitySteps,
      marginMode: marginMode,
      positionSide: positionSide,
      status: 'ACCEPTED',
      reduceOnly: reduceOnly,
      postOnly: postOnly,
    );
  }
}
