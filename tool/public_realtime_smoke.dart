// Read-only deployment check: dart run tool/public_realtime_smoke.dart
import 'dart:io';

import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

Future<void> main() async {
  final http = HttpClient();
  final api = ApiClient(const AppConfig(), httpClient: http);
  final ws = RealtimeClient(const AppConfig());
  final events = <Map<String, dynamic>>[];
  final failures = <Object>[];
  var installed = <String>{};
  List<Map<String, String>> subscriptions(Instrument i, String period) => [
    for (final channel in [
      'depth',
      'trades',
      'mark',
      'index',
      'funding',
      'candles',
    ])
      {
        'channel': channel,
        'productLine': i.mode.productLine,
        'instrumentId': i.instrumentId,
        if (channel == 'candles') 'period': period,
      },
  ];
  String key(Map<String, dynamic> s) =>
      '${s['productLine']}:${s['channel']}:${s['instrumentId']}:${s['period'] ?? ''}';
  Future<void> verify(
    Instrument instrument,
    String period,
    String label,
  ) async {
    events.clear();
    final requested = subscriptions(instrument, period);
    final desired = requested.map(key).toSet();
    final added = desired.difference(installed);
    final removed = installed.difference(desired);
    ws.replaceSubscriptions(requested);
    await Future<void>.delayed(const Duration(seconds: 8));
    final subscribed = events
        .where((e) => e['op'] == 'subscribed')
        .map(key)
        .toSet();
    final unsubscribed = events
        .where((e) => e['op'] == 'unsubscribed')
        .map(key)
        .toSet();
    final errors = events.where((e) => e['op'] == 'error');
    final observed = <String, int>{};
    final retired = <String>{};
    for (final event in events) {
      final id = key(event);
      if (event['op'] == 'unsubscribed') retired.add(id);
      if (event['op'] != 'event') continue;
      // Messages already in flight before the unsubscribe ACK are expected.
      if (retired.contains(id)) {
        throw StateError('Event after unsubscribe ACK: $id');
      }
      observed[id] = (observed[id] ?? 0) + 1;
    }
    if (errors.isNotEmpty ||
        failures.isNotEmpty ||
        !subscribed.containsAll(added) ||
        !unsubscribed.containsAll(removed)) {
      throw StateError(
        '$label: missing ACK or stream error: $errors $failures',
      );
    }
    final depth = key(requested.first);
    if ((observed[depth] ?? 0) == 0) {
      throw StateError('$label: no depth update');
    }
    stdout.writeln(
      '$label subscribe=${subscribed.length} unsubscribe=${unsubscribed.length} events=$observed',
    );
    installed = desired;
  }

  try {
    final instruments = await api.instruments();
    stdout.writeln(
      'Products: ${{for (final p in ProductMode.values) p.productLine: instruments.where((i) => i.mode == p).length}}',
    );
    final perpetuals = instruments
        .where((i) => i.mode == ProductMode.linear)
        .toList();
    if (perpetuals.isEmpty) {
      throw StateError('No active linear perpetual instruments');
    }
    for (final i in perpetuals) {
      final book = await api.orderBook(
        i.symbol,
        productLine: i.mode.productLine,
      );
      final candles = await api.candles(
        i.symbol,
        '4h',
        productLine: i.mode.productLine,
      );
      final trades = await api.recentTrades(
        i.symbol,
        productLine: i.mode.productLine,
      );
      stdout.writeln(
        'REST ${i.symbol} id=${i.instrumentId} book=${book.bids.length}/${book.asks.length} candles=${candles.length} trades=${trades.length}',
      );
      if (book.bids.isEmpty ||
          book.asks.isEmpty ||
          candles.isEmpty ||
          trades.isEmpty) {
        throw StateError('${i.symbol}: empty active market response');
      }
    }
    await ws.connect(onEvent: events.add, onError: failures.add);
    for (final instrument in perpetuals) {
      await verify(instrument, '1m', 'SWITCH ${instrument.symbol}');
    }
    await verify(perpetuals.last, '5m', 'PERIOD 5m');
    await ws.close();
    await ws.connect(onEvent: events.add, onError: failures.add);
    installed = {};
    await verify(perpetuals.last, '5m', 'RECONNECT');
    stdout.writeln(
      'PASS: public REST, instrument/period switches, unsubscribe ACKs and reconnect. Private account data was not tested.',
    );
  } finally {
    await ws.close();
    http.close(force: true);
  }
}
