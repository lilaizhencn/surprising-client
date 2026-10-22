import 'dart:async';

import 'models.dart';

enum MarketUpdate { ignored, changed, markChanged }

/// Owns public market projections. Session and order state never live here.
class MarketDataState {
  MarketDataState({
    this.snapshotTimeout = const Duration(seconds: 3),
    this.maxSnapshotAttempts = 3,
  });

  final Duration snapshotTimeout;
  final int maxSnapshotAttempts;
  OrderBook orderBook = OrderBook.empty('');
  List<Candle> candles = const [];
  List<Map<String, dynamic>> recentTrades = const [];
  final Map<String, double> latestPrices = {};
  final Map<String, int> markPrices = {};
  final Map<String, Map<String, dynamic>> metrics = {};
  final Map<String, Map<String, dynamic>> _versions = {};
  Timer? _snapshotTimer;
  String? _recovering;
  int _snapshotAttempts = 0;
  bool _closed = false;

  void Function()? requestDepthSnapshot;
  void Function()? reconnectDepth;
  void Function()? onDepthUnavailable;
  void Function(String)? onIssue;

  bool get depthRecovering => _recovering != null;
  String key(ProductMode product, String symbol) =>
      '${product.productLine}:$symbol';
  Map<String, dynamic>? version(String stream) => _versions[stream];
  void resetVersions() => _versions.clear();

  void resetBook(OrderBook book) {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _recovering = null;
    _snapshotAttempts = 0;
    orderBook = book;
  }

  /// Use exact integer arithmetic until the final display conversion.
  double? midpoint(Instrument instrument, int? bid, int? ask) {
    final scale = instrument.quoteScaleUnits;
    if (instrument.priceTickUnits <= 0 || scale == null || scale <= 0) {
      return null;
    }
    final bids = bid != null && bid > 0 ? BigInt.from(bid) : BigInt.zero;
    final asks = ask != null && ask > 0 ? BigInt.from(ask) : BigInt.zero;
    if (bids == BigInt.zero && asks == BigInt.zero) return null;
    final numerator = (bids + asks) * BigInt.from(instrument.priceTickUnits);
    final denominator =
        BigInt.from(scale) *
        BigInt.from(bids > BigInt.zero && asks > BigInt.zero ? 2 : 1);
    final price = numerator / denominator;
    return price.isFinite && price > 0 ? price : null;
  }

  /// Returns false for stale/out-of-order public events before mutating projections.
  bool acceptVersion(
    Map<String, dynamic> message,
    Map<String, dynamic> data,
    String stream,
  ) {
    final envelope = asMap(message['data']);
    final version = asString(envelope['version']);
    final previous = _versions[stream];
    final channel = message['channel'];
    final baseline = channel == 'depth' && data['updateType'] == 'SNAPSHOT';
    if (!baseline && version.isNotEmpty && previous != null) {
      final time = DateTime.tryParse(asString(message['eventTime']));
      final previousTime = DateTime.tryParse(asString(previous['eventTime']));
      final coreStream = ['trades', 'depth', 'bookTicker'].contains(channel);
      if (!coreStream &&
          time != null &&
          previousTime != null &&
          time != previousTime) {
        if (time.isBefore(previousTime)) return false;
      } else if (version.compareTo(asString(previous['version'])) <= 0) {
        return false;
      }
    }
    if (version.isNotEmpty) {
      if (!_versions.containsKey(stream) && _versions.length >= 4096) {
        return false;
      }
      _versions[stream] = {
        'version': version,
        'eventTime': message['eventTime'],
      };
    }
    return true;
  }

  bool validTrade(Map<String, dynamic> trade) {
    final priceTicks = trade['priceTicks'];
    final quantitySteps = trade['quantitySteps'];
    final ticks = parseInt64(priceTicks);
    final steps = parseInt64(quantitySteps);
    double? decimal(Object? value) {
      final parsed = value is num
          ? value.toDouble()
          : value is String && value.length <= 256
          ? double.tryParse(value)
          : null;
      return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
    }

    if (priceTicks != null
        ? ticks == null || ticks <= 0
        : decimal(trade['price']) == null) {
      return false;
    }
    if (quantitySteps != null
        ? steps == null || steps <= 0
        : decimal(trade['quantity']) == null) {
      return false;
    }
    if (trade['sequence'] != null &&
        (parseInt64(trade['sequence']) ?? -1) < 0) {
      return false;
    }
    return true;
  }

  MarketUpdate applyPublicEvent({
    required Map<String, dynamic> message,
    required Instrument instrument,
    required bool selected,
    required String period,
  }) {
    if (_closed) return MarketUpdate.ignored;
    final channel = asString(message['channel']);
    final envelope = asMap(message['data']);
    final data = asMap(
      envelope.containsKey('value') ? envelope['value'] : envelope,
    );
    if (!const {
      'depth',
      'trades',
      'bookTicker',
      'mark',
      'index',
      'funding',
      'candles',
    }.contains(channel)) {
      return MarketUpdate.ignored;
    }
    if (channel == 'depth' && !selected) return MarketUpdate.ignored;
    if (channel == 'candles' &&
        (!selected ||
            asString(message['period'], fallback: asString(data['period'])) !=
                period)) {
      return MarketUpdate.ignored;
    }
    if (channel == 'trades' && !validTrade(data)) {
      onIssue?.call('最新成交的价格或数量无效，已忽略该条消息');
      return MarketUpdate.ignored;
    }
    final priceKey = key(instrument.mode, instrument.symbol);
    final stream = '$priceKey:$channel:${message['period'] ?? ''}';
    if (!acceptVersion(message, data, stream)) return MarketUpdate.ignored;
    if (channel == 'depth') {
      if (data['levels'] is List) {
        final levels = asList(data['levels']);
        if (levels.any(
          (raw) =>
              raw is! Map<String, dynamic> ||
              !const {'BUY', 'SELL'}.contains(raw['side']),
        )) {
          _recover(priceKey, instrument.symbol);
          return MarketUpdate.changed;
        }
        applyDepth(instrument.mode, instrument.symbol, {
          ...data,
          'updateType': 'SNAPSHOT',
          'bids': levels.where((raw) => asMap(raw)['side'] == 'BUY').toList(),
          'asks': levels.where((raw) => asMap(raw)['side'] == 'SELL').toList(),
        });
      } else {
        applyDepth(instrument.mode, instrument.symbol, data);
      }
    } else if (channel == 'trades' || channel == 'bookTicker') {
      if (channel == 'bookTicker') {
        bool validSide(Object? raw) {
          if (raw == null) return true;
          if (raw is! Map<String, dynamic>) return false;
          final ticks = parseInt64(raw['priceTicks']);
          if (ticks == null || ticks < 0) return false;
          for (final field in ['quantitySteps', 'orderCount']) {
            if (raw[field] != null && (parseInt64(raw[field]) ?? -1) < 0) {
              return false;
            }
          }
          return true;
        }

        if (!validSide(data['bid']) || !validSide(data['ask'])) {
          onIssue?.call('最优买卖价的整数单位无效');
          return MarketUpdate.ignored;
        }
      }
      final price = channel == 'bookTicker'
          ? midpoint(
              instrument,
              parseInt64(asMap(data['bid'])['priceTicks']),
              parseInt64(asMap(data['ask'])['priceTicks']),
            )
          : data['priceTicks'] != null
          ? instrument.priceFromTicks(
              requireInt64(data['priceTicks'], 'priceTicks'),
            )
          : requireFiniteDouble(data['price'], 'trade.price');
      if (price != null && price.isFinite && price > 0) {
        if (selected && channel == 'trades') {
          recentTrades = mergeRecentTrades(recentTrades, [data]);
        }
        latestPrices[priceKey] = price;
      }
    } else if (channel == 'mark') {
      final units = parseInt64(data['markPriceUnits']);
      final ticks = data['markPriceTicks'] != null
          ? parseInt64(data['markPriceTicks'])
          : data['markPriceUnits'] != null && instrument.priceTickUnits > 0
          ? (units == null ? null : units ~/ instrument.priceTickUnits)
          : instrument.priceTicksFromText(asString(data['markPrice']));
      if (ticks != null && ticks > 0) {
        metrics[priceKey] = {...?metrics[priceKey], ...data};
        markPrices[priceKey] = ticks;
      } else {
        markPrices.remove(priceKey);
        onIssue?.call('标记价格无效，估值等待恢复');
      }
      return MarketUpdate.markChanged;
    } else if (channel == 'index' || channel == 'funding') {
      for (final field in [
        'indexPriceTicks',
        'indexPriceUnits',
        'fundingRatePpm',
      ]) {
        if (data[field] != null && parseInt64(data[field]) == null) {
          onIssue?.call('行情指标的整数单位无效');
          return MarketUpdate.ignored;
        }
      }
      metrics[priceKey] = {...?metrics[priceKey], ...data};
    } else if (channel == 'candles') {
      final candle = Candle.fromJson(data);
      candles = [
        ...candles.where((old) => old.openTime != candle.openTime),
        candle,
      ]..sort((a, b) => a.openTime.compareTo(b.openTime));
      if (candles.length > 300) candles = candles.sublist(candles.length - 300);
    }
    return MarketUpdate.changed;
  }

  void applyDepth(
    ProductMode product,
    String symbol,
    Map<String, dynamic> data,
  ) {
    if (_closed) return;
    final recoveryKey = key(product, symbol);
    try {
      final sequence = requireInt64(
        data['sequence'] ?? data['lastSequence'] ?? data['eventSequence'],
        'depth.sequence',
      );
      if (sequence < 0) throw const FormatException('盘口序列无效');
      final updateType = data['updateType'] ?? 'SNAPSHOT';
      if (updateType != 'SNAPSHOT' && updateType != 'DELTA') {
        throw const FormatException('盘口更新类型无效');
      }
      final requestedDepth = data['depth'];
      var limit = 50;
      if (requestedDepth != null) {
        final depth = parseInt64(requestedDepth);
        if (depth == null || depth <= 0 || depth > 50) {
          throw const FormatException('盘口档数无效');
        }
        limit = depth;
      }
      final bids = _levels(data['bids'] ?? data['bidLevels']);
      final asks = _levels(data['asks'] ?? data['askLevels']);
      if (updateType == 'SNAPSHOT') {
        resetBook(
          OrderBook(
            symbol: symbol,
            sequence: sequence,
            bids: _merge(const [], bids, descending: true, limit: limit),
            asks: _merge(const [], asks, descending: false, limit: limit),
          ),
        );
        return;
      }
      if (_recovering == recoveryKey || sequence <= orderBook.sequence) return;
      final previous = parseInt64(data['previousSequence']);
      if (orderBook.symbol != symbol ||
          orderBook.sequence == 0 ||
          previous != orderBook.sequence) {
        _recover(recoveryKey, symbol);
        return;
      }
      orderBook = OrderBook(
        symbol: symbol,
        sequence: sequence,
        bids: _merge(orderBook.bids, bids, descending: true, limit: limit),
        asks: _merge(orderBook.asks, asks, descending: false, limit: limit),
      );
    } on FormatException {
      _recover(recoveryKey, symbol);
    }
  }

  List<OrderBookLevel> _levels(Object? values) {
    if (values is! List || values.length > 100) {
      throw const FormatException('盘口价档无效');
    }
    final seen = <int>{};
    return values.map((raw) {
      if (raw is! Map<String, dynamic>) throw const FormatException('盘口价档无效');
      final price = requireInt64(raw['priceTicks'], 'priceTicks');
      final quantity = requireInt64(
        raw['quantitySteps'] ?? raw['quantity'],
        'quantitySteps',
      );
      final count = raw['orderCount'] == null
          ? 0
          : requireInt64(raw['orderCount'], 'orderCount');
      if (!seen.add(price) || price <= 0 || quantity < 0 || count < 0) {
        throw const FormatException('盘口价档无效');
      }
      return OrderBookLevel(
        priceTicks: price,
        quantitySteps: quantity,
        orderCount: count,
      );
    }).toList();
  }

  List<OrderBookLevel> _merge(
    List<OrderBookLevel> current,
    List<OrderBookLevel> updates, {
    required bool descending,
    required int limit,
  }) {
    final byPrice = <int, OrderBookLevel>{
      for (final level in current) level.priceTicks: level,
    };
    for (final level in updates) {
      if (level.quantitySteps == 0) {
        byPrice.remove(level.priceTicks);
      } else {
        byPrice[level.priceTicks] = level;
      }
    }
    final sorted = byPrice.values.toList()
      ..sort(
        (a, b) => descending
            ? b.priceTicks.compareTo(a.priceTicks)
            : a.priceTicks.compareTo(b.priceTicks),
      );
    return sorted.take(limit).toList();
  }

  void _recover(String recoveryKey, String symbol) {
    if (_closed || _recovering == recoveryKey) return;
    resetBook(OrderBook.empty(symbol));
    _recovering = recoveryKey;
    onDepthUnavailable?.call();
    _requestSnapshot();
  }

  /// The subscribe operation already requested the first baseline.
  void awaitDepthSnapshot(ProductMode product, String symbol) {
    if (_closed || symbol.isEmpty) return;
    resetBook(OrderBook.empty(symbol));
    _recovering = key(product, symbol);
    _snapshotAttempts = 1;
    _scheduleSnapshotDeadline();
  }

  void _requestSnapshot() {
    if (_closed || _recovering == null) return;
    requestDepthSnapshot?.call();
    _snapshotAttempts++;
    _scheduleSnapshotDeadline();
  }

  void _scheduleSnapshotDeadline() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer(
      snapshotTimeout * (1 << (_snapshotAttempts - 1)),
      () {
        if (_closed || _recovering == null) return;
        if (_snapshotAttempts < maxSnapshotAttempts) {
          _requestSnapshot();
        } else {
          _snapshotTimer = null;
          reconnectDepth?.call();
        }
      },
    );
  }

  void dispose() {
    _closed = true;
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    requestDepthSnapshot = null;
    reconnectDepth = null;
    onDepthUnavailable = null;
    onIssue = null;
  }
}
