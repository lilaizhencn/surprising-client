import 'models.dart';

class _Entry {
  _Entry(this.version, this.value);
  final String version;
  final Map<String, dynamic>? value;
}

String positionKey(Map<String, dynamic> row) =>
    '${row['symbol']}:${row['positionSide'] ?? 'NET'}';

/// Absolute entity updates, including tombstones, fenced by periodic full snapshots.
class PrivateView {
  String status = 'INITIALIZING';
  String fence = '';
  DateTime? receivedAt;
  final _entities = <String, _Entry>{};
  static final _version = RegExp(r'^\d{19}:\d{10}$');

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
        status = asString(data['status']);
        return true;
      }
      final nextFence = asString(data['snapshotVersion']);
      if (!_version.hasMatch(nextFence) ||
          data['account'] == null ||
          nextFence.compareTo(fence) < 0) {
        return false;
      }
      if (nextFence != fence) {
        _entities.removeWhere((_, e) => e.version.compareTo(nextFence) <= 0);
        void put(String key, Map<String, dynamic> value) =>
            _entities.putIfAbsent(key, () => _Entry(nextFence, value));
        final account = asMap(data['account']);
        put('metadata', {'positionMode': account['positionMode']});
        for (final raw in asList(account['balances'])) {
          final v = asMap(raw);
          put('balance:${v['asset']}', v);
        }
        for (final raw in asList(account['positions'])) {
          final v = asMap(raw);
          put('position:${positionKey(v)}', v);
        }
        for (final raw in asList(data['openOrders'])) {
          final v = asMap(raw);
          put('order:${v['orderId']}', v);
        }
        for (final raw in asList(data['triggerOrders'])) {
          final v = asMap(raw);
          put('trigger:${v['triggerOrderId']}', v);
        }
        for (final raw in asList(data['positionRisks'])) {
          final v = asMap(raw);
          put('risk:${positionKey(v)}', v);
        }
        fence = nextFence;
      }
      status = 'READY';
      receivedAt = DateTime.now();
      return true;
    }
    final version = asString(data['version']);
    if (message['op'] != 'event' ||
        !_version.hasMatch(version) ||
        version.compareTo(fence) <= 0) {
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
        if (data['entityId'] == 'user') {
          put('metadata', {'positionMode': value['positionMode']});
        }
        for (final raw in asList(value['balances'])) {
          final v = asMap(raw);
          put('balance:${v['asset']}', v);
        }
      case 'positions':
        for (final raw in asList(value['positions'])) {
          final v = asMap(raw), key = positionKey(v);
          put('position:$key', asInt(v['signedQuantitySteps']) == 0 ? null : v);
          if (asInt(v['signedQuantitySteps']) == 0) put('risk:$key', null);
        }
      case 'orders':
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

({int pnl, int value})? positionValuation(
  Map<String, dynamic> p,
  Instrument instrument,
  int mark,
) {
  if (mark <= 0 ||
      instrument.notionalMultiplierUnits == null ||
      asInt(p['entryPriceTicks']) <= 0) {
    return null;
  }
  final q = BigInt.from(asInt(p['signedQuantitySteps']));
  final entry = BigInt.from(asInt(p['entryPriceTicks']));
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
