import 'models.dart';

/// A short-lived realtime read model. Greeks are reference values per one underlying unit.
class OptionReference {
  OptionReference.fromJson(Map<String, dynamic> json)
    : instrumentId = asString(json['instrumentId']),
      underlyingInstrumentId = asString(json['underlyingInstrumentId']),
      underlyingProductLine = asString(json['underlyingProductLine']),
      optionType = asString(json['optionType']),
      strikePriceUnits = asString(json['strikePriceUnits']),
      baseAsset = asString(json['baseAsset']),
      quoteAsset = asString(json['quoteAsset']),
      expiryTime = DateTime.parse(asString(json['expiryTime'])).toUtc(),
      asOf = DateTime.parse(asString(json['asOf'])).toUtc(),
      validUntil = DateTime.parse(asString(json['validUntil'])).toUtc(),
      premiumPrice = _positive(json['premiumPrice']),
      underlyingIndexPrice = _positive(json['underlyingIndexPrice']),
      sameExpiryForwardPrice = _positive(json['sameExpiryForwardPrice']),
      intrinsicValue = _number(json['intrinsicValue']),
      greeks = json['greeks'] == null
          ? null
          : OptionReferenceGreeks.fromJson(asMap(json['greeks'])) {
    if (json['productLine'] != 'OPTION' ||
        json['model'] != 'BLACK_76_ZERO_RATE_ACT_365' ||
        json['unit'] != 'PER_UNDERLYING_UNIT' ||
        _number(json['discountFactor']) != 1 ||
        !['CALL', 'PUT'].contains(optionType) ||
        intrinsicValue < 0 ||
        BigInt.tryParse(strikePriceUnits) == null ||
        BigInt.parse(strikePriceUnits) <= BigInt.zero ||
        json['sourcePriceSequence'] is! String ||
        (BigInt.tryParse(asString(json['sourcePriceSequence'])) ??
                BigInt.zero) <=
            BigInt.zero) {
      throw const FormatException('期权参考报价格式不匹配');
    }
  }
  final String instrumentId,
      underlyingInstrumentId,
      underlyingProductLine,
      optionType,
      strikePriceUnits,
      baseAsset,
      quoteAsset;
  final DateTime expiryTime, asOf, validUntil;
  final double premiumPrice,
      underlyingIndexPrice,
      sameExpiryForwardPrice,
      intrinsicValue;
  final OptionReferenceGreeks? greeks;

  bool matches(Instrument instrument, [DateTime? time]) {
    final now = (time ?? DateTime.now()).toUtc();
    return canQueryOptionReference(instrument, now) &&
        instrument.instrumentId == instrumentId &&
        instrument.underlyingInstrumentId == underlyingInstrumentId &&
        instrument.underlyingProductLine == underlyingProductLine &&
        instrument.optionType == optionType &&
        '${instrument.strikePriceUnits}' == strikePriceUnits &&
        instrument.baseAsset == baseAsset &&
        instrument.quoteAsset == quoteAsset &&
        instrument.expiryTime?.toUtc().millisecondsSinceEpoch ==
            expiryTime.millisecondsSinceEpoch &&
        !asOf.isAfter(now) &&
        validUntil.isAfter(now) &&
        !validUntil.isAfter(expiryTime) &&
        validUntil.difference(asOf).inMilliseconds <= 5000;
  }
}

class OptionReferenceGreeks {
  OptionReferenceGreeks.fromJson(Map<String, dynamic> json)
    : impliedVolatility = _positive(json['impliedVolatility']),
      forwardDelta = _number(json['forwardDelta']),
      forwardGamma = _number(json['forwardGamma']),
      vegaPerVolPoint = _number(json['vegaPerVolPoint']),
      thetaPerDay = _number(json['thetaPerDay']) {
    if (forwardDelta.abs() > 1 ||
        forwardGamma < 0 ||
        vegaPerVolPoint < 0 ||
        thetaPerDay > 0) {
      throw const FormatException('期权参考 Greeks 不匹配');
    }
  }
  final double impliedVolatility,
      forwardDelta,
      forwardGamma,
      vegaPerVolPoint,
      thetaPerDay;
}

double _number(Object? raw) {
  final value = double.tryParse('$raw');
  if (value == null || !value.isFinite) {
    throw const FormatException('期权参考报价数字无效');
  }
  return value;
}

double _positive(Object? raw) {
  final value = _number(raw);
  if (value <= 0) throw const FormatException('期权参考报价数字必须为正');
  return value;
}

class OptionChainEntry {
  OptionChainEntry(this.strikeUnits);
  final BigInt strikeUnits;
  final calls = <Instrument>[], puts = <Instrument>[];
}

List<OptionChainEntry> optionChain(
  Instrument selected,
  List<Instrument> instruments,
) {
  final expiry = selected.expiryTime?.toUtc().millisecondsSinceEpoch;
  if (expiry == null ||
      selected.underlyingInstrumentId == null ||
      selected.underlyingProductLine == null) {
    return [];
  }
  final rows = <BigInt, OptionChainEntry>{};
  for (final item in instruments) {
    if (!item.isOption ||
        item.underlyingInstrumentId != selected.underlyingInstrumentId ||
        item.underlyingProductLine != selected.underlyingProductLine ||
        item.quoteAsset != selected.quoteAsset ||
        item.settleAsset != selected.settleAsset ||
        item.expiryTime?.toUtc().millisecondsSinceEpoch != expiry ||
        item.strikePriceUnits == null ||
        item.strikePriceUnits! <= 0 ||
        !['CALL', 'PUT'].contains(item.optionType)) {
      continue;
    }
    final strike = BigInt.from(item.strikePriceUnits!);
    final row = rows.putIfAbsent(strike, () => OptionChainEntry(strike));
    (item.optionType == 'CALL' ? row.calls : row.puts).add(item);
  }
  return rows.values.toList()
    ..sort((a, b) => a.strikeUnits.compareTo(b.strikeUnits));
}

bool canQueryOptionReference(Instrument instrument, [DateTime? time]) =>
    instrument.isOption &&
    [
      'PRE_TRADING',
      'TRADING',
      'HALT',
      'SETTLING',
    ].contains(instrument.status) &&
    instrument.expiryTime != null &&
    instrument.expiryTime!.isAfter(time ?? DateTime.now());
