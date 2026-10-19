import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

Instrument option({
  String status = 'TRADING',
  String expiry = '2030-01-01T00:00:00Z',
  int tick = 10000000,
  int multiplier = 10000,
  int? scale = 100000000,
}) => Instrument.fromJson({
  'instrumentId': '74',
  'productLine': 'OPTION',
  'instrumentType': 'OPTION',
  'contractType': 'VANILLA_OPTION',
  'symbol': 'BTC-CALL-50000',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
  'priceTickUnits': tick,
  'notionalMultiplierUnits': multiplier,
  'quoteScaleUnits': scale,
  'settleScaleUnits': scale,
  'changeId': 3,
  'status': status,
  'expiryTime': expiry,
  'strikePriceUnits': '5000000000000',
  'underlyingInstrumentId': '604',
  'underlyingProductLine': 'LINEAR_PERPETUAL',
});

void main() {
  test(
    'option premium is paid in full and seller credit accounts for fees',
    () {
      final contract = option();
      expect(
        optionPremiumTerms(
          instrument: contract,
          side: 'BUY',
          priceTicks: 50000,
          quantity: '2',
          takerFeeRatePpm: 500,
        ),
        (premium: '10', fee: '0.005', cash: '10.005'),
      );
      expect(
        optionPremiumTerms(
          instrument: contract,
          side: 'SELL',
          priceTicks: 50000,
          quantity: '2',
          takerFeeRatePpm: -200,
        ),
        (premium: '10', fee: '-0.002', cash: '10.002'),
      );
    },
  );
  test('option display preserves eighteen decimal asset units', () {
    expect(
      optionPremiumTerms(
        instrument: option(tick: 1, multiplier: 1, scale: 1000000000000000000),
        side: 'BUY',
        priceTicks: 9007199254740993,
        quantity: '1',
        takerFeeRatePpm: 1,
      ),
      (
        premium: '0.009007199254740993',
        fee: '0.000000009007199255',
        cash: '0.009007208261940248',
      ),
    );
  });
  test(
    'option premium refuses missing precision, fractional contracts and unknown fees',
    () {
      for (final terms in [
        optionPremiumTerms(
          instrument: option(),
          side: 'BUY',
          priceTicks: 50000,
          quantity: '0.5',
          takerFeeRatePpm: 500,
        ),
        optionPremiumTerms(
          instrument: option(scale: null),
          side: 'BUY',
          priceTicks: 50000,
          quantity: '1',
          takerFeeRatePpm: 500,
        ),
        optionPremiumTerms(
          instrument: option(),
          side: 'BUY',
          priceTicks: 50000,
          quantity: '1',
          takerFeeRatePpm: null,
        ),
      ]) {
        expect(terms, isNull);
      }
    },
  );
  test(
    'option lifecycle, underlying identity and strike use explicit metadata',
    () {
      expect(option().canPlaceOrder(reduceOnly: false), true);
      for (final status in ['PRE_TRADING', 'HALT', 'SETTLING', 'CLOSED']) {
        expect(option(status: status).canPlaceOrder(reduceOnly: true), false);
      }
      expect(
        option(expiry: '2020-01-01T00:00:00Z').canPlaceOrder(reduceOnly: true),
        false,
      );
      expect(option().underlyingInstrumentId, '604');
      expect(option().underlyingProductLine, 'LINEAR_PERPETUAL');
      expect(option().strikePrice, 50000);
      expect(option(scale: null).strikePrice, isNull);
      expect(ProductMode.option.tracksSingleOrderIntent, true);
    },
  );
  test(
    'option fee API verifies product, instrument version and user before displaying cash',
    () async {
      final api = _Api();
      expect(await api.optionOrderTerms(1, option()), (
        takerFeeRatePpm: 500,
        marketMaxSlippagePpm: 10000,
      ));
      expect(api.products, everyElement('OPTION'));
      api.wrongVersion = true;
      await expectLater(
        api.optionOrderTerms(1, option()),
        throwsFormatException,
      );
    },
  );
}

class _Api extends ApiClient {
  _Api() : super(const AppConfig());
  final products = <String?>[];
  bool wrongVersion = false;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    bool unwrapResponseResult = true,
    int? userId,
    String? productLine,
  }) async {
    products.add(productLine);
    return path.endsWith('/effective')
        ? {
            'productLine': 'OPTION',
            'instrumentId': '74',
            'userId': 1,
            'changeId': wrongVersion ? 2 : 3,
            'takerFeeRatePpm': 500,
          }
        : {'productLine': 'OPTION', 'marketMaxSlippagePpm': 10000};
  }
}
