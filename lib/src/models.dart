import 'dart:math' as math;

enum ProductMode {
  spot('现货', 'SPOT'),
  linear('U本位', 'LINEAR_PERPETUAL'),
  inverse('币本位', 'INVERSE_PERPETUAL');

  const ProductMode(this.label, this.contractType);

  final String label;
  final String contractType;

  String get accountType {
    return switch (this) {
      ProductMode.spot => 'SPOT',
      ProductMode.linear => 'USDT_PERPETUAL',
      ProductMode.inverse => 'COIN_PERPETUAL',
    };
  }
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

  ProductMode get mode {
    if (contractType == ProductMode.spot.contractType) return ProductMode.spot;
    if (contractType == ProductMode.inverse.contractType) {
      return ProductMode.inverse;
    }
    return ProductMode.linear;
  }

  String get displayName => symbol.replaceAll('-SPOT', '');

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

int asInt(Object? value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString()) ??
      double.tryParse(value.toString())?.round() ??
      fallback;
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
