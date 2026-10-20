import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/models.dart';

Instrument market({int? multiplier = 1}) => Instrument.fromJson({
  'instrumentId': '42',
  'symbol': 'BTC-USDT',
  'instrumentType': 'SPOT',
  'contractType': 'SPOT',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
  'baseScaleUnits': 1000000,
  'quoteScaleUnits': 1000,
  'settleScaleUnits': 1000,
  'priceTickUnits': 5,
  'quantityStepUnits': 200000,
  'notionalMultiplierUnits': multiplier,
  'pricePrecision': 3,
});
OrderModel order({bool high = false, bool marketOrder = false}) =>
    OrderModel.fromJson({
      'orderId': '9007199254740993',
      'symbol': 'BTC-USDT',
      'instrumentId': '42',
      'status': 'OPEN',
      'side': high ? 'SELL' : 'BUY',
      'orderType': marketOrder ? 'MARKET' : 'LIMIT',
      'timeInForce': 'GTC',
      'priceTicks': marketOrder
          ? 0
          : high
          ? 9007199254740993
          : 12345,
      'averagePriceTicks': high ? '9007199254740993.5' : '12344.5',
      'executedValueTicks': high ? '90071992547409935' : '123445',
      'quantitySteps': 25,
      'executedQuantitySteps': 10,
      'remainingQuantitySteps': 15,
      'cumulativeFeeUnits': -1,
    });
void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness spot order shows exact price, sub-tick average and committed notionals',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: SingleChildScrollView(
                child: OrderRow(
                  order: order(),
                  instrument: market(),
                  onCancel: null,
                ),
              ),
            ),
          ),
        );
        for (final value in [
          '61.725',
          '61.7225',
          '308.625 USDT',
          '123.445 USDT',
          '2 BTC',
          '3 BTC',
          '-0.001 USDT',
          '计价币种',
        ]) {
          expect(find.text(value), findsOneWidget);
        }
        expect(find.textContaining('全仓'), findsNothing);
        expect(find.text('只做 Maker'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'large integer spot ticks retain all digits in the active order card',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderRow(
                order: order(high: true),
                instrument: market(),
                onCancel: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('45035996273704.965'), findsOneWidget);
      expect(find.text('45035996273704.9675'), findsOneWidget);
      expect(find.text('90071992547409.935 USDT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'market spot order shows actual filled value while limit notional remains unavailable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderRow(
                order: order(marketOrder: true),
                instrument: market(),
                onCancel: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('123.445 USDT'), findsOneWidget);
      expect(find.text('308.625 USDT'), findsNothing);
    },
  );
  testWidgets(
    'spot values remain unavailable without the contract multiplier',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: OrderRow(
                order: order(),
                instrument: market(multiplier: null),
                onCancel: null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('123.445 USDT'), findsNothing);
      expect(find.text('308.625 USDT'), findsNothing);
      expect(find.text('-0.001 USDT'), findsOneWidget);
    },
  );
}
