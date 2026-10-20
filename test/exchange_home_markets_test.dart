import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/exchange_widgets.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/user_scanner_page.dart';

void main() {
  test('only Surprising user identity QR codes are accepted', () {
    expect(isUserQrCode(userQrCode(42)), isTrue);
    for (final code in [
      'https://other.example',
      'surprising://user/0',
      'surprising://user/42?amount=100',
      'surprising://user/9999999999999999999',
    ]) {
      expect(isUserQrCode(code), isFalse);
    }
  });

  for (final theme in ClientTheme.values) {
    for (final width in [320.0, 392.0]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets(
          'home and markets share search and open the chart at $width ${theme.name} scale $textScale',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = AppState(offline: true)..clientTheme = theme;
            addTearDown(state.dispose);
            await tester.pumpWidget(
              SurprisingClientApp(state: state, bootstrap: false),
            );
            expect(find.text('交易所'), findsOneWidget);
            expect(find.text('总资产估值'), findsOneWidget);
            expect(find.textContaining('今日收益 '), findsOneWidget);
            expect(find.text('链上充币'), findsOneWidget);
            expect(find.text('C2C 买币'), findsOneWidget);
            expect(find.byType(ExchangeSearchField), findsOneWidget);
            expect(find.byTooltip('扫一扫'), findsOneWidget);
            expect(find.textContaining('Web3'), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('行情').last);
            await tester.pumpAndSettle();
            expect(find.byType(ExchangeSearchField), findsOneWidget);
            expect(find.byTooltip('扫一扫'), findsNothing);
            expect(
              find.text('行情'),
              findsOneWidget,
            ); // Only the bottom navigation label.
            expect(
              find.byKey(const ValueKey('market-product-tabs')),
              findsOneWidget,
            );
            expect(find.byType(PublicMarketRow), findsWidgets);
            await tester.enterText(find.byType(TextField).first, '不存在的交易对');
            await tester.pumpAndSettle();
            expect(find.byType(PublicMarketRow), findsNothing);
            expect(find.text('暂无匹配的交易对'), findsOneWidget);
            await tester.tap(find.byTooltip('清空搜索'));
            await tester.pumpAndSettle();
            expect(find.byTooltip('清空搜索'), findsNothing);
            expect(find.byType(PublicMarketRow), findsWidgets);
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await tester.pumpAndSettle();
            expect(tester.testTextInput.isVisible, isFalse);

            await tester.tap(find.byType(PublicMarketRow).first);
            await tester.pumpAndSettle();
            expect(find.byType(MarketChartPage), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets('long option symbol and large change at 320px $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = AppState(offline: true);
      addTearDown(state.dispose);
      final instrument = Instrument.fromJson({
        'symbol': 'BTC-USDT-261225-100000-C',
        'instrumentType': 'OPTION',
        'contractType': 'VANILLA_OPTION',
        'lastPrice': '123456.789',
        'pricePrecision': 3,
        'change24h': '1234567.89',
        'volume24h': '987654321',
      });
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const MarketListHeading(),
                    PublicMarketRow(instrument: instrument),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('+1234567.89%'), findsOneWidget);
      expect(find.text(instrument.displayName), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
