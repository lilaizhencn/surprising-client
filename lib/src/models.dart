import 'dart:math' as math;

enum ProductMode {
  spot('现货', 'SPOT'),
  linear('U本位永续', 'LINEAR_PERPETUAL'),
  inverse('币本位永续', 'INVERSE_PERPETUAL'),
  linearDelivery('U本位交割', 'LINEAR_DELIVERY'),
  inverseDelivery('币本位交割', 'INVERSE_DELIVERY'),
  option('期权', 'VANILLA_OPTION');

  const ProductMode(this.label, this.contractType);

  final String label;
  final String contractType;

  bool get isSpot => this == ProductMode.spot;
  bool get isPerpetual =>
      this == ProductMode.linear || this == ProductMode.inverse;
  bool get isDelivery =>
      this == ProductMode.linearDelivery ||
      this == ProductMode.inverseDelivery;
  bool get isOption => this == ProductMode.option;
  bool get isDerivative => !isSpot;

  String get contractLabel {
    return switch (this) {
      ProductMode.spot => '现货',
      ProductMode.linear || ProductMode.inverse => '永续',
      ProductMode.linearDelivery || ProductMode.inverseDelivery => '交割',
      ProductMode.option => '期权',
    };
  }

  String get accountType {
    return switch (this) {
      ProductMode.spot => 'SPOT',
      ProductMode.linear => 'USDT_PERPETUAL',
      ProductMode.inverse => 'COIN_PERPETUAL',
      ProductMode.linearDelivery => 'USDT_DELIVERY',
      ProductMode.inverseDelivery => 'COIN_DELIVERY',
      ProductMode.option => 'OPTION',
    };
  }

  String get productLine {
    return switch (this) {
      ProductMode.spot => 'SPOT',
      ProductMode.linear => 'LINEAR_PERPETUAL',
      ProductMode.inverse => 'INVERSE_PERPETUAL',
      ProductMode.linearDelivery => 'LINEAR_DELIVERY',
      ProductMode.inverseDelivery => 'INVERSE_DELIVERY',
      ProductMode.option => 'OPTION',
    };
  }
}

const productAccountTypes = [
  'SPOT',
  'USDT_PERPETUAL',
  'COIN_PERPETUAL',
  'USDT_DELIVERY',
  'COIN_DELIVERY',
  'OPTION',
];

String productAccountLabel(String type) {
  return switch (type) {
    'SPOT' => '现货',
    'USDT_PERPETUAL' => 'U本位永续',
    'COIN_PERPETUAL' => '币本位永续',
    'USDT_DELIVERY' => 'U本位交割',
    'COIN_DELIVERY' => '币本位交割',
    'OPTION' => '期权',
    _ => type,
  };
}

String positionModeLabel(String mode) {
  return mode == 'HEDGE' ? '双向持仓' : '净仓';
}

String positionSideLabel(String side) {
  return switch (side) {
    'LONG' => '多仓',
    'SHORT' => '空仓',
    _ => '净仓',
  };
}

String triggerTypeLabel(String type) {
  return switch (type) {
    'TAKE_PROFIT' => '止盈',
    'STOP_LOSS' => '止损',
    'TRAILING_STOP' => '追踪止损',
    _ => type,
  };
}

String triggerPriceTypeLabel(String type) {
  return switch (type) {
    'MARK_PRICE' => '标记价',
    'INDEX_PRICE' => '指数价',
    'LAST_PRICE' => '最新价',
    _ => type,
  };
}

String triggerCloseLabel(String side, String positionSide) {
  if (positionSide == 'LONG') return '平多';
  if (positionSide == 'SHORT') return '平空';
  return side == 'BUY' ? '买入平仓' : '卖出平仓';
}

String algoTypeLabel(String type) {
  return switch (type) {
    'TWAP' => 'TWAP',
    'ICEBERG' => '冰山',
    _ => type,
  };
}

String orderTypeLabel(String type) {
  return switch (type) {
    'LIMIT' => '限价单',
    'MARKET' => '市价单',
    _ => type,
  };
}

String timeInForceLabel(String type) {
  return switch (type) {
    'GTC' => 'GTC',
    'IOC' => 'IOC',
    'FOK' => 'FOK',
    'GTX' => 'Post Only',
    _ => type,
  };
}

String marginModeLabel(String type) {
  return switch (type) {
    'CROSS' => '全仓',
    'ISOLATED' => '逐仓',
    _ => type,
  };
}

double? fallbackPriceFor(Instrument instrument) {
  final symbol = (instrument.underlyingSymbol ?? instrument.symbol).replaceAll(
    '-SPOT',
    '',
  );
  if (symbol.startsWith('BTC-USDT') || symbol.startsWith('BTC-USD')) {
    return 61418.6;
  }
  if (symbol.startsWith('ETH-USDT') || symbol.startsWith('ETH-USD')) {
    return 1735.71;
  }
  if (symbol.startsWith('SOL-USDT') || symbol.startsWith('SOL-USD')) {
    return 79.44;
  }
  return switch (symbol) {
    'BTC-USDT' => 61418.6,
    'BTC-USDC' => 61365.0,
    'ETH-USDT' => 1735.71,
    'ETH-USDC' => 1734.30,
    'SOL-USDT' => 79.44,
    'XAUT-USDT' => 4147.77,
    _ => null,
  };
}

class AppConfig {
  const AppConfig({
    this.gatewayBaseUrl = const String.fromEnvironment(
      'SURPRISING_GATEWAY_URL',
      defaultValue: 'http://127.0.0.1:9094',
    ),
    this.websocketUrl = const String.fromEnvironment(
      'SURPRISING_WEBSOCKET_URL',
      defaultValue: 'ws://127.0.0.1:9093/ws/v1',
    ),
    this.localWebSocketUserFallback = const bool.fromEnvironment(
      'SURPRISING_WS_QUERY_USER_ID',
      defaultValue: true,
    ),
  });

  final String gatewayBaseUrl;
  final String websocketUrl;
  final bool localWebSocketUserFallback;
}

class AuthUser {
  const AuthUser({
    required this.userId,
    required this.username,
    required this.email,
    required this.status,
  });

  final int userId;
  final String username;
  final String email;
  final String status;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: asInt(json['userId']),
      username: asString(json['username'], fallback: 'user'),
      email: asString(json['email']),
      status: asString(json['status'], fallback: 'ACTIVE'),
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AuthUser.fromJson(asMap(json['user'])),
      accessToken: asString(json['accessToken']),
      refreshToken: asString(json['refreshToken']),
    );
  }
}

class Instrument {
  const Instrument({
    required this.symbol,
    required this.instrumentType,
    required this.contractType,
    required this.baseAsset,
    required this.quoteAsset,
    required this.settleAsset,
    required this.priceTickUnits,
    required this.quantityStepUnits,
    required this.pricePrecision,
    required this.quantityPrecision,
    required this.maxLeveragePpm,
    required this.status,
    this.expiryTime,
    this.deliveryTime,
    this.underlyingSymbol,
    this.strikePriceUnits,
    this.optionType,
    this.optionExerciseStyle,
    this.settlementMethod,
  });

  final String symbol;
  final String instrumentType;
  final String contractType;
  final String baseAsset;
  final String quoteAsset;
  final String settleAsset;
  final int priceTickUnits;
  final int quantityStepUnits;
  final int pricePrecision;
  final int quantityPrecision;
  final int maxLeveragePpm;
  final String status;
  final DateTime? expiryTime;
  final DateTime? deliveryTime;
  final String? underlyingSymbol;
  final int? strikePriceUnits;
  final String? optionType;
  final String? optionExerciseStyle;
  final String? settlementMethod;

  ProductMode get mode {
    if (contractType == ProductMode.spot.contractType) return ProductMode.spot;
    if (contractType == ProductMode.inverse.contractType) {
      return ProductMode.inverse;
    }
    if (contractType == ProductMode.linearDelivery.contractType) {
      return ProductMode.linearDelivery;
    }
    if (contractType == ProductMode.inverseDelivery.contractType) {
      return ProductMode.inverseDelivery;
    }
    if (contractType == ProductMode.option.contractType ||
        instrumentType == 'OPTION') {
      return ProductMode.option;
    }
    return ProductMode.linear;
  }

  bool get isSpot => mode.isSpot;
  bool get isDerivative => mode.isDerivative;
  bool get isPerpetual => mode.isPerpetual;
  bool get isDelivery => mode.isDelivery;
  bool get isOption => mode.isOption;
  String get contractLabel => mode.contractLabel;

  String get displayName => symbol.replaceAll('-SPOT', '');

  double? get strikePrice {
    final units = strikePriceUnits;
    if (units == null) return null;
    return units / 100000000.0;
  }

  double priceFromTicks(int ticks) => ticks * priceTickUnits / 100000000.0;

  int ticksFromPrice(double price) {
    if (priceTickUnits <= 0) return price.round();
    return (price * 100000000.0 / priceTickUnits).round();
  }

  factory Instrument.fromJson(Map<String, dynamic> json) {
    return Instrument(
      symbol: asString(json['symbol']),
      instrumentType: asString(json['instrumentType'], fallback: 'PERPETUAL'),
      contractType: asString(
        json['contractType'],
        fallback: 'LINEAR_PERPETUAL',
      ),
      baseAsset: asString(json['baseAsset'], fallback: 'BTC'),
      quoteAsset: asString(json['quoteAsset'], fallback: 'USDT'),
      settleAsset: asString(json['settleAsset'], fallback: 'USDT'),
      priceTickUnits: asInt(json['priceTickUnits'], fallback: 10000000),
      quantityStepUnits: asInt(json['quantityStepUnits'], fallback: 1),
      pricePrecision: asInt(json['pricePrecision'], fallback: 2),
      quantityPrecision: asInt(json['quantityPrecision'], fallback: 0),
      maxLeveragePpm: asInt(json['maxLeveragePpm'], fallback: 1000000),
      status: asString(json['status'], fallback: 'TRADING'),
      expiryTime: asNullableDateTime(json['expiryTime']),
      deliveryTime: asNullableDateTime(json['deliveryTime']),
      underlyingSymbol: nullableString(json['underlyingSymbol']),
      strikePriceUnits: asNullableInt(json['strikePriceUnits']),
      optionType: nullableString(json['optionType']),
      optionExerciseStyle: nullableString(json['optionExerciseStyle']),
      settlementMethod: nullableString(json['settlementMethod']),
    );
  }
}

class OrderBookLevel {
  const OrderBookLevel({
    required this.priceTicks,
    required this.quantitySteps,
    required this.orderCount,
  });

  final int priceTicks;
  final int quantitySteps;
  final int orderCount;

  factory OrderBookLevel.fromJson(Map<String, dynamic> json) {
    return OrderBookLevel(
      priceTicks: asInt(json['priceTicks']),
      quantitySteps: asInt(json['quantitySteps']),
      orderCount: asInt(json['orderCount']),
    );
  }
}

class OrderBook {
  const OrderBook({
    required this.symbol,
    required this.sequence,
    required this.bids,
    required this.asks,
  });

  final String symbol;
  final int sequence;
  final List<OrderBookLevel> bids;
  final List<OrderBookLevel> asks;

  factory OrderBook.empty(String symbol) {
    return OrderBook(
      symbol: symbol,
      sequence: 0,
      bids: const [],
      asks: const [],
    );
  }

  factory OrderBook.fromJson(Map<String, dynamic> json) {
    return OrderBook(
      symbol: asString(json['symbol']),
      sequence: asInt(json['sequence']),
      bids: asList(
        json['bids'],
      ).map((e) => OrderBookLevel.fromJson(asMap(e))).toList(),
      asks: asList(
        json['asks'],
      ).map((e) => OrderBookLevel.fromJson(asMap(e))).toList(),
    );
  }
}

OrderBook fallbackOrderBook(Instrument instrument) {
  final midPrice = fallbackPriceFor(instrument) ?? 100;
  final midTicks = instrument.ticksFromPrice(midPrice);
  const askSizes = [58, 4039, 266, 12, 12110, 320, 86];
  const bidSizes = [12, 12, 13, 12, 12, 44, 120];
  return OrderBook(
    symbol: instrument.symbol,
    sequence: 1,
    asks: [
      for (var i = 0; i < askSizes.length; i++)
        OrderBookLevel(
          priceTicks: midTicks + i + 1,
          quantitySteps: askSizes[i],
          orderCount: 1 + i,
        ),
    ],
    bids: [
      for (var i = 0; i < bidSizes.length; i++)
        OrderBookLevel(
          priceTicks: midTicks - i - 1,
          quantitySteps: bidSizes[i],
          orderCount: 1 + i,
        ),
    ],
  );
}

class Candle {
  const Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final DateTime openTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  int get timeMillis => openTime.millisecondsSinceEpoch;

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      openTime: DateTime.tryParse(asString(json['openTime'])) ?? DateTime.now(),
      open: asDouble(json['openPrice']),
      high: asDouble(json['highPrice']),
      low: asDouble(json['lowPrice']),
      close: asDouble(json['closePrice']),
      volume: asDouble(json['baseVolume']),
    );
  }
}

class ProductBalance {
  const ProductBalance({
    required this.accountType,
    required this.asset,
    required this.availableUnits,
    required this.lockedUnits,
    required this.equityUnits,
  });

  final String accountType;
  final String asset;
  final int availableUnits;
  final int lockedUnits;
  final int equityUnits;

  double get available => unitsToDecimal(availableUnits);
  double get locked => unitsToDecimal(lockedUnits);
  double get equity => unitsToDecimal(equityUnits);

  factory ProductBalance.fromJson(Map<String, dynamic> json) {
    return ProductBalance(
      accountType: asString(json['accountType'], fallback: 'SPOT'),
      asset: asString(json['asset'], fallback: 'USDT'),
      availableUnits: asInt(json['availableUnits']),
      lockedUnits: asInt(json['lockedUnits']),
      equityUnits: asInt(json['equityUnits']),
    );
  }
}

class Position {
  const Position({
    required this.symbol,
    required this.marginMode,
    required this.positionSide,
    required this.signedQuantitySteps,
    required this.entryPriceTicks,
    required this.realizedPnlUnits,
  });

  final String symbol;
  final String marginMode;
  final String positionSide;
  final int signedQuantitySteps;
  final int entryPriceTicks;
  final int realizedPnlUnits;

  bool get isLong => signedQuantitySteps >= 0;

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      symbol: asString(json['symbol']),
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      signedQuantitySteps: asInt(json['signedQuantitySteps']),
      entryPriceTicks: asInt(json['entryPriceTicks']),
      realizedPnlUnits: asInt(json['realizedPnlUnits']),
    );
  }
}

class OrderModel {
  const OrderModel({
    required this.orderId,
    required this.symbol,
    required this.side,
    required this.orderType,
    required this.timeInForce,
    required this.priceTicks,
    required this.quantitySteps,
    required this.executedQuantitySteps,
    required this.remainingQuantitySteps,
    required this.marginMode,
    required this.positionSide,
    required this.status,
    required this.reduceOnly,
    required this.postOnly,
  });

  final int orderId;
  final String symbol;
  final String side;
  final String orderType;
  final String timeInForce;
  final int priceTicks;
  final int quantitySteps;
  final int executedQuantitySteps;
  final int remainingQuantitySteps;
  final String marginMode;
  final String positionSide;
  final String status;
  final bool reduceOnly;
  final bool postOnly;

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      orderId: asInt(json['orderId']),
      symbol: asString(json['symbol']),
      side: asString(json['side']),
      orderType: asString(json['orderType']),
      timeInForce: asString(json['timeInForce']),
      priceTicks: asInt(json['priceTicks']),
      quantitySteps: asInt(json['quantitySteps']),
      executedQuantitySteps: asInt(json['executedQuantitySteps']),
      remainingQuantitySteps: asInt(json['remainingQuantitySteps']),
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      status: asString(json['status']),
      reduceOnly: asBool(json['reduceOnly']),
      postOnly: asBool(json['postOnly']),
    );
  }
}

class TestOrderResult {
  const TestOrderResult({
    required this.accepted,
    required this.instrumentVersion,
    required this.validationStage,
    required this.estimatedReserveUnits,
    this.rejectReason,
    this.accountType,
    this.asset,
  });

  final bool accepted;
  final String? rejectReason;
  final int instrumentVersion;
  final String validationStage;
  final String? accountType;
  final String? asset;
  final int estimatedReserveUnits;

  factory TestOrderResult.fromJson(Map<String, dynamic> json) {
    return TestOrderResult(
      accepted: asBool(json['accepted']),
      rejectReason: nullableString(json['rejectReason']),
      instrumentVersion: asInt(json['instrumentVersion']),
      validationStage: asString(json['validationStage']),
      accountType: nullableString(json['accountType']),
      asset: nullableString(json['asset']),
      estimatedReserveUnits: asInt(json['estimatedReserveUnits']),
    );
  }
}

class OrderBatchItem {
  const OrderBatchItem({
    required this.index,
    required this.success,
    required this.message,
    this.order,
  });

  final int index;
  final bool success;
  final String message;
  final OrderModel? order;

  factory OrderBatchItem.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    return OrderBatchItem(
      index: asInt(json['index']),
      success: asBool(json['success']),
      message: asString(json['message']),
      order: rawOrder == null ? null : OrderModel.fromJson(asMap(rawOrder)),
    );
  }
}

class OrderBatchResult {
  const OrderBatchResult({
    required this.requested,
    required this.completed,
    required this.failed,
    required this.results,
  });

  final int requested;
  final int completed;
  final int failed;
  final List<OrderBatchItem> results;

  factory OrderBatchResult.fromJson(Map<String, dynamic> json) {
    return OrderBatchResult(
      requested: asInt(json['requested']),
      completed: asInt(json['completed']),
      failed: asInt(json['failed']),
      results: asList(
        json['results'],
      ).map((item) => OrderBatchItem.fromJson(asMap(item))).toList(),
    );
  }
}

class AlgoOrderModel {
  const AlgoOrderModel({
    required this.algoOrderId,
    required this.symbol,
    required this.algoType,
    required this.side,
    required this.priceTicks,
    required this.quantitySteps,
    required this.childQuantitySteps,
    required this.intervalSeconds,
    required this.durationSeconds,
    required this.marginMode,
    required this.positionSide,
    required this.reduceOnly,
    required this.postOnly,
    required this.timeInForce,
    required this.status,
    required this.executedQuantitySteps,
    required this.activeQuantitySteps,
    required this.childOrderCount,
    this.clientAlgoOrderId,
    this.currentOrderId,
    this.rejectReason,
  });

  final int algoOrderId;
  final String? clientAlgoOrderId;
  final String symbol;
  final String algoType;
  final String side;
  final int priceTicks;
  final int quantitySteps;
  final int childQuantitySteps;
  final int intervalSeconds;
  final int durationSeconds;
  final String marginMode;
  final String positionSide;
  final bool reduceOnly;
  final bool postOnly;
  final String timeInForce;
  final String status;
  final int executedQuantitySteps;
  final int activeQuantitySteps;
  final int childOrderCount;
  final int? currentOrderId;
  final String? rejectReason;

  factory AlgoOrderModel.fromJson(Map<String, dynamic> json) {
    return AlgoOrderModel(
      algoOrderId: asInt(json['algoOrderId']),
      clientAlgoOrderId: nullableString(json['clientAlgoOrderId']),
      symbol: asString(json['symbol']),
      algoType: asString(json['algoType'], fallback: 'TWAP'),
      side: asString(json['side'], fallback: 'BUY'),
      priceTicks: asInt(json['priceTicks']),
      quantitySteps: asInt(json['quantitySteps']),
      childQuantitySteps: asInt(json['childQuantitySteps']),
      intervalSeconds: asInt(json['intervalSeconds']),
      durationSeconds: asInt(json['durationSeconds']),
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      reduceOnly: asBool(json['reduceOnly']),
      postOnly: asBool(json['postOnly']),
      timeInForce: asString(json['timeInForce'], fallback: 'GTC'),
      status: asString(json['status'], fallback: 'PENDING'),
      executedQuantitySteps: asInt(json['executedQuantitySteps']),
      activeQuantitySteps: asInt(json['activeQuantitySteps']),
      childOrderCount: asInt(json['childOrderCount']),
      currentOrderId: asNullableInt(json['currentOrderId']),
      rejectReason: nullableString(json['rejectReason']),
    );
  }
}

class AlgoOrderBatchItem {
  const AlgoOrderBatchItem({
    required this.index,
    required this.success,
    required this.message,
    this.order,
  });

  final int index;
  final bool success;
  final String message;
  final AlgoOrderModel? order;

  factory AlgoOrderBatchItem.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['algoOrder'];
    return AlgoOrderBatchItem(
      index: asInt(json['index']),
      success: asBool(json['success']),
      message: asString(json['message']),
      order: rawOrder == null ? null : AlgoOrderModel.fromJson(asMap(rawOrder)),
    );
  }
}

class AlgoOrderBatchResult {
  const AlgoOrderBatchResult({
    required this.requested,
    required this.completed,
    required this.failed,
    required this.results,
  });

  final int requested;
  final int completed;
  final int failed;
  final List<AlgoOrderBatchItem> results;

  factory AlgoOrderBatchResult.fromJson(Map<String, dynamic> json) {
    return AlgoOrderBatchResult(
      requested: asInt(json['requested']),
      completed: asInt(json['completed']),
      failed: asInt(json['failed']),
      results: asList(
        json['results'],
      ).map((item) => AlgoOrderBatchItem.fromJson(asMap(item))).toList(),
    );
  }
}

class AlgoOrderDraft {
  const AlgoOrderDraft({
    required this.algoType,
    required this.side,
    required this.priceTicks,
    required this.quantitySteps,
    required this.childQuantitySteps,
    required this.intervalSeconds,
    required this.durationSeconds,
    required this.marginMode,
    required this.positionSide,
    required this.reduceOnly,
    required this.postOnly,
  });

  final String algoType;
  final String side;
  final int priceTicks;
  final int quantitySteps;
  final int childQuantitySteps;
  final int intervalSeconds;
  final int durationSeconds;
  final String marginMode;
  final String positionSide;
  final bool reduceOnly;
  final bool postOnly;
}

class CancelAllAfterResult {
  const CancelAllAfterResult({
    required this.userId,
    required this.countdownMs,
    required this.active,
    required this.updatedAt,
    required this.canceledOrders,
    required this.canceledTriggerOrders,
    this.symbol,
    this.triggerAt,
  });

  final int userId;
  final String? symbol;
  final int countdownMs;
  final bool active;
  final DateTime? triggerAt;
  final DateTime updatedAt;
  final int canceledOrders;
  final int canceledTriggerOrders;

  factory CancelAllAfterResult.fromJson(Map<String, dynamic> json) {
    return CancelAllAfterResult(
      userId: asInt(json['userId']),
      symbol: nullableString(json['symbol']),
      countdownMs: asInt(json['countdownMs']),
      active: asBool(json['active']),
      triggerAt: DateTime.tryParse(asString(json['triggerAt'])),
      updatedAt:
          DateTime.tryParse(asString(json['updatedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      canceledOrders: asInt(json['canceledOrders']),
      canceledTriggerOrders: asInt(json['canceledTriggerOrders']),
    );
  }
}

class AmendOrderResult {
  const AmendOrderResult({
    required this.originalOrder,
    required this.replacementOrder,
    required this.cancelRequested,
    required this.message,
  });

  final OrderModel originalOrder;
  final OrderModel replacementOrder;
  final bool cancelRequested;
  final String message;

  factory AmendOrderResult.fromJson(Map<String, dynamic> json) {
    return AmendOrderResult(
      originalOrder: OrderModel.fromJson(asMap(json['originalOrder'])),
      replacementOrder: OrderModel.fromJson(asMap(json['replacementOrder'])),
      cancelRequested: asBool(json['cancelRequested']),
      message: asString(json['message']),
    );
  }
}

class AmendOrderBatchItem {
  const AmendOrderBatchItem({
    required this.index,
    required this.success,
    required this.message,
    this.amend,
  });

  final int index;
  final bool success;
  final String message;
  final AmendOrderResult? amend;

  factory AmendOrderBatchItem.fromJson(Map<String, dynamic> json) {
    final rawAmend = json['amend'];
    return AmendOrderBatchItem(
      index: asInt(json['index']),
      success: asBool(json['success']),
      message: asString(json['message']),
      amend: rawAmend == null
          ? null
          : AmendOrderResult.fromJson(asMap(rawAmend)),
    );
  }
}

class AmendOrderBatchResult {
  const AmendOrderBatchResult({
    required this.requested,
    required this.completed,
    required this.failed,
    required this.results,
  });

  final int requested;
  final int completed;
  final int failed;
  final List<AmendOrderBatchItem> results;

  factory AmendOrderBatchResult.fromJson(Map<String, dynamic> json) {
    return AmendOrderBatchResult(
      requested: asInt(json['requested']),
      completed: asInt(json['completed']),
      failed: asInt(json['failed']),
      results: asList(
        json['results'],
      ).map((item) => AmendOrderBatchItem.fromJson(asMap(item))).toList(),
    );
  }
}

class TriggerOrderModel {
  const TriggerOrderModel({
    required this.triggerOrderId,
    required this.symbol,
    required this.side,
    required this.triggerType,
    required this.triggerPriceType,
    required this.triggerCondition,
    required this.triggerPriceTicks,
    this.activationPriceTicks,
    this.callbackRatePpm,
    this.highestPriceTicks,
    this.lowestPriceTicks,
    this.activatedAt,
    required this.orderType,
    required this.timeInForce,
    required this.priceTicks,
    required this.quantitySteps,
    required this.marginMode,
    required this.positionSide,
    required this.status,
    this.placedOrderId,
  });

  final int triggerOrderId;
  final String symbol;
  final String side;
  final String triggerType;
  final String triggerPriceType;
  final String triggerCondition;
  final int triggerPriceTicks;
  final int? activationPriceTicks;
  final int? callbackRatePpm;
  final int? highestPriceTicks;
  final int? lowestPriceTicks;
  final String? activatedAt;
  final String orderType;
  final String timeInForce;
  final int priceTicks;
  final int quantitySteps;
  final String marginMode;
  final String positionSide;
  final String status;
  final int? placedOrderId;

  factory TriggerOrderModel.fromJson(Map<String, dynamic> json) {
    final placedOrderId = json['placedOrderId'];
    return TriggerOrderModel(
      triggerOrderId: asInt(json['triggerOrderId']),
      symbol: asString(json['symbol']),
      side: asString(json['side'], fallback: 'SELL'),
      triggerType: asString(json['triggerType'], fallback: 'TAKE_PROFIT'),
      triggerPriceType: asString(
        json['triggerPriceType'],
        fallback: 'MARK_PRICE',
      ),
      triggerCondition: asString(json['triggerCondition']),
      triggerPriceTicks: asInt(json['triggerPriceTicks']),
      activationPriceTicks: asNullableInt(json['activationPriceTicks']),
      callbackRatePpm: asNullableInt(json['callbackRatePpm']),
      highestPriceTicks: asNullableInt(json['highestPriceTicks']),
      lowestPriceTicks: asNullableInt(json['lowestPriceTicks']),
      activatedAt: nullableString(json['activatedAt']),
      orderType: asString(json['orderType'], fallback: 'MARKET'),
      timeInForce: asString(json['timeInForce'], fallback: 'IOC'),
      priceTicks: asInt(json['priceTicks']),
      quantitySteps: asInt(json['quantitySteps']),
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      status: asString(json['status'], fallback: 'NEW'),
      placedOrderId: placedOrderId == null ? null : asInt(placedOrderId),
    );
  }
}

class TriggerOrderBatchItem {
  const TriggerOrderBatchItem({
    required this.index,
    required this.success,
    required this.message,
    this.order,
  });

  final int index;
  final bool success;
  final String message;
  final TriggerOrderModel? order;

  factory TriggerOrderBatchItem.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    return TriggerOrderBatchItem(
      index: asInt(json['index']),
      success: asBool(json['success']),
      message: asString(json['message']),
      order: rawOrder == null
          ? null
          : TriggerOrderModel.fromJson(asMap(rawOrder)),
    );
  }
}

class TriggerOrderBatchResult {
  const TriggerOrderBatchResult({
    required this.requested,
    required this.completed,
    required this.failed,
    required this.results,
  });

  final int requested;
  final int completed;
  final int failed;
  final List<TriggerOrderBatchItem> results;

  factory TriggerOrderBatchResult.fromJson(Map<String, dynamic> json) {
    return TriggerOrderBatchResult(
      requested: asInt(json['requested']),
      completed: asInt(json['completed']),
      failed: asInt(json['failed']),
      results: asList(
        json['results'],
      ).map((item) => TriggerOrderBatchItem.fromJson(asMap(item))).toList(),
    );
  }
}

class TriggerOrderDraft {
  const TriggerOrderDraft({
    required this.side,
    required this.triggerType,
    required this.triggerPriceType,
    required this.triggerPriceTicks,
    this.activationPriceTicks,
    this.callbackRatePpm,
    required this.quantitySteps,
    required this.marginMode,
    required this.positionSide,
  });

  final String side;
  final String triggerType;
  final String triggerPriceType;
  final int triggerPriceTicks;
  final int? activationPriceTicks;
  final int? callbackRatePpm;
  final int quantitySteps;
  final String marginMode;
  final String positionSide;
}

class AccountRisk {
  const AccountRisk({
    required this.settleAsset,
    required this.equityUnits,
    required this.maintenanceMarginUnits,
    required this.marginRatioPpm,
    required this.status,
  });

  final String settleAsset;
  final int equityUnits;
  final int maintenanceMarginUnits;
  final int marginRatioPpm;
  final String status;

  factory AccountRisk.fromJson(Map<String, dynamic> json) {
    return AccountRisk(
      settleAsset: asString(json['settleAsset'], fallback: 'USDT'),
      equityUnits: asInt(json['equityUnits']),
      maintenanceMarginUnits: asInt(json['maintenanceMarginUnits']),
      marginRatioPpm: asInt(json['marginRatioPpm']),
      status: asString(json['status'], fallback: 'NORMAL'),
    );
  }
}

class PositionRisk {
  const PositionRisk({
    required this.symbol,
    required this.positionSide,
    required this.markPriceTicks,
    required this.unrealizedPnlUnits,
    required this.positionMarginUnits,
    required this.marginRatioPpm,
    required this.status,
  });

  final String symbol;
  final String positionSide;
  final int markPriceTicks;
  final int unrealizedPnlUnits;
  final int positionMarginUnits;
  final int marginRatioPpm;
  final String status;

  factory PositionRisk.fromJson(Map<String, dynamic> json) {
    return PositionRisk(
      symbol: asString(json['symbol']),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      markPriceTicks: asInt(json['markPriceTicks']),
      unrealizedPnlUnits: asInt(json['unrealizedPnlUnits']),
      positionMarginUnits: asInt(json['positionMarginUnits']),
      marginRatioPpm: asInt(json['marginRatioPpm']),
      status: asString(json['status'], fallback: 'NORMAL'),
    );
  }
}

class LiquidationOrder {
  const LiquidationOrder({
    required this.orderId,
    required this.symbol,
    required this.status,
    required this.quantitySteps,
  });

  final int orderId;
  final String symbol;
  final String status;
  final int quantitySteps;

  factory LiquidationOrder.fromJson(Map<String, dynamic> json) {
    return LiquidationOrder(
      orderId: asInt(json['liquidationOrderId'] ?? json['orderId']),
      symbol: asString(json['symbol']),
      status: asString(json['status']),
      quantitySteps: asInt(json['quantitySteps']),
    );
  }
}

class WalletPortfolio {
  const WalletPortfolio({
    required this.generatedAt,
    required this.assets,
    required this.assetCount,
  });

  final String generatedAt;
  final List<WalletAssetSummary> assets;
  final int assetCount;

  double get totalBalance {
    return assets.fold<double>(0, (sum, asset) => sum + asset.totalBalance);
  }

  factory WalletPortfolio.empty() {
    return const WalletPortfolio(generatedAt: '', assets: [], assetCount: 0);
  }

  factory WalletPortfolio.fromJson(Map<String, dynamic> json) {
    final assets = asList(
      json['assets'],
    ).map((item) => WalletAssetSummary.fromJson(asMap(item))).toList();
    return WalletPortfolio(
      generatedAt: asString(json['generatedAt']),
      assets: assets,
      assetCount: asInt(json['assetCount'], fallback: assets.length),
    );
  }
}

WalletPortfolio fallbackWalletPortfolio() {
  return const WalletPortfolio(
    generatedAt: 'demo',
    assetCount: 2,
    assets: [
      WalletAssetSummary(
        symbol: 'OKB',
        availableBalance: 135.00000009,
        lockedBalance: 0,
        totalBalance: 135.00000009,
        chains: [
          WalletChainAsset(
            chain: 'X Layer',
            symbol: 'OKB',
            network: 'X Layer',
            family: 'EVM',
            standard: 'Native',
            nativeAsset: true,
            nativeSymbol: 'OKB',
            availableBalance: 135.00000009,
            lockedBalance: 0,
            totalBalance: 135.00000009,
            addresses: [],
          ),
        ],
      ),
      WalletAssetSummary(
        symbol: 'BTC',
        availableBalance: 0.0195464,
        lockedBalance: 0,
        totalBalance: 0.0195464,
        chains: [
          WalletChainAsset(
            chain: 'BTC',
            symbol: 'BTC',
            network: 'Bitcoin',
            family: 'BTC',
            standard: 'Native',
            nativeAsset: true,
            nativeSymbol: 'BTC',
            availableBalance: 0.0195464,
            lockedBalance: 0,
            totalBalance: 0.0195464,
            addresses: [],
          ),
        ],
      ),
    ],
  );
}

class WalletAssetSummary {
  const WalletAssetSummary({
    required this.symbol,
    required this.availableBalance,
    required this.lockedBalance,
    required this.totalBalance,
    required this.chains,
  });

  final String symbol;
  final double availableBalance;
  final double lockedBalance;
  final double totalBalance;
  final List<WalletChainAsset> chains;

  factory WalletAssetSummary.fromJson(Map<String, dynamic> json) {
    return WalletAssetSummary(
      symbol: asString(json['symbol']),
      availableBalance: asDouble(json['availableBalance']),
      lockedBalance: asDouble(json['lockedBalance']),
      totalBalance: asDouble(json['totalBalance']),
      chains: asList(
        json['chains'],
      ).map((item) => WalletChainAsset.fromJson(asMap(item))).toList(),
    );
  }
}

class WalletChainAsset {
  const WalletChainAsset({
    required this.chain,
    required this.symbol,
    required this.network,
    required this.family,
    required this.standard,
    required this.nativeAsset,
    required this.nativeSymbol,
    required this.availableBalance,
    required this.lockedBalance,
    required this.totalBalance,
    required this.addresses,
  });

  final String chain;
  final String symbol;
  final String network;
  final String family;
  final String standard;
  final bool nativeAsset;
  final String nativeSymbol;
  final double availableBalance;
  final double lockedBalance;
  final double totalBalance;
  final List<WalletAddressRef> addresses;

  String get label => '$chain ${network.isEmpty ? '' : '· $network'}'.trim();

  factory WalletChainAsset.fromJson(Map<String, dynamic> json) {
    return WalletChainAsset(
      chain: asString(json['chain']),
      symbol: asString(json['symbol']),
      network: asString(json['network']),
      family: asString(json['family']),
      standard: asString(
        json['standard'] ?? json['tokenStandard'] ?? json['tokenstandard'],
      ),
      nativeAsset: asBool(json['nativeAsset'] ?? json['nativeasset']),
      nativeSymbol: asString(json['nativeSymbol'] ?? json['nativesymbol']),
      availableBalance: asDouble(json['availableBalance']),
      lockedBalance: asDouble(json['lockedBalance']),
      totalBalance: asDouble(json['totalBalance']),
      addresses: asList(
        json['addresses'],
      ).map((item) => WalletAddressRef.fromJson(asMap(item))).toList(),
    );
  }
}

class WalletAddressRef {
  const WalletAddressRef({
    required this.chain,
    required this.symbol,
    required this.address,
    required this.ownerAddress,
    required this.addressIndex,
  });

  final String chain;
  final String symbol;
  final String address;
  final String ownerAddress;
  final int addressIndex;

  factory WalletAddressRef.fromJson(Map<String, dynamic> json) {
    return WalletAddressRef(
      chain: asString(json['chain']),
      symbol: asString(json['symbol']),
      address: asString(json['address']),
      ownerAddress: asString(json['ownerAddress']),
      addressIndex: asInt(json['addressIndex']),
    );
  }
}

class WalletDepositAddress {
  const WalletDepositAddress({
    required this.chain,
    required this.symbol,
    required this.network,
    required this.standard,
    required this.nativeAsset,
    required this.nativeSymbol,
    required this.address,
    required this.qrCodeDataUrl,
    required this.ownerAddress,
    required this.accountId,
    required this.addressIndex,
    required this.memo,
    required this.warnings,
  });

  final String chain;
  final String symbol;
  final String network;
  final String standard;
  final bool nativeAsset;
  final String nativeSymbol;
  final String address;
  final String qrCodeDataUrl;
  final String ownerAddress;
  final String accountId;
  final int addressIndex;
  final String memo;
  final List<String> warnings;

  factory WalletDepositAddress.fromJson(Map<String, dynamic> json) {
    return WalletDepositAddress(
      chain: asString(json['chain']),
      symbol: asString(json['symbol']),
      network: asString(json['network']),
      standard: asString(json['standard']),
      nativeAsset: asBool(json['nativeAsset']),
      nativeSymbol: asString(json['nativeSymbol']),
      address: asString(json['address']),
      qrCodeDataUrl: asString(json['qrCodeDataUrl']),
      ownerAddress: asString(json['ownerAddress']),
      accountId: asString(json['accountId']),
      addressIndex: asInt(json['addressIndex']),
      memo: asString(json['memo']),
      warnings: asList(json['warnings']).map((item) => '$item').toList(),
    );
  }
}

class WalletOrderRecord {
  const WalletOrderRecord({
    required this.type,
    required this.refNo,
    required this.chain,
    required this.symbol,
    required this.amount,
    required this.fee,
    required this.status,
    required this.toAddress,
    required this.txHash,
    required this.errorMessage,
    required this.updatedAt,
  });

  final String type;
  final String refNo;
  final String chain;
  final String symbol;
  final double amount;
  final double fee;
  final String status;
  final String toAddress;
  final String txHash;
  final String errorMessage;
  final String updatedAt;

  factory WalletOrderRecord.fromJson(Map<String, dynamic> json) {
    return WalletOrderRecord(
      type: asString(json['type']),
      refNo: asString(json['refNo'] ?? json['ref_no']),
      chain: asString(json['chain']),
      symbol: asString(
        json['assetSymbol'] ?? json['asset_symbol'] ?? json['symbol'],
      ),
      amount: asDouble(json['amount']),
      fee: asDouble(json['fee']),
      status: asString(json['status']),
      toAddress: asString(json['toAddress'] ?? json['to_address']),
      txHash: asString(json['txHash'] ?? json['tx_hash']),
      errorMessage: asString(json['errorMessage'] ?? json['error_message']),
      updatedAt: asString(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

double unitsToDecimal(int units) => units / 100000000.0;

int decimalToUnits(double value) => (value * 100000000.0).round();

String money(double value, {int digits = 2}) {
  if (!value.isFinite) return '--';
  return value.toStringAsFixed(digits);
}

String compactInt(int value) {
  final absValue = value.abs();
  if (absValue >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (absValue >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
  return '$value';
}

String percentageFromPpm(int ppm) => '${(ppm / 10000.0).toStringAsFixed(2)}%';

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, val) => MapEntry('$key', val));
  return <String, dynamic>{};
}

List<dynamic> asList(Object? value) => value is List ? value : const [];

String asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString();
  return string.isEmpty ? fallback : string;
}

String? nullableString(Object? value) {
  if (value == null) return null;
  final string = value.toString();
  return string.isEmpty ? null : string;
}

DateTime? asNullableDateTime(Object? value) {
  final string = nullableString(value);
  if (string == null) return null;
  return DateTime.tryParse(string);
}

int asInt(Object? value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ??
      double.tryParse(value.toString())?.round() ??
      fallback;
}

int? asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ??
      double.tryParse(value.toString())?.round();
}

double asDouble(Object? value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

bool asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1' || text == 'yes';
}

List<Instrument> fallbackInstruments() {
  return const [
    Instrument(
      symbol: 'BTC-USDT',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 10000000,
      quantityStepUnits: 100000,
      pricePrecision: 1,
      quantityPrecision: 0,
      maxLeveragePpm: 100000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'ETH-USDT',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'ETH',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 100000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'BTC-USDC',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'BTC',
      quoteAsset: 'USDC',
      settleAsset: 'USDC',
      priceTickUnits: 10000000,
      quantityStepUnits: 100000,
      pricePrecision: 1,
      quantityPrecision: 0,
      maxLeveragePpm: 100000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'SOL-USDT',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'SOL',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 50000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'ETH-USDC',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'ETH',
      quoteAsset: 'USDC',
      settleAsset: 'USDC',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 100000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'XAUT-USDT',
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: 'XAUT',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 20000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'BTC-USDT-SPOT',
      instrumentType: 'SPOT',
      contractType: 'SPOT',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 10000000,
      quantityStepUnits: 100000,
      pricePrecision: 1,
      quantityPrecision: 0,
      maxLeveragePpm: 1000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'ETH-USDT-SPOT',
      instrumentType: 'SPOT',
      contractType: 'SPOT',
      baseAsset: 'ETH',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 1000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'SOL-USDT-SPOT',
      instrumentType: 'SPOT',
      contractType: 'SPOT',
      baseAsset: 'SOL',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 1,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 1000000,
      status: 'TRADING',
    ),
    Instrument(
      symbol: 'BTC-USDT-260925',
      instrumentType: 'DELIVERY',
      contractType: 'LINEAR_DELIVERY',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 10000000,
      quantityStepUnits: 100000,
      pricePrecision: 1,
      quantityPrecision: 0,
      maxLeveragePpm: 50000000,
      status: 'TRADING',
      underlyingSymbol: 'BTC-USDT',
      settlementMethod: 'CASH',
    ),
    Instrument(
      symbol: 'BTC-USD-260925',
      instrumentType: 'DELIVERY',
      contractType: 'INVERSE_DELIVERY',
      baseAsset: 'BTC',
      quoteAsset: 'USD',
      settleAsset: 'BTC',
      priceTickUnits: 10000000,
      quantityStepUnits: 100000,
      pricePrecision: 1,
      quantityPrecision: 0,
      maxLeveragePpm: 50000000,
      status: 'TRADING',
      underlyingSymbol: 'BTC-USD',
      settlementMethod: 'CASH',
    ),
    Instrument(
      symbol: 'BTC-USDT-260925-70000-C',
      instrumentType: 'OPTION',
      contractType: 'VANILLA_OPTION',
      baseAsset: 'BTC',
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1000000,
      quantityStepUnits: 100000,
      pricePrecision: 2,
      quantityPrecision: 0,
      maxLeveragePpm: 1000000,
      status: 'TRADING',
      underlyingSymbol: 'BTC-USDT',
      strikePriceUnits: 7000000000000,
      optionType: 'CALL',
      optionExerciseStyle: 'EUROPEAN',
      settlementMethod: 'CASH',
    ),
  ];
}

List<Candle> fallbackCandles() {
  final now = DateTime.now().subtract(const Duration(minutes: 80));
  var price = 65000.0;
  return List.generate(80, (index) {
    final swing = math.sin(index / 5.0) * 180 + math.cos(index / 3.0) * 80;
    final open = price;
    final close = price + swing / 12;
    final high = math.max(open, close) + 90 + index % 7;
    final low = math.min(open, close) - 80 - index % 5;
    price = close;
    return Candle(
      openTime: now.add(Duration(minutes: index)),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: 80 + index * 3.0,
    );
  });
}
