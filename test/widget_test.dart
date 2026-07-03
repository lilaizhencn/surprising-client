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

  test('maps trading modes to backend account types', () {
    expect(ProductMode.spot.accountType, 'SPOT');
    expect(ProductMode.linear.accountType, 'USDT_PERPETUAL');
    expect(ProductMode.inverse.accountType, 'COIN_PERPETUAL');
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
      'triggerPriceType': 'MARK_PRICE',
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
