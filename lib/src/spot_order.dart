import 'models.dart';

/// Exact spot sizing in exchange units. The trading core still admits the order.
String? spotOrderQuantity({
  required Instrument instrument,
  required ProductBalance? balance,
  required OrderBook book,
  required String side,
  required String orderType,
  required String price,
  required String? bboMode,
  required int? takerFeeRatePpm,
  required int? marketMaxSlippagePpm,
  required int percentage,
}) {
  if (!instrument.isSpot ||
      balance == null ||
      balance.accountType != 'SPOT' ||
      balance.asset.toUpperCase() !=
          (side == 'BUY' ? instrument.quoteAsset : instrument.baseAsset)
              .toUpperCase() ||
      !['BUY', 'SELL'].contains(side) ||
      percentage < 0 ||
      percentage > 100 ||
      balance.availableUnits < 0) {
    return null;
  }
  final unit = instrument.quantityStepUnits;
  final scale = instrument.baseScaleUnits;
  final min = instrument.minQuantitySteps;
  final max = instrument.maxQuantitySteps;
  final minNotional = instrument.minNotionalUnits;
  final maxNotional = instrument.maxNotionalUnits;
  final multiplier = instrument.notionalMultiplierUnits;
  if (unit <= 0 ||
      scale == null ||
      !RegExp(r'^10*$').hasMatch('$scale') ||
      min == null ||
      max == null ||
      min <= 0 ||
      max < min ||
      minNotional == null ||
      maxNotional == null ||
      minNotional <= 0 ||
      maxNotional < minNotional ||
      multiplier == null ||
      multiplier <= 0) {
    return null;
  }
  int? ticks;
  if (orderType == 'LIMIT' && bboMode == null) {
    ticks = decimalIncrement(
      price,
      instrument.priceTickUnits,
      scaleUnits: instrument.quoteScaleUnits ?? 0,
    );
  } else {
    if (book.symbol != instrument.symbol ||
        (bboMode != null && !bboPriceModes.contains(bboMode))) {
      return null;
    }
    final sameSide = bboMode?.startsWith('SAME_SIDE_') ?? false;
    final levels = (side == 'BUY') != sameSide ? book.asks : book.bids;
    final index = bboMode?.endsWith('_5') == true ? 4 : 0;
    if (levels.length <= index) return null;
    ticks = levels[index].priceTicks;
    if (orderType == 'MARKET') {
      final slip = marketMaxSlippagePpm;
      if (slip == null || slip < 0 || slip >= 1000000) return null;
      final value =
          BigInt.from(ticks) *
          BigInt.from(side == 'BUY' ? 1000000 + slip : 1000000 - slip);
      final bound =
          (value + (side == 'BUY' ? BigInt.from(999999) : BigInt.zero)) ~/
          BigInt.from(1000000);
      if (bound > BigInt.from(9223372036854775807)) return null;
      ticks = bound < BigInt.one ? 1 : bound.toInt();
    } else if (orderType != 'LIMIT') {
      return null;
    }
  }
  if (ticks == null || ticks <= 0) return null;
  final notional = BigInt.from(ticks) * BigInt.from(multiplier);
  var cost = BigInt.from(unit);
  if (side == 'BUY') {
    final fee = takerFeeRatePpm;
    if (fee == null || fee.abs() > 1000000) return null;
    cost =
        notional +
        (notional * BigInt.from(fee > 0 ? fee : 0) + BigInt.from(999999)) ~/
            BigInt.from(1000000);
  }
  var steps =
      BigInt.from(balance.availableUnits) *
      BigInt.from(percentage) ~/
      BigInt.from(100) ~/
      cost;
  for (final cap in [
    BigInt.from(max),
    BigInt.from(maxNotional) ~/ notional,
    BigInt.from(9223372036854775807) ~/ BigInt.from(unit),
  ]) {
    if (steps > cap) steps = cap;
  }
  if (steps < BigInt.from(min) || steps * notional < BigInt.from(minNotional)) {
    steps = BigInt.zero;
  }
  return scaledAmount(steps * BigInt.from(unit), scale);
}

/// The replacement quantity is a new order quantity, not the original total.
({int priceTicks, int quantitySteps}) spotAmendmentTerms(
  Instrument instrument,
  OrderModel order,
  String price,
  String quantity,
) {
  if (!instrument.isSpot ||
      instrument.instrumentId.isEmpty ||
      instrument.symbol != order.symbol ||
      instrument.status != 'TRADING' ||
      order.orderId <= 0 ||
      order.orderType != 'LIMIT' ||
      !['OPEN', 'NEW', 'ACCEPTED', 'PARTIALLY_FILLED'].contains(order.status)) {
    throw const FormatException('当前订单或交易对不可改单');
  }
  final quoteScale = instrument.quoteScaleUnits,
      baseScale = instrument.baseScaleUnits;
  final minQ = instrument.minQuantitySteps, maxQ = instrument.maxQuantitySteps;
  final minN = instrument.minNotionalUnits, maxN = instrument.maxNotionalUnits;
  final multiplier = instrument.notionalMultiplierUnits;
  if (quoteScale == null ||
      baseScale == null ||
      minQ == null ||
      maxQ == null ||
      minN == null ||
      maxN == null ||
      multiplier == null ||
      multiplier <= 0) {
    throw const FormatException('改单精度或交易规则未就绪，请刷新资料');
  }
  final p = decimalIncrement(
    price,
    instrument.priceTickUnits,
    scaleUnits: quoteScale,
  );
  final q = decimalIncrement(
    quantity,
    instrument.quantityStepUnits,
    scaleUnits: baseScale,
  );
  if (p == null || p <= 0 || q == null || q <= 0) {
    throw const FormatException('价格或数量不符合最小步长');
  }
  final notional = BigInt.from(p) * BigInt.from(q) * BigInt.from(multiplier);
  if (q < minQ ||
      q > maxQ ||
      notional < BigInt.from(minN) ||
      notional > BigInt.from(maxN) ||
      BigInt.from(q) * BigInt.from(instrument.quantityStepUnits) >
          BigInt.from(9223372036854775807)) {
    throw const FormatException('新委托数量或金额超出交易规则');
  }
  if (p == order.priceTicks && q == order.remainingQuantitySteps) {
    throw const FormatException('请修改价格或新委托数量');
  }
  return (priceTicks: p, quantitySteps: q);
}
