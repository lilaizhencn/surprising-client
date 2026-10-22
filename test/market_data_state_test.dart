import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/market_data_state.dart';
import 'package:surprising_client/src/models.dart';

Map<String, dynamic> book(
  int sequence, {
  String type = 'SNAPSHOT',
  int? previous,
  Object? depth = 50,
  List<Map<String, Object?>>? bids,
  List<Map<String, Object?>>? asks,
}) => {
  'sequence': sequence,
  'updateType': type,
  'previousSequence': previous,
  'depth': depth,
  'bids': bids ?? [],
  'asks': asks ?? [],
};

void main() {
  final instrument = Instrument.fromJson({
    'instrumentId': '1',
    'symbol': 'X-USDT',
    'contractType': 'LINEAR_PERPETUAL',
    'instrumentType': 'PERPETUAL',
    'status': 'TRADING',
    'priceTickUnits': 10000,
    'quantityStepUnits': 1,
    'quoteScaleUnits': 1000000,
  });

  Map<String, dynamic> event(String channel, Map<String, dynamic> data) => {
    'channel': channel,
    'data': {'value': data},
  };

  test('invalid public trade units never enter price or tape projections', () {
    final market = MarketDataState();
    addTearDown(market.dispose);
    final issues = <String>[];
    market.onIssue = issues.add;
    for (final invalid in [
      1.5,
      '1.5',
      'NaN',
      double.infinity,
      true,
      '9223372036854775808',
      -1,
    ]) {
      for (final field in ['priceTicks', 'quantitySteps', 'sequence']) {
        expect(
          market.applyPublicEvent(
            message: event('trades', {
              'priceTicks': 101,
              'quantitySteps': 2,
              'sequence': 1,
              field: invalid,
            }),
            instrument: instrument,
            selected: true,
            period: '1m',
          ),
          MarketUpdate.ignored,
        );
      }
    }
    expect(issues, hasLength(21));
    expect(market.latestPrices, isEmpty);
    expect(market.recentTrades, isEmpty);
    expect(
      market.applyPublicEvent(
        message: event('trades', {
          'priceTicks': '101',
          'quantitySteps': '2',
          'sequence': '1',
        }),
        instrument: instrument,
        selected: true,
        period: '1m',
      ),
      MarketUpdate.changed,
    );
    expect(market.latestPrices.values.single, 1.01);
    expect(market.recentTrades, hasLength(1));
  });

  test('malformed ticker cannot replace a known price with rounded units', () {
    final market = MarketDataState();
    addTearDown(market.dispose);
    final priceKey = market.key(instrument.mode, instrument.symbol);
    market.latestPrices[priceKey] = 1.01;
    for (final badSide in [
      'bad',
      {'priceTicks': '100.5'},
      {'priceTicks': 100, 'quantitySteps': 'NaN'},
      {'priceTicks': 100, 'orderCount': -1},
    ]) {
      expect(
        market.applyPublicEvent(
          message: event('bookTicker', {
            'bid': badSide,
            'ask': {'priceTicks': 102},
          }),
          instrument: instrument,
          selected: true,
          period: '1m',
        ),
        MarketUpdate.ignored,
      );
      expect(market.latestPrices[priceKey], 1.01);
    }
  });

  test('ticker midpoint uses quote scale and exact wide intermediates', () {
    final market = MarketDataState();
    addTearDown(market.dispose);
    final instrument = Instrument.fromJson({
      'instrumentId': '1',
      'symbol': 'X-USDT',
      'contractType': 'LINEAR_PERPETUAL',
      'instrumentType': 'PERPETUAL',
      'status': 'TRADING',
      'priceTickUnits': 10000,
      'quantityStepUnits': 1,
      'quoteScaleUnits': 1000000,
    });
    expect(market.midpoint(instrument, 100, 102), 1.01);
    expect(market.midpoint(instrument, null, 102), 1.02);
    expect(market.midpoint(instrument, 0, 0), isNull);
    final large = market.midpoint(
      instrument,
      9223372036854775807,
      9223372036854775807,
    );
    expect(large, closeTo(92233720368547758.07, 16));
  });

  test(
    'depth always retains at most 50 levels and validates before applying',
    () {
      final market = MarketDataState();
      addTearDown(market.dispose);
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(
          1,
          bids: [
            for (var i = 1; i <= 100; i++)
              {'priceTicks': i, 'quantitySteps': 2},
          ],
        ),
      );
      expect(market.orderBook.bids, hasLength(50));
      expect(market.orderBook.bids.first.priceTicks, 100);
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(
          2,
          type: 'DELTA',
          previous: 1,
          bids: [
            {'priceTicks': 100, 'quantitySteps': 0},
            {'priceTicks': 101, 'quantitySteps': 3},
          ],
        ),
      );
      expect(market.orderBook.bids, hasLength(50));
      expect(market.orderBook.bids.first.priceTicks, 101);
      expect(
        market.orderBook.bids.any((level) => level.priceTicks == 100),
        isFalse,
      );
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(3, type: 'DELTA', previous: 2, depth: -1),
      );
      expect(market.depthRecovering, isTrue);
      expect(market.orderBook.bids, isEmpty);
      market.applyDepth(ProductMode.linear, 'X', book(4));
      expect(market.depthRecovering, isFalse);
      expect(market.orderBook.bids, isEmpty);
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(
          5,
          bids: [
            {'priceTicks': -1, 'quantitySteps': 4},
          ],
        ),
      );
      expect(market.depthRecovering, isTrue);
    },
  );

  testWidgets(
    'lost baseline retries with backoff, coalesces gaps and reconnects once',
    (tester) async {
      var snapshots = 0, reconnects = 0;
      final market = MarketDataState(
        snapshotTimeout: const Duration(seconds: 1),
      );
      market.requestDepthSnapshot = () => snapshots++;
      market.reconnectDepth = () => reconnects++;
      market.applyDepth(ProductMode.linear, 'X', book(1));
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(3, type: 'DELTA', previous: 2),
      );
      market.applyDepth(
        ProductMode.linear,
        'X',
        book(4, type: 'DELTA', previous: 3),
      );
      expect(snapshots, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(snapshots, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(snapshots, 3);
      await tester.pump(const Duration(seconds: 4));
      expect(reconnects, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(reconnects, 1);
      market.applyDepth(ProductMode.linear, 'X', book(10));
      expect(market.depthRecovering, isFalse);
      market.dispose();
    },
  );

  testWidgets(
    'initial missing snapshot has a deadline and disposal cancels recovery',
    (tester) async {
      var requests = 0;
      final market = MarketDataState(
        snapshotTimeout: const Duration(seconds: 1),
      );
      market.requestDepthSnapshot = () => requests++;
      market.awaitDepthSnapshot(ProductMode.spot, 'X');
      expect(requests, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(requests, 1);
      market.dispose();
      await tester.pump(const Duration(seconds: 30));
      expect(requests, 1);
    },
  );
}
