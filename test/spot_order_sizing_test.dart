import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/spot_order.dart';

Instrument instrument([Map<String, dynamic> changes = const {}]) =>
    Instrument.fromJson({
      'instrumentId': '1',
      'symbol': 'BTC-USDT',
      'contractType': 'SPOT',
      'instrumentType': 'SPOT',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'baseScaleUnits': 1000,
      'quoteScaleUnits': 1000,
      'priceTickUnits': 100,
      'quantityStepUnits': 10,
      'notionalMultiplierUnits': 1,
      'minQuantitySteps': 1,
      'maxQuantitySteps': 1000,
      'minNotionalUnits': 1,
      'maxNotionalUnits': '9223372036854775807',
      ...changes,
    });
ProductBalance balance(int units, [String asset = 'USDT']) => ProductBalance(
  scaleUnits: 100000000,
  accountType: 'SPOT',
  asset: asset,
  availableUnits: units,
  lockedUnits: 0,
  equityUnits: units,
);
final book = OrderBook(
  symbol: 'BTC-USDT',
  sequence: 1,
  bids: [990, 980, 970, 960, 950]
      .map(
        (price) =>
            OrderBookLevel(priceTicks: price, quantitySteps: 10, orderCount: 1),
      )
      .toList(),
  asks: [1010, 1020, 1030, 1040, 1050]
      .map(
        (price) =>
            OrderBookLevel(priceTicks: price, quantitySteps: 10, orderCount: 1),
      )
      .toList(),
);
String? quantity({
  Instrument? spec,
  ProductBalance? funds,
  int percent = 100,
  String side = 'BUY',
  String type = 'LIMIT',
  String price = '100',
  String? bbo,
  int? fee = 1000,
  int? slippage = 10000,
  OrderBook? depth,
}) => spotOrderQuantity(
  instrument: spec ?? instrument(),
  balance: funds ?? balance(10000),
  book: depth ?? book,
  side: side,
  orderType: type,
  price: price,
  bboMode: bbo,
  takerFeeRatePpm: fee,
  marketMaxSlippagePpm: slippage,
  percentage: percent,
);

void main() {
  test(
    'spot amendment uses new quantities and exact steps, rejecting unchanged drafts',
    () {
      final spec = instrument();
      final order = OrderModel.fromJson({
        'orderId': 91,
        'symbol': 'BTC-USDT',
        'orderType': 'LIMIT',
        'status': 'PARTIALLY_FILLED',
        'priceTicks': 1000,
        'remainingQuantitySteps': 3,
      });
      expect(spotAmendmentTerms(spec, order, '101.1', '0.02'), (
        priceTicks: 1011,
        quantitySteps: 2,
      ));
      for (final draft in [
        ('100', '0.03'),
        ('100.01', '0.02'),
        ('100', '0.001'),
      ]) {
        expect(
          () => spotAmendmentTerms(spec, order, draft.$1, draft.$2),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'percentage reserves each fragmented step fee and floors the selected budget',
    () {
      expect(quantity(), '0.09');
      expect(quantity(percent: 50), '0.04');
      expect(quantity(price: '0.1', funds: balance(5)), '0.02');
      expect(quantity(side: 'SELL', funds: balance(95, 'BTC')), '0.09');
      expect(quantity(fee: -1000), '0.1');
    },
  );
  test('six and eighteen decimal assets preserve exact large integers', () {
    expect(
      quantity(
        side: 'SELL',
        funds: balance(9007199254740993, 'BTC'),
        spec: instrument({
          'baseScaleUnits': 1000000000000000000,
          'quantityStepUnits': 1,
          'maxQuantitySteps': '9223372036854775807',
        }),
      ),
      '0.009007199254740993',
    );
    expect(
      quantity(
        funds: balance(1000000),
        spec: instrument({
          'baseScaleUnits': 1000000000000000000,
          'quoteScaleUnits': 1000000,
          'quantityStepUnits': 1000000000000000,
          'priceTickUnits': 1000,
        }),
      ),
      '0.009',
    );
    expect(
      decimalIncrement(
        '0.009007199254740993',
        1,
        scaleUnits: 1000000000000000000,
      ),
      9007199254740993,
    );
    expect(decimalIncrement('0.1234567', 1, scaleUnits: 1000000), isNull);
  });
  test(
    'order limits, asset ownership and missing metadata never produce invented quantities',
    () {
      expect(quantity(spec: instrument({'maxQuantitySteps': 3})), '0.03');
      expect(quantity(spec: instrument({'maxNotionalUnits': 2000})), '0.02');
      expect(quantity(spec: instrument({'minNotionalUnits': 10001})), '0');
      expect(quantity(spec: instrument({'baseScaleUnits': null})), isNull);
      expect(
        quantity(spec: instrument({'notionalMultiplierUnits': null})),
        isNull,
      );
      expect(quantity(fee: null), isNull);
      expect(quantity(funds: balance(10000, 'BTC')), isNull);
    },
  );
  test(
    'BBO uses the selected side and rank, market includes the server protection bound',
    () {
      expect(quantity(bbo: 'OPPONENT_5'), '0.09');
      expect(quantity(bbo: 'SAME_SIDE_5'), '0.1');
      expect(quantity(type: 'MARKET', funds: balance(2045)), '0.01');
      expect(quantity(funds: balance(2045)), '0.02');
      expect(quantity(type: 'MARKET', slippage: null), isNull);
      expect(
        quantity(bbo: 'OPPONENT_5', depth: OrderBook.empty('BTC-USDT')),
        isNull,
      );
      expect(
        quantity(bbo: 'SAME_SIDE_1', depth: OrderBook.empty('ETH-USDT')),
        isNull,
      );
    },
  );
}
