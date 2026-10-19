import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/option_market.dart';

final expiry = DateTime.now().toUtc().add(const Duration(days: 365));
Instrument contract({
  String id = '74',
  String status = 'TRADING',
  String type = 'CALL',
  String? symbol,
  DateTime? ends,
  String underlying = '604',
  String line = 'LINEAR_PERPETUAL',
  int strike = 10000000000,
  String settle = 'USDT',
}) => Instrument.fromJson({
  'instrumentId': id,
  'symbol': symbol ?? 'BTC-OPTION-$id-$type',
  'instrumentType': 'OPTION',
  'contractType': 'VANILLA_OPTION',
  'productLine': 'OPTION',
  'status': status,
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': settle,
  'underlyingInstrumentId': underlying,
  'underlyingProductLine': line,
  'expiryTime': (ends ?? expiry).toIso8601String(),
  'optionType': type,
  'strikePriceUnits': strike,
  'priceTickUnits': 1000000,
  'notionalMultiplierUnits': 1000,
  'quoteScaleUnits': 100000000,
  'settleScaleUnits': 100000000,
  'pricePrecision': 2,
  'changeId': 7,
});
Map<String, dynamic> data(
  Instrument instrument, {
  DateTime? at,
  bool greeks = true,
}) {
  final source = at ?? DateTime.now().toUtc();
  return {
    'productLine': 'OPTION',
    'instrumentId': instrument.instrumentId,
    'underlyingInstrumentId': instrument.underlyingInstrumentId,
    'underlyingProductLine': instrument.underlyingProductLine,
    'optionType': instrument.optionType,
    'expiryTime': instrument.expiryTime!.toIso8601String(),
    'strikePriceUnits': '${instrument.strikePriceUnits}',
    'baseAsset': instrument.baseAsset,
    'quoteAsset': instrument.quoteAsset,
    'premiumPrice': 7.965567455405796,
    'underlyingIndexPrice': 100,
    'sameExpiryForwardPrice': 100,
    'intrinsicValue': 0,
    'asOf': source.toIso8601String(),
    'validUntil': source.add(const Duration(seconds: 5)).toIso8601String(),
    'sourcePriceSequence': '9007199254740993',
    'model': 'BLACK_76_ZERO_RATE_ACT_365',
    'discountFactor': 1,
    'unit': 'PER_UNDERLYING_UNIT',
    'greeks': greeks
        ? {
            'impliedVolatility': .2,
            'forwardDelta': instrument.optionType == 'CALL'
                ? 0.539827837277029
                : -0.460172162722971,
            'forwardGamma': .0198476273738506,
            'vegaPerVolPoint': .396952547477012,
            'thetaPerDay': -.0108754122596442,
          }
        : null,
  };
}

void main() {
  test(
    'reference data cannot cross product, underlying, contract, precision or freshness boundaries',
    () {
      final call = contract();
      final now = DateTime.now().toUtc();
      final quote = OptionReference.fromJson(data(call, at: now));
      expect(quote.matches(call, now), true);
      expect(quote.matches(contract(status: 'HALT'), now), true);
      expect(contract(status: 'HALT').canPlaceOrder(reduceOnly: true), false);
      expect(quote.matches(call, now.add(const Duration(seconds: 5))), false);
      expect(quote.matches(contract(id: '75'), now), false);
      expect(quote.matches(contract(line: 'SPOT'), now), false);
      expect(quote.matches(contract(strike: 10000000001), now), false);
      expect(
        quote.matches(
          contract(ends: expiry.add(const Duration(hours: 8))),
          now,
        ),
        false,
      );
      expect(
        OptionReference.fromJson(
          data(call, at: now.add(const Duration(seconds: 1))),
        ).matches(call, now),
        false,
      );
      expect(
        OptionReference.fromJson(data(call, greeks: false)).greeks,
        isNull,
      );
      for (final invalid in [null, true, 'NaN', double.infinity]) {
        expect(
          () => OptionReference.fromJson({
            ...data(call),
            'premiumPrice': invalid,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'chain keeps exact integer strikes, every contract, and distinct underlying and expiry boundaries',
    () {
      final call = contract(strike: 9007199254740993);
      final rows = optionChain(call, [
        call,
        contract(id: '75', type: 'PUT', strike: 9007199254740993),
        contract(id: '76', strike: 9007199254740993),
        contract(id: '77', strike: 9007199254740992),
        contract(id: '78', line: 'SPOT'),
        contract(id: '79', ends: expiry.add(const Duration(hours: 8))),
        contract(id: '80', settle: 'BTC'),
      ]);
      expect(rows.map((r) => r.strikeUnits.toString()), [
        '9007199254740992',
        '9007199254740993',
      ]);
      expect(rows.last.calls.map((i) => i.instrumentId), ['74', '76']);
      expect(rows.last.puts.single.instrumentId, '75');
    },
  );
  test(
    'state ignores a late response for the previous selected contract',
    () async {
      final call = contract(), put = contract(id: '75', type: 'PUT');
      final api = _Api();
      final state = AppState(apiClient: api, seedInstruments: [call, put])
        ..mode = ProductMode.option;
      addTearDown(state.dispose);
      api.pending = Completer<OptionReference>();
      final pending = state.refreshOptionReference();
      state.selectedSymbol = put.symbol;
      api.pending!.complete(OptionReference.fromJson(data(call)));
      await pending;
      expect(state.optionReference, isNull);
      api.pending = null;
      await state.refreshOptionReference();
      expect(state.optionReference?.instrumentId, '75');
      api.fail = true;
      await state.refreshOptionReference();
      expect(state.optionReference, isNull);
    },
  );
  test(
    'option API binds the real product route and checks returned identity',
    () async {
      final api = _PayloadApi();
      final call = contract();
      api.reply = data(call);
      await api.optionReference(call);
      expect(api.path, '/api/v1/gateway/candlestick/options/quote');
      expect(api.product, 'OPTION');
      expect(api.query!['instrumentId'], '74');
      api.reply = data(contract(id: '75'));
      await expectLater(api.optionReference(call), throwsFormatException);
    },
  );
  testWidgets(
    'small-screen option reference and chain selection render in dark and light themes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = _WidgetState();
      addTearDown(state.dispose);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ListenableBuilder(
                    listenable: state,
                    builder: (context, _) => ProductLifecyclePanel(
                      state: state,
                      instrument: state.selectedInstrument,
                      latestPrice: 9999,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('远期 Delta'), findsOneWidget);
        expect(find.text('远期 Gamma'), findsOneWidget);
        expect(find.textContaining('Black-76 参考值'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('option-chain-75')),
        );
        await tester.tap(find.byKey(const ValueKey('option-chain-75')));
        await tester.pump();
        expect(state.selectedInstrument.instrumentId, '75');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

class _Api extends ApiClient {
  _Api() : super(const AppConfig());
  Completer<OptionReference>? pending;
  bool fail = false;
  @override
  Future<OptionReference> optionReference(Instrument instrument) async {
    if (fail) throw const FormatException('stale');
    return pending?.future ?? OptionReference.fromJson(data(instrument));
  }
}

class _PayloadApi extends ApiClient {
  _PayloadApi() : super(const AppConfig());
  late Map<String, dynamic> reply;
  String? path, product;
  Map<String, String>? query;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = true,
  }) async {
    this.path = path;
    this.query = query;
    product = productLine;
    return reply;
  }
}

class _WidgetState extends AppState {
  _WidgetState()
    : super(
        offline: true,
        seedInstruments: [
          contract(),
          contract(id: '75', type: 'PUT'),
        ],
      ) {
    instruments = [contract(), contract(id: '75', type: 'PUT')];
    api.instrumentCatalog = instruments;
    mode = ProductMode.option;
    selectedSymbol = instruments.first.symbol;
  }
  @override
  OptionReference? get optionReference =>
      OptionReference.fromJson(data(selectedInstrument));
  @override
  Future<void> selectSymbol(String symbol) async {
    selectedSymbol = symbol;
    notifyListeners();
  }
}
