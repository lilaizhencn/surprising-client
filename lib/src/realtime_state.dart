import 'models.dart';

class _Entry {
  _Entry(this.version, this.value);
  final String version;
  final Map<String, dynamic>? value;
}

String positionKey(Map<String, dynamic> row) =>
    '${row['instrumentId'] ?? row['symbol']}:${row['positionSide'] ?? 'NET'}';

/// Absolute entity updates, including tombstones, fenced by periodic full snapshots.
class PrivateView {
  String status = 'INITIALIZING';
  String fence = '';
  DateTime? receivedAt;
  final _entities = <String, _Entry>{};
  final _orderUpdates = <String, _Entry>{};
  List<Map<String, dynamic>> get orderUpdates =>
      _orderUpdates.values.toList().reversed.map((e) => e.value!).toList();
  static final _version = RegExp(r'^\d{19}:\d{10}$');
  static bool _validVersion(String value) =>
      _version.hasMatch(value) &&
      value.substring(0, 19).compareTo('9223372036854775807') <= 0 &&
      value.substring(20).compareTo('2147483647') <= 0;

  bool get ready =>
      status == 'READY' &&
      receivedAt != null &&
      DateTime.now().difference(receivedAt!).inSeconds < 15;
  String get positionMode => asString(
    _entities['metadata']?.value?['positionMode'],
    fallback: 'ONE_WAY',
  );
  List<Map<String, dynamic>> rows(String kind) => _entities.entries
      .where((e) => e.key.startsWith('$kind:') && e.value.value != null)
      .map((e) => e.value.value!)
      .toList();

  bool apply(Map<String, dynamic> message) {
    final data = asMap(message['data']);
    if (message['op'] == 'snapshot') {
      if (data['status'] != 'READY') {
        status = data['status'] == 'INITIALIZING' ? 'INITIALIZING' : 'STALE';
        return true;
      }
      final nextFence = asString(data['snapshotVersion']);
      if (!_validVersion(nextFence)) {
        status = 'STALE';
        return false;
      }
      if (nextFence.compareTo(fence) < 0) return false;
      final snapshot = _validatedSnapshot(data, message);
      if (snapshot == null) {
        status = 'STALE';
        return false;
      }
      if (nextFence != fence) {
        // Validate the entire replacement first; retain later events and tombstones.
        final replacement = <String, _Entry>{
          for (final entry in _entities.entries)
            if (entry.value.version.compareTo(nextFence) > 0)
              entry.key: entry.value,
        };
        for (final entry in snapshot.entries) {
          replacement.putIfAbsent(
            entry.key,
            () => _Entry(nextFence, entry.value),
          );
        }
        _entities
          ..clear()
          ..addAll(replacement);
        fence = nextFence;
      }
      status = 'READY';
      receivedAt = DateTime.now();
      return true;
    }
    final version = asString(data['version']);
    if (message['op'] != 'event') return false;
    if (!_validVersion(version)) {
      status = 'STALE';
      return false;
    }
    if (version.compareTo(fence) <= 0) return false;
    if (!_validEvent(message)) {
      status = 'STALE';
      return false;
    }
    void put(String key, Map<String, dynamic>? value) {
      if (version.compareTo(_entities[key]?.version ?? '') > 0) {
        _entities[key] = _Entry(version, value);
      }
    }

    final value = asMap(data['value']);
    switch (message['channel']) {
      case 'accountState':
        if (data['entityId'] == 'user' && value['positionMode'] != null) {
          put('metadata', {'positionMode': value['positionMode']});
        }
        for (final raw in asList(value['balances'])) {
          final v = asMap(raw);
          put('balance:${v['asset']}', v);
        }
        for (final raw in asList(value['leverages'])) {
          final v = asMap(raw);
          put('leverage:${v['instrumentId']}:${v['marginMode']}', v);
        }
      case 'positions':
        for (final raw in asList(value['positions'])) {
          final v = asMap(raw), key = positionKey(v);
          put(
            'position:$key',
            parseInt64(v['signedQuantitySteps']) == 0 ? null : v,
          );
          if (parseInt64(v['signedQuantitySteps']) == 0) put('risk:$key', null);
        }
      case 'orders':
        final orderId = asString(value['orderId']);
        if (version.compareTo(_entities['order:$orderId']?.version ?? '') > 0 &&
            version.compareTo(_orderUpdates[orderId]?.version ?? '') > 0) {
          _orderUpdates.remove(orderId);
          _orderUpdates[orderId] = _Entry(version, value);
          if (_orderUpdates.length > 100) {
            _orderUpdates.remove(_orderUpdates.keys.first);
          }
        }
        put(
          'order:${value['orderId']}',
          value['status'] == 'OPEN' ? value : null,
        );
      case 'triggerOrders':
        for (final raw in asList(data['value'])) {
          final v = asMap(raw);
          put(
            'trigger:${v['triggerOrderId']}',
            ['PENDING', 'TRIGGERING'].contains(v['status']) ? v : null,
          );
        }
      case 'positionRisk':
      case 'accountRisk':
        put('risk:${positionKey(value)}', value);
      default:
        return false;
    }
    if (_entities.length > 20000) {
      _entities.clear();
      fence = '';
      status = 'STALE';
    }
    return true;
  }
}

Map<String, Map<String, dynamic>>? _validatedSnapshot(
  Map<String, dynamic> data,
  Map<String, dynamic> message,
) {
  try {
    final account = _requireMap(data['account']);
    if (account.containsKey('revision')) {
      requireInt64(account['revision'], 'revision');
    }
    final mode = account['positionMode'];
    if (!['ONE_WAY', 'HEDGE'].contains(mode)) {
      throw const FormatException('positionMode');
    }
    if (account['productLine'] != null &&
        account['productLine'] != message['productLine']) {
      throw const FormatException('productLine');
    }
    if (account['userId'] != null &&
        (parseInt64(account['userId']) == null ||
            parseInt64(account['userId']) != parseInt64(message['userId']))) {
      throw const FormatException('userId');
    }
    final result = <String, Map<String, dynamic>>{
      'metadata': {'positionMode': mode},
    };
    var entityCount = 0;
    void collect(String kind, Object? raw, {bool retain = true}) {
      if (raw is! List || raw.length > 20000) throw FormatException(kind);
      final seen = <String>{};
      for (final item in raw) {
        final row = _requireMap(item);
        _validateIdentity(row, message);
        final key = _validateRow(kind, row);
        if (!seen.add(key)) throw FormatException('duplicate $kind');
        if (++entityCount > 20000) {
          throw const FormatException('snapshot too large');
        }
        if (retain) result[key] = Map<String, dynamic>.unmodifiable(row);
      }
    }

    collect('balance', account['balances']);
    // Reservations are validated for completeness; this UI does not project them.
    collect('reservation', account['reservations'], retain: false);
    collect('position', account['positions']);
    collect('leverage', account['leverages']);
    collect('order', data['openOrders']);
    collect('trigger', data['triggerOrders']);
    collect('risk', data['positionRisks']);
    return result;
  } on FormatException {
    return null;
  }
}

bool _validEvent(Map<String, dynamic> message) {
  try {
    final data = _requireMap(message['data']);
    final raw = data['value'];
    void rows(String kind, Object? source) {
      if (source is! List || source.length > 20000) throw FormatException(kind);
      final seen = <String>{};
      for (final raw in source) {
        final row = _requireMap(raw);
        _validateIdentity(row, message);
        final key = _validateRow(kind, row, snapshot: false);
        if (!seen.add(key)) throw FormatException('duplicate $kind');
      }
    }

    switch (message['channel']) {
      case 'accountState':
        final value = _requireMap(raw);
        if (value.containsKey('positionMode') &&
            !['ONE_WAY', 'HEDGE'].contains(value['positionMode'])) {
          throw const FormatException('positionMode');
        }
        if (value.containsKey('balances')) rows('balance', value['balances']);
        if (value.containsKey('leverages')) {
          rows('leverage', value['leverages']);
        }
        if (value.containsKey('reservations')) {
          rows('reservation', value['reservations']);
        }
      case 'positions':
        rows('position', _requireMap(raw)['positions']);
      case 'orders':
        _validateIdentity(_requireMap(raw), message);
        _validateRow('order', _requireMap(raw), snapshot: false);
      case 'triggerOrders':
        rows('trigger', raw);
      case 'positionRisk':
      case 'accountRisk':
        _validateIdentity(_requireMap(raw), message);
        _validateRow('risk', _requireMap(raw), snapshot: false);
      default:
        return false;
    }
    return true;
  } on FormatException {
    return false;
  }
}

Map<String, dynamic> _requireMap(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('expected object');
  }
  return raw;
}

void _validateIdentity(Map<String, dynamic> row, Map<String, dynamic> message) {
  if (row['productLine'] != null &&
      row['productLine'] != message['productLine']) {
    throw const FormatException('productLine');
  }
  if (row['userId'] != null &&
      (parseInt64(row['userId']) == null ||
          parseInt64(row['userId']) != parseInt64(message['userId']))) {
    throw const FormatException('userId');
  }
}

String _validateRow(
  String kind,
  Map<String, dynamic> row, {
  bool snapshot = true,
}) {
  String text(String field) => requireString(row[field], field);
  void integers(List<String> fields) {
    for (final field in fields) {
      requireInt64(row[field], field);
    }
  }

  void choice(String field, List<String> values) {
    if (!values.contains(row[field])) throw FormatException(field);
  }

  String instrument() => text('instrumentId');
  String position() {
    choice('positionSide', ['NET', 'LONG', 'SHORT']);
    return '${instrument()}:${row['positionSide']}';
  }

  String id(String field) {
    final value = requireInt64(row[field], field);
    if (value <= 0) throw FormatException(field);
    return '$value';
  }

  for (final field in [
    'userId',
    'revision',
    'makerFeeRatePpm',
    'takerFeeRatePpm',
    'createdAtEpochMillis',
    'updatedAtEpochMillis',
    'clusterPosition',
    'executedValueHigh',
    'executedValueLow',
    'activatedAtEpochMillis',
    'placedOrderId',
    'triggerSequence',
    'triggeredPriceTicks',
    'expiresAtEpochMillis',
    'triggeredAtEpochMillis',
  ]) {
    if (row.containsKey(field)) requireInt64(row[field], field);
  }
  switch (kind) {
    case 'balance':
      integers(['availableUnits', 'lockedUnits']);
      return 'balance:${text('asset')}';
    case 'reservation':
      instrument();
      text('asset');
      choice('kind', ['SPOT_ASSET', 'DERIVATIVE_MARGIN']);
      integers([
        'reservedUnits',
        'releasedUnits',
        'consumedUnits',
        'orderQuantitySteps',
      ]);
      return 'reservation:${id('orderId')}';
    case 'position':
      final key = position();
      text('marginAsset');
      choice('marginMode', ['CROSS', 'ISOLATED']);
      integers([
        'signedQuantitySteps',
        'entryPriceTicks',
        'entryValueTicks',
        'realizedPnlUnits',
        'positionMarginUnits',
      ]);
      return 'position:$key';
    case 'leverage':
      final key = instrument();
      choice('marginMode', ['CROSS', 'ISOLATED']);
      integers(['leveragePpm']);
      if (requireInt64(row['leveragePpm'], 'leveragePpm') <= 0) {
        throw const FormatException('leveragePpm');
      }
      return 'leverage:$key:${row['marginMode']}';
    case 'order':
      instrument();
      choice(
        'status',
        snapshot ? ['OPEN'] : ['OPEN', 'FILLED', 'CANCELED', 'REJECTED'],
      );
      choice('side', ['BUY', 'SELL']);
      choice('marginMode', ['CROSS', 'ISOLATED']);
      choice('positionSide', ['NET', 'LONG', 'SHORT']);
      choice('orderType', ['LIMIT', 'MARKET']);
      choice('timeInForce', ['GTC', 'IOC', 'FOK', 'GTX']);
      integers([
        'priceTicks',
        'quantitySteps',
        'executedQuantitySteps',
        'remainingQuantitySteps',
        'cumulativeFeeUnits',
      ]);
      return 'order:${id('orderId')}';
    case 'trigger':
      instrument();
      id('userId');
      if (row.containsKey('priceSource')) {
        choice('priceSource', ['MARK', 'LAST', 'INDEX']);
      }
      if (row.containsKey('triggerCondition')) {
        choice('triggerCondition', ['GREATER_OR_EQUAL', 'LESS_OR_EQUAL']);
      }
      choice(
        'status',
        snapshot
            ? ['PENDING', 'TRIGGERING']
            : [
                'PENDING',
                'TRIGGERING',
                'TRIGGERED',
                'TRIGGER_FAILED',
                'CANCELED',
                'EXPIRED',
              ],
      );
      choice('side', ['BUY', 'SELL']);
      choice('marginMode', ['CROSS', 'ISOLATED']);
      choice('positionSide', ['NET', 'LONG', 'SHORT']);
      choice('orderType', ['LIMIT', 'MARKET']);
      choice('timeInForce', ['GTC', 'IOC', 'FOK', 'GTX']);
      choice('triggerType', ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP']);
      integers([
        'triggerPriceTicks',
        'activationPriceTicks',
        'callbackRatePpm',
        'highestPriceTicks',
        'lowestPriceTicks',
        'priceTicks',
        'quantitySteps',
      ]);
      return 'trigger:${id('triggerOrderId')}';
    case 'risk':
      final key = position();
      choice('status', ['NORMAL', 'WARNING', 'LIQUIDATION']);
      integers([
        'equityUnits',
        'unrealizedPnlUnits',
        'maintenanceMarginUnits',
        'marginRatioPpm',
      ]);
      return 'risk:$key';
    default:
      throw FormatException(kind);
  }
}

({int pnl, int value})? positionValuation(
  Map<String, dynamic> p,
  Instrument instrument,
  int mark,
) {
  if (mark <= 0 ||
      instrument.notionalMultiplierUnits == null ||
      instrument.notionalMultiplierUnits! <= 0 ||
      (parseInt64(p['entryPriceTicks']) ?? 0) <= 0 ||
      parseInt64(p['signedQuantitySteps']) == null) {
    return null;
  }
  final q = BigInt.from(parseInt64(p['signedQuantitySteps'])!);
  final entry = BigInt.from(parseInt64(p['entryPriceTicks'])!);
  final multiplier = BigInt.from(instrument.notionalMultiplierUnits!);
  var pnl = q * (BigInt.from(mark) - entry) * multiplier;
  if (instrument.mode == ProductMode.inverse ||
      instrument.mode == ProductMode.inverseDelivery) {
    if (instrument.settleScaleUnits == null || instrument.priceTickUnits <= 0) {
      return null;
    }
    final numerator = pnl * BigInt.from(instrument.settleScaleUnits!);
    final denominator =
        entry * BigInt.from(mark) * BigInt.from(instrument.priceTickUnits);
    final abs = numerator.abs();
    pnl =
        (abs ~/ denominator +
            (abs.remainder(denominator) * BigInt.two >= denominator
                ? BigInt.one
                : BigInt.zero)) *
        BigInt.from(numerator.sign);
  }
  final value = instrument.isOption ? q * BigInt.from(mark) * multiplier : pnl;
  if (pnl.bitLength > 63 || value.bitLength > 63) return null;
  return (pnl: pnl.toInt(), value: value.toInt());
}
