import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
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

  test('converts price decimals to backend ticks', () {
    final instrument = fallbackInstruments().first;

    expect(instrument.ticksFromPrice(65000), 650000);
    expect(instrument.priceFromTicks(650000), 65000);
  });

  test('updates latest price from public trade events', () {
    final state = AppState(offline: true);

    state.handleRealtimeMessage({
      'op': 'event',
      'channel': 'trades',
      'symbol': 'BTC-USDT',
      'data': {'priceTicks': 650123},
    });

    expect(state.latestPriceFor(state.selectedInstrument), 65012.3);
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
}
