import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

// Layout fixtures only; these tests never send an order or replace live data.
Instrument _instrument() => Instrument.fromJson({
  'instrumentId': '604',
  'symbol': 'BTC-USDT',
  'contractType': 'LINEAR_PERPETUAL',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'priceTickUnits': 10000000,
  'quantityStepUnits': 100000,
  'pricePrecision': 1,
  'status': 'TRADING',
});

Finder _input(TextEditingController controller) => find.byWidgetPredicate(
  (widget) => widget is TextField && identical(widget.controller, controller),
);

Future<void> _ticket(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
  required TextEditingController price,
  required TextEditingController quantity,
  required AppState state,
  double scale = 1,
  ValueChanged<bool>? onBbo,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 376,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 12,
                    child: OrderTicket(
                      side: 'BUY',
                      orderType: 'LIMIT',
                      timeInForce: 'GTC',
                      marginMode: 'CROSS',
                      positionMode: 'ONE_WAY',
                      positionSide: 'NET',
                      reduceOnly: false,
                      postOnly: false,
                      bboEnabled: false,
                      bboPriceMode: 'OPPONENT_1',
                      onBboEnabled: onBbo ?? (_) {},
                      onBboPriceMode: (_) {},
                      priceController: price,
                      quantityController: quantity,
                      instrument: _instrument(),
                      loggedIn: false,
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
                  const SizedBox(width: 6),
                  const Expanded(flex: 9, child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [320.0, 392.0, 430.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '$width $brightness scale=$scale shows the entire price without horizontal clipping',
          (tester) async {
            final price = TextEditingController(
              text: scale == 1 ? '1282044.5' : '82044.5',
            );
            final quantity = TextEditingController(text: '100000');
            final state = AppState(offline: true);
            addTearDown(state.dispose);
            addTearDown(price.dispose);
            addTearDown(quantity.dispose);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await _ticket(
              tester,
              width: width,
              brightness: brightness,
              price: price,
              quantity: quantity,
              state: state,
              scale: scale,
            );
            for (final controller in [price, quantity]) {
              final editable = find.descendant(
                of: _input(controller),
                matching: find.byType(EditableText),
              );
              final render = tester
                  .state<EditableTextState>(editable)
                  .renderEditable;
              expect(
                render.maxScrollExtent,
                0,
                reason:
                    '${controller.text} must fit the actual editable viewport',
              );
            }
            expect(
              tester.getTopLeft(find.byType(BestPriceButton)).dy,
              lessThan(tester.getTopLeft(_input(price)).dy),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'compact price controls retain stepping, best ask and keyboard editing',
    (tester) async {
      final price = TextEditingController(text: '82044.5');
      final quantity = TextEditingController(text: '2');
      final state = AppState(offline: true)
        ..orderBook = OrderBook(
          symbol: 'BTC-USDT',
          sequence: 1,
          bids: const [
            OrderBookLevel(
              priceTicks: 820444,
              quantitySteps: 10,
              orderCount: 1,
            ),
          ],
          asks: const [
            OrderBookLevel(
              priceTicks: 820451,
              quantitySteps: 10,
              orderCount: 1,
            ),
          ],
        );
      addTearDown(state.dispose);
      addTearDown(price.dispose);
      addTearDown(quantity.dispose);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await _ticket(
        tester,
        width: 392,
        brightness: Brightness.dark,
        price: price,
        quantity: quantity,
        state: state,
      );
      await tester.tap(
        find.descendant(of: _input(price), matching: find.byTooltip('增加')),
      );
      await tester.pumpAndSettle();
      expect(price.text, '82044.6');
      await tester.tap(
        find.descendant(of: _input(price), matching: find.byTooltip('减少')),
      );
      await tester.pumpAndSettle();
      expect(price.text, '82044.5');
      await tester.tap(find.byType(BestPriceButton));
      await tester.pumpAndSettle();
      expect(price.text, '82045.1');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.tap(_input(price));
      await tester.enterText(_input(price), '82045.2');
      await tester.pumpAndSettle();
      expect(price.text, '82045.2');
      expect(tester.takeException(), isNull);
    },
  );
}
