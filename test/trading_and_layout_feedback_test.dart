import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/deposit_page.dart';
import 'package:surprising_client/src/exchange_widgets.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

import 'linear_delivery_trading_test.dart' show actor;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void bind(WidgetTester tester, Size size, {double textScale = 1.0}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  testWidgets('deposit search stays below the header on a small, large-text screen', (
    tester,
  ) async {
    bind(tester, const Size(320, 720), textScale: 1.3);
    final state = AppState(initialSession: actor, offline: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: buildClientTheme(ClientTheme.dark),
          home: MobileDepositPage(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(ExchangeSearchField), findsOneWidget);
    final header = tester.getRect(find.byType(AppBar));
    final search = tester.getRect(find.byType(ExchangeSearchField));
    expect(search.top, greaterThanOrEqualTo(header.bottom - 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused fields keep a single input decorator', (tester) async {
    bind(tester, const Size(392, 800), textScale: 1.3);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildClientTheme(ClientTheme.dark),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ExchangeSearchField(onChanged: (_) {}),
                const SizedBox(height: 16),
                AppTextField(label: '数量', controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(InputDecorator), findsNWidgets(2));
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(find.byType(InputDecorator), findsNWidgets(2));
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    expect(find.byType(InputDecorator), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('order book changes depth in place and does not open a sheet', (
    tester,
  ) async {
    bind(tester, const Size(392, 800));
    final state = AppState(offline: true);
    addTearDown(state.dispose);
    state.orderBook = OrderBook(
      symbol: state.selectedSymbol,
      sequence: 1,
      bids: [
        for (var i = 0; i < 30; i++)
          OrderBookLevel(priceTicks: 1000 - i, quantitySteps: 1, orderCount: 1),
      ],
      asks: [
        for (var i = 0; i < 30; i++)
          OrderBookLevel(priceTicks: 1001 + i, quantitySteps: 1, orderCount: 1),
      ],
    );
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: buildClientTheme(ClientTheme.dark),
          home: Scaffold(
            body: SizedBox(
              height: 520,
              child: OrderBookPanel(
                instrument: state.selectedInstrument,
                orderBook: state.orderBook,
                latestPrice: 1,
                onPrice: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('order-book-depth-menu')), findsOneWidget);
    expect(find.text('20档'), findsOneWidget);
    expect(find.byType(FullOrderBookSheet), findsNothing);
    await tester.tap(find.byKey(const ValueKey('order-book-depth-menu')));
    await tester.pumpAndSettle();
    expect(find.text('5档'), findsWidgets);
    expect(find.text('50档'), findsOneWidget);
    await tester.tap(find.text('50档').last);
    await tester.pumpAndSettle();
    expect(find.text('50档'), findsOneWidget);
    expect(find.byType(FullOrderBookSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trade page no longer shows a kline below the ticket', (
    tester,
  ) async {
    bind(tester, const Size(392, 900), textScale: 1.3);
    final state = AppState(offline: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: buildClientTheme(ClientTheme.dark),
          home: const Scaffold(body: TradePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(KlinePanel), findsNothing);
    expect(find.textContaining('K线图表'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar is taller and does not overflow at 320dp', (
    tester,
  ) async {
    bind(tester, const Size(320, 700), textScale: 1.3);
    final state = AppState(offline: true);
    addTearDown(state.dispose);
    await tester.pumpWidget(SurprisingClientApp(state: state, bootstrap: false));
    await tester.pumpAndSettle();
    final nav = tester.getRect(find.byType(ExchangeBottomNav));
    expect(nav.height, greaterThanOrEqualTo(68));
    expect(tester.takeException(), isNull);
  });
}
