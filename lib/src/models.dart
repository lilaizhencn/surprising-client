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
  // All six products expose owner-bound committed order and trigger receipts.
  bool get tracksSingleOrderIntent => true;
  bool get tracksTriggerIntent => true;
  bool get isPerpetual =>
      this == ProductMode.linear || this == ProductMode.inverse;
  bool get isDelivery =>
      this == ProductMode.linearDelivery || this == ProductMode.inverseDelivery;
  bool get isOption => this == ProductMode.option;
  bool get isExpiring => isDelivery || isOption;
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

enum ValuationCurrency {
  usdt('USDT', ''),
  usd('USD', '\$'),
  cny('CNY', '¥');

  const ValuationCurrency(this.code, this.symbol);

  final String code;
  final String symbol;

  static ValuationCurrency fromCode(String value) {
    final normalized = value.trim().toUpperCase();
    return ValuationCurrency.values.firstWhere(
      (currency) => currency.code == normalized,
      orElse: () => ValuationCurrency.usdt,
    );
  }
}

enum ClientTheme {
  dark('深色', 'dark'),
  light('浅色', 'light');

  const ClientTheme(this.label, this.code);

  final String label;
  final String code;

  static ClientTheme fromCode(String value) {
    return ClientTheme.values.firstWhere(
      (theme) => theme.code == value.trim().toLowerCase(),
      orElse: () => ClientTheme.dark,
    );
  }
}

enum ClientLanguage {
  zhHans('简体中文', 'zh'),
  en('English', 'en');

  const ClientLanguage(this.label, this.code);

  final String label;
  final String code;

  static ClientLanguage fromCode(String value) {
    return ClientLanguage.values.firstWhere(
      (language) => language.code == value.trim().toLowerCase(),
      orElse: () => ClientLanguage.zhHans,
    );
  }
}

const productAccountTypes = [
  'FUNDING',
  'SPOT',
  'USDT_PERPETUAL',
  'COIN_PERPETUAL',
  'USDT_DELIVERY',
  'COIN_DELIVERY',
  'OPTION',
];

String productAccountLabel(String type) {
  return switch (type) {
    'FUNDING' => '资金账户',
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

const bboPriceModes = [
  'OPPONENT_1',
  'OPPONENT_5',
  'SAME_SIDE_1',
  'SAME_SIDE_5',
];

String bboPriceModeLabel(String mode) => switch (mode) {
  'OPPONENT_1' => '对手价 1',
  'OPPONENT_5' => '对手价 5',
  'SAME_SIDE_1' => '同向价 1',
  'SAME_SIDE_5' => '同向价 5',
  _ => mode,
};

void validateOrderPolicy(String type, String tif, bool postOnly, String? bbo) {
  if (!['LIMIT', 'MARKET'].contains(type) ||
      !['GTC', 'IOC', 'FOK', 'GTX'].contains(tif)) {
    throw const FormatException('请选择有效的委托方式');
  }
  if (type == 'MARKET' &&
      (!['IOC', 'FOK'].contains(tif) || postOnly || bbo != null)) {
    throw const FormatException('市价单仅支持 IOC/FOK，不能使用只挂单或 BBO');
  }
  if (postOnly && !['GTC', 'GTX'].contains(tif)) {
    throw const FormatException('只挂单不能与 IOC/FOK 同时使用');
  }
  if (bbo != null && !bboPriceModes.contains(bbo)) {
    throw const FormatException('请选择有效的 BBO 定价方式');
  }
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

const _productionGatewayBaseUrl = 'https://ex-api.tokdou.com';
const _productionWebsocketUrl = 'wss://ex-api.tokdou.com/ws/v1';

class AppConfig {
  const AppConfig({
    this.gatewayBaseUrl = const String.fromEnvironment(
      'SURPRISING_GATEWAY_URL',
      defaultValue: _productionGatewayBaseUrl,
    ),
    this.websocketUrl = const String.fromEnvironment(
      'SURPRISING_WEBSOCKET_URL',
      defaultValue: _productionWebsocketUrl,
    ),
    this.localWebSocketUserFallback = const bool.fromEnvironment(
      'SURPRISING_WS_QUERY_USER_ID',
      defaultValue: false,
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
    this.displayName,
    required this.email,
    required this.status,
  });

  final int userId;
  final String username;
  final String? displayName;
  String get name =>
      displayName?.trim().isNotEmpty == true ? displayName! : username;
  final String email;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'displayName': displayName,
      'email': email,
      'status': status,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      userId: asInt(json['userId']),
      displayName: nullableString(json['displayName']),
      email: asString(json['email']),
      username: asString(
        json['username'],
        fallback: asString(json['email'], fallback: '账户'),
      ),
      status: asString(json['status'], fallback: 'ACTIVE'),
    );
  }
}

class LoginChallenge implements Exception {
  LoginChallenge.fromJson(Map<String, dynamic> json)
    : token = asString(json['challengeToken']),
      expiresAt = DateTime.parse(asString(json['expiresAt'])),
      methods = asList(json['methods']).map(asMap).toList() {
    if (token.isEmpty ||
        methods.isEmpty ||
        methods.any((m) => !['EMAIL', 'PHONE', 'TOTP'].contains(m['type']))) {
      throw const FormatException('不支持的登录验证方式');
    }
  }
  final String token;
  final DateTime expiresAt;
  final List<Map<String, dynamic>> methods;
  bool get expired => !expiresAt.isAfter(DateTime.now());
}

class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    this.requiresEmailVerification = false,
    this.accessTokenExpiresAt,
    this.refreshTokenExpiresAt,
  });

  final AuthUser user;
  final String accessToken;
  final String refreshToken;
  final bool requiresEmailVerification;
  final DateTime? accessTokenExpiresAt;
  final DateTime? refreshTokenExpiresAt;

  bool get refreshTokenExpired {
    final expiresAt = refreshTokenExpiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc());
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'requiresEmailVerification': requiresEmailVerification,
      if (accessTokenExpiresAt != null)
        'accessTokenExpiresAt': accessTokenExpiresAt!.toUtc().toIso8601String(),
      if (refreshTokenExpiresAt != null)
        'refreshTokenExpiresAt': refreshTokenExpiresAt!
            .toUtc()
            .toIso8601String(),
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: AuthUser.fromJson(asMap(json['user'])),
      accessToken: asString(json['accessToken']),
      refreshToken: asString(json['refreshToken']),
      requiresEmailVerification: json['requiresEmailVerification'] == true,
      accessTokenExpiresAt: asNullableDateTime(json['accessTokenExpiresAt']),
      refreshTokenExpiresAt: asNullableDateTime(json['refreshTokenExpiresAt']),
    );
  }
}

class Instrument {
  const Instrument({
    this.instrumentId = '',
    this.lastPrice,
    this.change24h,
    this.volume24h,
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
    this.underlyingInstrumentId,
    this.underlyingProductLine,
    this.strikePriceUnits,
    this.optionType,
    this.optionExerciseStyle,
    this.settlementMethod,
    this.changeId,
    this.notionalMultiplierUnits,
    this.settleScaleUnits,
    this.baseScaleUnits,
    this.quoteScaleUnits,
    this.minQuantitySteps,
    this.maxQuantitySteps,
    this.minNotionalUnits,
    this.maxNotionalUnits,
  });

  final String instrumentId;
  final double? lastPrice;
  final double? change24h;
  final double? volume24h;
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
  final String? underlyingInstrumentId;
  final String? underlyingProductLine;
  final int? strikePriceUnits;
  final String? optionType;
  final String? optionExerciseStyle;
  final String? settlementMethod;
  final int? changeId;
  final int? notionalMultiplierUnits;
  final int? settleScaleUnits;
  final int? baseScaleUnits;
  final int? quoteScaleUnits;
  final int? minQuantitySteps;
  final int? maxQuantitySteps;
  final int? minNotionalUnits;
  final int? maxNotionalUnits;

  factory Instrument.empty(ProductMode mode) {
    return Instrument(
      symbol: '',
      instrumentType: 'UNKNOWN',
      contractType: mode.contractType,
      baseAsset: '',
      quoteAsset: '',
      settleAsset: '',
      priceTickUnits: 0,
      quantityStepUnits: 0,
      pricePrecision: 0,
      quantityPrecision: 0,
      maxLeveragePpm: 0,
      status: 'UNAVAILABLE',
    );
  }

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
  bool get isExpiring => mode.isExpiring;
  String get contractLabel => mode.contractLabel;

  bool canPlaceOrder({required bool reduceOnly}) => isOption
      ? status == 'TRADING' &&
            expiryTime != null &&
            expiryTime!.isAfter(DateTime.now().toUtc())
      : status == 'TRADING' ||
            (isDelivery && status == 'SETTLING' && reduceOnly);

  /// Conditional protection cannot be introduced during settlement or after expiry.
  bool canPlaceTrigger({DateTime? now}) =>
      isDerivative &&
      status == 'TRADING' &&
      (!isExpiring ||
          (expiryTime != null &&
              expiryTime!.isAfter(now ?? DateTime.now().toUtc())));

  bool effectiveReduceOnly({
    required bool reduceOnly,
    required String side,
    required String positionMode,
    required String positionSide,
  }) =>
      reduceOnly ||
      (isExpiring &&
          positionMode == 'HEDGE' &&
          ((positionSide == 'LONG' && side == 'SELL') ||
              (positionSide == 'SHORT' && side == 'BUY')));

  String get displayName => symbol.replaceAll('-SPOT', '');

  double? get strikePrice {
    final units = strikePriceUnits;
    if (units == null || quoteScaleUnits == null || quoteScaleUnits! <= 0) {
      return null;
    }
    return units / quoteScaleUnits!;
  }

  double priceFromTicks(int ticks) {
    final scale = quoteScaleUnits;
    return scale == null || scale <= 0
        ? double.nan
        : (BigInt.from(ticks) * BigInt.from(priceTickUnits)).toDouble() / scale;
  }

  /// A submitted price must match the declared quote scale and tick exactly.
  int? priceTicksFromText(String price) =>
      decimalIncrement(price, priceTickUnits, scaleUnits: quoteScaleUnits ?? 0);

  int ticksFromPrice(double price) {
    if (isSpot) {
      final ticks = priceTicksFromText('$price');
      if (ticks == null || ticks <= 0) {
        throw const FormatException('价格精度未就绪或价格不符合步长');
      }
      return ticks;
    }
    // Display/reference conversion only. Submitted orders use priceTicksFromText.
    final scale = quoteScaleUnits;
    if (scale == null ||
        scale <= 0 ||
        priceTickUnits <= 0 ||
        !price.isFinite ||
        price <= 0) {
      return 0;
    }
    return (price * scale / priceTickUnits).round();
  }

  factory Instrument.fromJson(Map<String, dynamic> json) {
    double? number(String key) => double.tryParse(asString(json[key]));
    return Instrument(
      instrumentId: asString(json['instrumentId']),
      lastPrice: number('lastPrice'),
      change24h:
          number('change24h') ??
          (number('change24hPpm') == null
              ? null
              : number('change24hPpm')! / 10000),
      volume24h: number('volume24h'),
      symbol: asString(json['symbol']),
      instrumentType: asString(json['instrumentType'], fallback: 'PERPETUAL'),
      contractType: asString(
        json['contractType'],
        fallback: 'LINEAR_PERPETUAL',
      ),
      baseAsset: asString(json['baseAsset'], fallback: 'BTC'),
      quoteAsset: asString(json['quoteAsset'], fallback: 'USDT'),
      settleAsset: asString(json['settleAsset'], fallback: 'USDT'),
      priceTickUnits: asInt(
        json['priceTickUnits'],
        fallback: json['contractType'] == 'SPOT' ? 0 : 10000000,
      ),
      quantityStepUnits: asInt(
        json['quantityStepUnits'],
        fallback: json['contractType'] == 'SPOT' ? 0 : 1,
      ),
      pricePrecision: asInt(json['pricePrecision'], fallback: 2),
      quantityPrecision: asInt(json['quantityPrecision'], fallback: 0),
      maxLeveragePpm: asInt(json['maxLeveragePpm'], fallback: 1000000),
      status: asString(
        json['status'],
        fallback:
            (json['contractType'] == 'LINEAR_DELIVERY' ||
                json['contractType'] == 'INVERSE_DELIVERY' ||
                json['contractType'] == 'VANILLA_OPTION')
            ? 'UNAVAILABLE'
            : 'TRADING',
      ),
      expiryTime: asNullableDateTime(json['expiryTime']),
      deliveryTime: asNullableDateTime(json['deliveryTime']),
      underlyingSymbol: nullableString(json['underlyingSymbol']),
      underlyingInstrumentId: nullableString(json['underlyingInstrumentId']),
      underlyingProductLine: nullableString(json['underlyingProductLine']),
      strikePriceUnits: asNullableInt(json['strikePriceUnits']),
      optionType: nullableString(json['optionType']),
      optionExerciseStyle: nullableString(json['optionExerciseStyle']),
      settlementMethod: nullableString(json['settlementMethod']),
      changeId: asNullableInt(json['changeId']),
      notionalMultiplierUnits: asNullableInt(json['notionalMultiplierUnits']),
      settleScaleUnits: asNullableInt(json['settleScaleUnits']),
      baseScaleUnits: asNullableInt(json['baseScaleUnits']),
      quoteScaleUnits: asNullableInt(json['quoteScaleUnits']),
      minQuantitySteps: asNullableInt(json['minQuantitySteps']),
      maxQuantitySteps: asNullableInt(json['maxQuantitySteps']),
      minNotionalUnits: asNullableInt(json['minNotionalUnits']),
      maxNotionalUnits: asNullableInt(json['maxNotionalUnits']),
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
    List<OrderBookLevel> levels(String side) {
      final byPrice = <int, OrderBookLevel>{};
      for (final raw in asList(json[side])) {
        final level = OrderBookLevel.fromJson(asMap(raw));
        if (level.priceTicks > 0 && level.quantitySteps > 0) {
          byPrice[level.priceTicks] = level;
        }
      }
      final sorted = byPrice.values.toList()
        ..sort(
          (a, b) => side == 'bids'
              ? b.priceTicks.compareTo(a.priceTicks)
              : a.priceTicks.compareTo(b.priceTicks),
        );
      return sorted.take(50).toList();
    }

    return OrderBook(
      symbol: asString(json['symbol']),
      sequence: asInt(json['sequence']),
      bids: levels('bids'),
      asks: levels('asks'),
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

class PrimaryAuthenticationContext {
  const PrimaryAuthenticationContext({
    required this.passwordRequired,
    required this.reauthenticationRequired,
    this.authenticatedUntil,
  });
  final bool passwordRequired;
  final bool reauthenticationRequired;
  final DateTime? authenticatedUntil;

  factory PrimaryAuthenticationContext.fromJson(Map<String, dynamic> value) {
    if (value['passwordRequired'] is! bool ||
        value['reauthenticationRequired'] is! bool) {
      throw const FormatException('安全身份资料暂不可用');
    }
    final until = value['authenticatedUntil'];
    final parsed = until is String ? DateTime.tryParse(until) : null;
    if ((until != null && parsed == null) ||
        (value['passwordRequired'] == false &&
            value['reauthenticationRequired'] == false &&
            parsed == null)) {
      throw const FormatException('安全身份资料暂不可用');
    }
    return PrimaryAuthenticationContext(
      passwordRequired: value['passwordRequired'] as bool,
      reauthenticationRequired: value['reauthenticationRequired'] as bool,
      authenticatedUntil: parsed,
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
    this.scaleUnits,
  });

  final String accountType;
  final String asset;
  final int availableUnits;
  final int lockedUnits;
  final int equityUnits;
  final int? scaleUnits;

  bool get hasScale =>
      scaleUnits != null && RegExp(r'^10*$').hasMatch('$scaleUnits');
  double? _amount(int units) => units == 0
      ? 0
      : hasScale
      ? units / scaleUnits!
      : null;
  double? get available => _amount(availableUnits);
  double? get locked => _amount(lockedUnits);
  double? get equity => _amount(equityUnits);

  factory ProductBalance.fromJson(
    Map<String, dynamic> json, {
    int? scaleUnits,
  }) {
    return ProductBalance(
      accountType: asString(json['accountType'], fallback: 'SPOT'),
      asset: asString(json['asset'], fallback: 'USDT'),
      availableUnits: asInt(json['availableUnits']),
      lockedUnits: asInt(json['lockedUnits']),
      equityUnits: asInt(json['equityUnits']),
      scaleUnits: scaleUnits,
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
    this.instrumentId = '',
    this.marginAsset = '',
    this.positionMarginUnits,
  });

  final String symbol;
  final String marginMode;
  final String positionSide;
  final int signedQuantitySteps;
  final int entryPriceTicks;
  final int? realizedPnlUnits;
  final String instrumentId;
  final String marginAsset;
  final int? positionMarginUnits;

  bool get isLong => signedQuantitySteps >= 0;

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      symbol: asString(json['symbol']),
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      signedQuantitySteps: asInt(json['signedQuantitySteps']),
      entryPriceTicks: asInt(json['entryPriceTicks']),
      realizedPnlUnits: asNullableInt(json['realizedPnlUnits']),
      instrumentId: asString(json['instrumentId']),
      marginAsset: asString(json['marginAsset']),
      positionMarginUnits: asNullableInt(json['positionMarginUnits']),
    );
  }
}

/// Fixed cancellation targets and confirmed progress, not live order state.
class CancellationBatch {
  CancellationBatch(this.key, List<int> orderIds)
    : orderIds = List.unmodifiable(orderIds) {
    if (key.isEmpty ||
        key.length > 64 ||
        orderIds.isEmpty ||
        orderIds.length > 50 ||
        orderIds.any((id) => id <= 0)) {
      throw const FormatException('批量撤单资料无效');
    }
  }
  final String key;
  final List<int> orderIds;
  Map<String, dynamic> toJson() => {'key': key, 'orderIds': orderIds};
  factory CancellationBatch.fromJson(Map<String, dynamic> json) =>
      CancellationBatch(
        asString(json['key']),
        asList(json['orderIds']).map(asInt).toList(),
      );
}

class CancellationPlan {
  CancellationPlan({
    required this.id,
    required List<CancellationBatch> batches,
    this.index = 0,
    this.issued = false,
    this.completed = 0,
    this.failed = 0,
    List<({int orderId, String code})> failures = const [],
    this.instrumentId,
  }) : batches = List.unmodifiable(batches),
       failures = List.unmodifiable(failures) {
    if (id.isEmpty ||
        batches.isEmpty ||
        index < 0 ||
        index > batches.length ||
        completed < 0 ||
        failed < 0 ||
        completed + failed !=
            batches.take(index).fold<int>(0, (n, b) => n + b.orderIds.length) ||
        failures.length != failed ||
        (index == batches.length && issued) ||
        batches.map((b) => b.key).toSet().length != batches.length ||
        batches.expand((b) => b.orderIds).toSet().length !=
            batches.fold<int>(0, (n, b) => n + b.orderIds.length) ||
        failures.any(
          (f) =>
              f.orderId <= 0 ||
              f.code.isEmpty ||
              !batches.take(index).any((b) => b.orderIds.contains(f.orderId)),
        )) {
      throw const FormatException('批量撤单恢复资料无效');
    }
  }
  final String id;
  final String? instrumentId;
  final List<CancellationBatch> batches;
  final int index, completed, failed;
  final bool issued;
  final List<({int orderId, String code})> failures;
  int get requested => batches.fold(0, (n, b) => n + b.orderIds.length);
  CancellationPlan markIssued() => CancellationPlan(
    id: id,
    batches: batches,
    index: index,
    issued: true,
    completed: completed,
    failed: failed,
    failures: failures,
    instrumentId: instrumentId,
  );
  CancellationPlan advance(OrderBatchResult result) {
    final ids = batches[index].orderIds;
    if (result.requested != ids.length ||
        result.results.length != ids.length ||
        result.completed + result.failed != ids.length) {
      throw const FormatException('批量撤单回执不完整');
    }
    final rejected = <({int orderId, String code})>[];
    var applied = 0;
    for (var i = 0; i < ids.length; i++) {
      final item = result.results[i];
      if (item.index != i ||
          item.message.isEmpty ||
          (item.success && item.message != 'NONE') ||
          (!item.success && item.message == 'NONE') ||
          (item.order != null && item.order!.orderId != ids[i])) {
        throw const FormatException('批量撤单回执不匹配');
      }
      if (item.success) {
        applied++;
      } else {
        rejected.add((orderId: ids[i], code: item.message));
      }
    }
    if (result.completed != applied || result.failed != rejected.length) {
      throw const FormatException('批量撤单计数不匹配');
    }
    return CancellationPlan(
      id: id,
      batches: batches,
      index: index + 1,
      issued: false,
      completed: completed + applied,
      failed: failed + rejected.length,
      failures: [...failures, ...rejected],
      instrumentId: instrumentId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'instrumentId': instrumentId,
    'batches': batches.map((b) => b.toJson()).toList(),
    'index': index,
    'issued': issued,
    'completed': completed,
    'failed': failed,
    'failures': failures
        .map((f) => {'orderId': f.orderId, 'code': f.code})
        .toList(),
  };
  factory CancellationPlan.fromJson(Map<String, dynamic> json) =>
      CancellationPlan(
        id: asString(json['id']),
        instrumentId: json['instrumentId'] as String?,
        batches: asList(
          json['batches'],
        ).map((b) => CancellationBatch.fromJson(asMap(b))).toList(),
        index: asInt(json['index']),
        issued: asBool(json['issued']),
        completed: asInt(json['completed']),
        failed: asInt(json['failed']),
        failures: asList(json['failures']).map((f) {
          final row = asMap(f);
          return (orderId: asInt(row['orderId']), code: asString(row['code']));
        }).toList(),
      );
}

class CancellationSummary {
  const CancellationSummary(
    this.userId,
    this.requested,
    this.completed,
    this.failed,
    this.failures,
  );
  final int userId, requested, completed, failed;
  final List<({int orderId, String code})> failures;
}

/// A persisted submission identity, kept until a receipt or realtime order confirms it.
class PendingTradingOrder {
  const PendingTradingOrder({
    required this.userId,
    required this.product,
    this.commandId,
    this.clientOrderId,
    this.instrumentId,
    this.cancelOrderId,
    this.amendRequestId,
    this.amendOrderId,
    this.cancelPlan,
    this.ocoTakeProfitClientId,
    this.ocoStopLossClientId,
    this.clientTriggerOrderId,
    this.cancelTriggerOrderId,
  });
  final CancellationPlan? cancelPlan;
  final String? amendRequestId;
  final int? amendOrderId;
  final int userId;
  final int? cancelOrderId;
  final ProductMode product;
  final String? commandId, clientOrderId, instrumentId;
  final String? ocoTakeProfitClientId, ocoStopLossClientId;
  final String? clientTriggerOrderId;
  final int? cancelTriggerOrderId;
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
    this.averagePriceTicks,
    this.executedValueTicks,
    this.cumulativeFeeUnits,
    this.createdAt,
    this.updatedAt,
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
  final String? averagePriceTicks;
  final String? executedValueTicks;
  final int? cumulativeFeeUnits;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get fillProgress =>
      quantitySteps <= 0 ||
          executedQuantitySteps < 0 ||
          executedQuantitySteps > quantitySteps
      ? '--'
      : '${(BigInt.from(executedQuantitySteps) * BigInt.from(10000) ~/ BigInt.from(quantitySteps)).toInt() / 100}%';

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
      averagePriceTicks: nullableString(json['averagePriceTicks']),
      executedValueTicks: nullableString(json['executedValueTicks']),
      cumulativeFeeUnits: asNullableInt(json['cumulativeFeeUnits']),
      createdAt: orderTimestamp(
        json['createdAtEpochMillis'] ?? json['createdAt'],
      ),
      updatedAt: orderTimestamp(
        json['updatedAtEpochMillis'] ?? json['updatedAt'],
      ),
    );
  }
}

class OpenOrdersPage {
  const OpenOrdersPage({
    required this.orders,
    required this.nextCursor,
    required this.hasMore,
    required this.sort,
    required this.limit,
  });

  final List<OrderModel> orders;
  final String? nextCursor;
  final bool hasMore;
  final String sort;
  final int limit;
}

class TestOrderResult {
  const TestOrderResult({
    required this.accepted,
    required this.instrumentChangeId,
    required this.validationStage,
    required this.estimatedReserveUnits,
    this.rejectReason,
    this.accountType,
    this.asset,
  });

  final bool accepted;
  final String? rejectReason;
  final int instrumentChangeId;
  final String validationStage;
  final String? accountType;
  final String? asset;
  final int estimatedReserveUnits;

  factory TestOrderResult.fromJson(Map<String, dynamic> json) {
    return TestOrderResult(
      accepted: asBool(json['accepted']),
      rejectReason: nullableString(json['rejectReason']),
      instrumentChangeId: asInt(json['instrumentChangeId']),
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

  /// Cancellation progress must not accept defaulted fields from an incomplete receipt.
  factory OrderBatchResult.fromCancellationJson(Map<String, dynamic> json) {
    final rows = json['results'];
    if (json['requested'] is! int ||
        json['completed'] is! int ||
        json['failed'] is! int ||
        rows is! List ||
        rows.isEmpty ||
        rows.length > 50) {
      throw const FormatException('批量撤单回执不完整');
    }
    for (final value in rows) {
      final item = asMap(value);
      if (item['index'] is! int ||
          item['success'] is! bool ||
          item['message'] is! String) {
        throw const FormatException('批量撤单回执字段无效');
      }
    }
    return OrderBatchResult.fromJson(json);
  }

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
    required this.userId,
    required this.instrumentId,
    required this.product,
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
  final int userId;
  final String instrumentId;
  final ProductMode product;
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

  bool get isOpen =>
      const ['PENDING', 'RUNNING', 'CANCEL_REQUESTED'].contains(status);

  factory AlgoOrderModel.fromJson(
    Map<String, dynamic> json, {
    required ProductMode product,
  }) {
    int integer(String key, {int minimum = 0}) {
      final raw = json[key];
      final text = '$raw';
      final value =
          (raw is int || raw is String) && RegExp(r'^\d+$').hasMatch(text)
          ? BigInt.tryParse(text)
          : null;
      if (value == null ||
          value < BigInt.from(minimum) ||
          value > BigInt.from(9223372036854775807)) {
        throw FormatException('算法单 $key 无效');
      }
      return value.toInt();
    }

    final instrumentId = asString(json['instrumentId']);
    final quantity = integer('quantitySteps', minimum: 1);
    final child = integer('childQuantitySteps', minimum: 1);
    final executed = integer('executedQuantitySteps');
    final active = integer('activeQuantitySteps');
    final type = json['algoType'];
    final status = json['status'];
    final price = integer('priceTicks');
    final interval = integer('intervalSeconds', minimum: 1);
    final duration = integer('durationSeconds', minimum: 1);
    if (!RegExp(r'^[1-9]\d*$').hasMatch(instrumentId) ||
        asString(json['clientAlgoOrderId']).trim().isEmpty ||
        asString(json['clientAlgoOrderId']).length > 64 ||
        (json.containsKey('productLine') &&
            json['productLine'] != product.productLine) ||
        !const ['TWAP', 'ICEBERG'].contains(type) ||
        !const ['BUY', 'SELL'].contains(json['side']) ||
        !const ['CROSS', 'ISOLATED'].contains(json['marginMode']) ||
        !const ['NET', 'LONG', 'SHORT'].contains(json['positionSide']) ||
        !const ['GTC', 'GTX', 'IOC'].contains(json['timeInForce']) ||
        !const [
          'PENDING',
          'RUNNING',
          'CANCEL_REQUESTED',
          'CANCELED',
          'COMPLETED',
          'FAILED',
        ].contains(status) ||
        json['reduceOnly'] is! bool ||
        json['postOnly'] is! bool ||
        child > quantity ||
        BigInt.from(executed) + BigInt.from(active) > BigInt.from(quantity) ||
        (type == 'ICEBERG' && price == 0) ||
        duration < interval ||
        (product.isSpot &&
            (json['positionSide'] != 'NET' || json['reduceOnly'] != false))) {
      throw const FormatException('算法单身份或进度无效');
    }
    return AlgoOrderModel(
      algoOrderId: integer('algoOrderId', minimum: 1),
      userId: integer('userId', minimum: 1),
      instrumentId: instrumentId,
      product: product,
      clientAlgoOrderId: nullableString(json['clientAlgoOrderId']),
      symbol: asString(json['symbol']),
      algoType: asString(json['algoType'], fallback: 'TWAP'),
      side: asString(json['side'], fallback: 'BUY'),
      priceTicks: price,
      quantitySteps: quantity,
      childQuantitySteps: child,
      intervalSeconds: interval,
      durationSeconds: duration,
      marginMode: asString(json['marginMode'], fallback: 'CROSS'),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      reduceOnly: asBool(json['reduceOnly']),
      postOnly: asBool(json['postOnly']),
      timeInForce: asString(json['timeInForce'], fallback: 'GTC'),
      status: asString(json['status'], fallback: 'PENDING'),
      executedQuantitySteps: executed,
      activeQuantitySteps: active,
      childOrderCount: integer('childOrderCount'),
      currentOrderId: json['currentOrderId'] == null
          ? null
          : integer('currentOrderId', minimum: 1),
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

  factory AlgoOrderBatchItem.fromJson(
    Map<String, dynamic> json, {
    required ProductMode product,
  }) {
    final rawOrder = json['algoOrder'];
    return AlgoOrderBatchItem(
      index: asInt(json['index']),
      success: asBool(json['success']),
      message: asString(json['message']),
      order: rawOrder == null
          ? null
          : AlgoOrderModel.fromJson(asMap(rawOrder), product: product),
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

  factory AlgoOrderBatchResult.fromJson(
    Map<String, dynamic> json, {
    required ProductMode product,
  }) {
    return AlgoOrderBatchResult(
      requested: asInt(json['requested']),
      completed: asInt(json['completed']),
      failed: asInt(json['failed']),
      results: asList(json['results'])
          .map(
            (item) =>
                AlgoOrderBatchItem.fromJson(asMap(item), product: product),
          )
          .toList(),
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
    this.instrumentId = '',
    this.clientTriggerOrderId = '',
    this.ocoGroupId,
    this.priceSource = 'MARK',
    this.userId = 0,
  });

  final int triggerOrderId;
  final String symbol;
  final String side;
  final String triggerType;
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
  final String instrumentId, clientTriggerOrderId, priceSource;
  final String? ocoGroupId;
  final int userId;

  factory TriggerOrderModel.fromJson(Map<String, dynamic> json) {
    final placedOrderId = json['placedOrderId'];
    return TriggerOrderModel(
      userId: asInt(json['userId']),
      triggerOrderId: asInt(json['triggerOrderId']),
      instrumentId: asString(json['instrumentId']),
      clientTriggerOrderId: asString(json['clientTriggerOrderId']),
      ocoGroupId: nullableString(json['ocoGroupId']),
      priceSource: asString(json['priceSource'], fallback: 'MARK'),
      symbol: asString(json['symbol']),
      side: asString(json['side'], fallback: 'SELL'),
      triggerType: asString(json['triggerType'], fallback: 'TAKE_PROFIT'),
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

  factory TriggerOrderBatchResult.fromAtomicOcoJson(Map<String, dynamic> json) {
    final rows = json['results'];
    if (json['requested'] is! int ||
        json['completed'] is! int ||
        json['failed'] is! int ||
        rows is! List ||
        rows.length != 2) {
      throw const FormatException('OCO 回执字段不完整');
    }
    for (final value in rows) {
      final row = asMap(value);
      if (row['index'] is! int ||
          row['success'] is! bool ||
          row['order'] is! Map) {
        throw const FormatException('OCO 回执档位不完整');
      }
    }
    return TriggerOrderBatchResult.fromJson(json);
  }

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
    required this.triggerPriceTicks,
    this.activationPriceTicks,
    this.callbackRatePpm,
    required this.quantitySteps,
    required this.marginMode,
    required this.positionSide,
    this.priceSource = 'MARK',
    this.orderType = 'MARKET',
    this.priceTicks = 0,
  });

  final String side;
  final String triggerType;
  final int triggerPriceTicks;
  final int? activationPriceTicks;
  final int? callbackRatePpm;
  final int quantitySteps;
  final String marginMode;
  final String positionSide;
  final String priceSource, orderType;
  final int priceTicks;
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
    this.maintenanceMarginUnits,
    this.liquidationPriceTicks,
  });

  final String symbol;
  final String positionSide;
  final int markPriceTicks;
  final int? unrealizedPnlUnits;
  final int positionMarginUnits;
  final int? marginRatioPpm;
  final String status;
  final int? maintenanceMarginUnits;
  final int? liquidationPriceTicks;

  factory PositionRisk.fromJson(Map<String, dynamic> json) {
    return PositionRisk(
      symbol: asString(json['symbol']),
      positionSide: asString(json['positionSide'], fallback: 'NET'),
      markPriceTicks: asInt(json['markPriceTicks']),
      unrealizedPnlUnits: asNullableInt(json['unrealizedPnlUnits']),
      positionMarginUnits: asInt(json['positionMarginUnits']),
      marginRatioPpm: asNullableInt(json['marginRatioPpm']),
      status: asString(json['status'], fallback: 'PENDING'),
      maintenanceMarginUnits: asNullableInt(json['maintenanceMarginUnits']),
      liquidationPriceTicks: asNullableInt(json['liquidationPriceTicks']),
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
        symbol: 'SPEX',
        availableBalance: 135.00000009,
        lockedBalance: 0,
        totalBalance: 135.00000009,
        chains: [
          WalletChainAsset(
            chain: 'Surprising Chain',
            symbol: 'SPEX',
            network: 'Surprising Chain',
            family: 'EVM',
            standard: 'Native',
            nativeAsset: true,
            nativeSymbol: 'SPEX',
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
    this.availableBalanceText,
  });

  final String symbol;
  final double availableBalance;
  final double lockedBalance;
  final double totalBalance;
  final List<WalletChainAsset> chains;

  /// Exact decimal from the server; doubles are used only for approximate valuation.
  final String? availableBalanceText;
  String? get availableAmount => plainNonnegativeDecimal(
    availableBalanceText ?? availableBalance.toString(),
  );

  factory WalletAssetSummary.fromJson(Map<String, dynamic> json) {
    return WalletAssetSummary(
      symbol: asString(json['symbol']),
      availableBalance: asDouble(json['availableBalance']),
      availableBalanceText: asString(json['availableBalance']),
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      baseScaleUnits: 100000000,
      quoteScaleUnits: 100000000,
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
      baseScaleUnits: 100000000,
      quoteScaleUnits: 100000000,
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
      baseScaleUnits: 100000000,
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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
      quoteScaleUnits: 100000000,
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

/// REST history and live events overlap after reconnect; retain one row per trade.
List<Map<String, dynamic>> mergeRecentTrades(
  List<Map<String, dynamic>> older,
  List<Map<String, dynamic>> newer,
) {
  final rows = <String, Map<String, dynamic>>{};
  for (final row in [...older, ...newer]) {
    final id = asString(row['tradeId'], fallback: asString(row['sequence']));
    if (id.isEmpty) continue;
    rows[id] = {...?rows[id], ...row};
  }
  final result = rows.values.toList()
    ..sort((a, b) {
      final left = asString(a['tradeId']).split(':');
      final right = asString(b['tradeId']).split(':');
      if (left.length == 5 && right.length == 5 && left.first == right.first) {
        for (var i = 1; i < 5; i++) {
          final l = BigInt.tryParse(left[i]), r = BigInt.tryParse(right[i]);
          if (l == null || r == null) break;
          final order = r.compareTo(l);
          if (order != 0) return order;
        }
      }
      final sequence = a['sequence'] != null && b['sequence'] != null
          ? asInt(b['sequence']).compareTo(asInt(a['sequence']))
          : 0;
      if (sequence != 0) return sequence;
      final time = asString(b['eventTime']).compareTo(asString(a['eventTime']));
      if (time != 0) return time;
      final aId = BigInt.tryParse(asString(a['tradeId'])),
          bId = BigInt.tryParse(asString(b['tradeId']));
      return aId != null && bId != null ? bId.compareTo(aId) : 0;
    });
  return result.take(50).toList();
}

/// Convert a user decimal to integer increments without rounding an invalid tick.
int? decimalIncrement(
  String text,
  int incrementUnits, {
  int scaleUnits = 100000000,
}) {
  if (incrementUnits <= 0 ||
      scaleUnits <= 0 ||
      !RegExp(r'^10*$').hasMatch('$scaleUnits') ||
      !RegExp(r'^(?:\d+(?:\.\d*)?|\.\d+)$').hasMatch(text.trim())) {
    return null;
  }
  final parts = text.trim().split('.');
  final fraction = parts.length == 1 ? '' : parts.last;
  final numerator =
      BigInt.parse('${parts.first.isEmpty ? '0' : parts.first}$fraction') *
      BigInt.from(scaleUnits);
  final divisor =
      BigInt.from(10).pow(fraction.length) * BigInt.from(incrementUnits);
  if (numerator % divisor != BigInt.zero) return null;
  final value = numerator ~/ divisor;
  if (value > BigInt.from(9223372036854775807)) return null;
  return value.toInt();
}

DateTime? orderTimestamp(Object? raw) {
  if (raw == null) return null;
  final millis = int.tryParse('$raw');
  if (millis != null) {
    if (millis <= 0 || millis.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  return DateTime.tryParse('$raw');
}

String scaledAmount(BigInt? units, int? scale) {
  if (units == null || scale == null || scale <= 0) return '--';
  final divisor = BigInt.from(scale);
  final fraction = units.abs().remainder(divisor);
  final digits = scale.toString().length - 1;
  if (BigInt.from(10).pow(digits) != divisor) return '--';
  final tail = fraction
      .toString()
      .padLeft(digits, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${units.isNegative ? '-' : ''}${units.abs() ~/ divisor}${tail.isEmpty ? '' : '.$tail'}';
}

List<OrderBookLevel> aggregateBookLevels(
  List<OrderBookLevel> levels,
  int multiple, {
  required bool bids,
}) {
  if (multiple <= 0) throw ArgumentError.value(multiple, 'multiple');
  final buckets = <int, OrderBookLevel>{};
  for (final level in levels) {
    final bucket =
        (bids
            ? level.priceTicks ~/ multiple
            : (level.priceTicks + multiple - 1) ~/ multiple) *
        multiple;
    final previous = buckets[bucket];
    buckets[bucket] = OrderBookLevel(
      priceTicks: bucket,
      quantitySteps: (previous?.quantitySteps ?? 0) + level.quantitySteps,
      orderCount: (previous?.orderCount ?? 0) + level.orderCount,
    );
  }
  return buckets.values.toList()..sort(
    (a, b) => bids
        ? b.priceTicks.compareTo(a.priceTicks)
        : a.priceTicks.compareTo(b.priceTicks),
  );
}

/// Option premium is paid in full in settlement asset units; leverage does not divide it.
({String premium, String fee, String cash})? optionPremiumTerms({
  required Instrument instrument,
  required String side,
  required int? priceTicks,
  required String quantity,
  required int? takerFeeRatePpm,
}) {
  final contracts = decimalIncrement(quantity, 1, scaleUnits: 1);
  final multiplier = instrument.notionalMultiplierUnits;
  if (!instrument.isOption ||
      priceTicks == null ||
      priceTicks <= 0 ||
      contracts == null ||
      contracts <= 0 ||
      multiplier == null ||
      multiplier <= 0 ||
      instrument.settleScaleUnits == null ||
      takerFeeRatePpm == null ||
      takerFeeRatePpm.abs() > 1000000 ||
      !['BUY', 'SELL'].contains(side)) {
    return null;
  }
  final premium =
      BigInt.from(priceTicks) *
      BigInt.from(contracts) *
      BigInt.from(multiplier);
  if (premium > BigInt.from(9223372036854775807)) return null;
  final fee =
      ((premium * BigInt.from(takerFeeRatePpm.abs()) + BigInt.from(999999)) ~/
          BigInt.from(1000000)) *
      BigInt.from(takerFeeRatePpm < 0 ? -1 : 1);
  final scale = instrument.settleScaleUnits;
  final cash = side == 'BUY' ? premium + fee : premium - fee;
  final result = (
    premium: scaledAmount(premium, scale),
    fee: scaledAmount(fee, scale),
    cash: scaledAmount(cash, scale),
  );
  return result.cash == '--' ? null : result;
}

String triggerPriceSourceLabel(String source) => switch (source) {
  'MARK' => '标记价格',
  'LAST' => '最新成交价',
  'INDEX' => '指数价格',
  _ => '--',
};

// BigDecimal JSON strings may use an exponent. Normalize metadata with integer
// string operations, keeping tiny fees exact and bounding malformed exponents.
String? plainNonnegativeDecimal(String raw) {
  if (raw.length > 256) return null;
  final match = RegExp(
    r'^\+?(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final exponent = int.tryParse(match.group(3) ?? '0');
  if (exponent == null || exponent.abs() > 36) return null;
  final integer = match.group(1)!;
  var digits = integer + (match.group(2) ?? '');
  var point = integer.length + exponent;
  if (point <= 0) {
    digits = '${'0' * (1 - point)}$digits';
    point = 1;
  }
  if (point >= digits.length) digits += '0' * (point - digits.length + 1);
  final whole = digits
      .substring(0, point)
      .replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = digits.substring(point).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}
