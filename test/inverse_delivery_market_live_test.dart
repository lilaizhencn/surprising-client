import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final rootPath = Platform.environment['INVERSE_MARKET_LIVE_ROOT'];
  test(
    'inverse delivery market replay retains committed fills and actual base volume',
    () async {
      expect(rootPath, startsWith('/tmp/surprising-inverse-delivery-fused-'));
      final root = Directory(rootPath!);
      final expected = asMap(
        jsonDecode(
          await File('${root.path}/market-expected.json').readAsString(),
        ),
      );
      final ownership = asMap(
        jsonDecode(
          await File(
            '${root.path}/initial-runtime-ownership.json',
          ).readAsString(),
        ),
      );
      final corePid = asInt(asMap(ownership['pids'])['core-node0']);
      expect(
        (await Process.run('ps', ['-p', '$corePid', '-o', 'args='])).stdout,
        contains(
          '-Dsurprising.launcher.identity=${ownership['runId']}/core-node0',
        ),
      );
      final http = HttpClient();
      final api = ApiClient(
        const AppConfig(gatewayBaseUrl: 'http://127.0.0.1:9094'),
        httpClient: http,
      );
      var paused = false;
      try {
        final instrument = await api.instrumentLatest(
          asString(expected['instrumentId']),
          ProductMode.inverseDelivery,
        );
        api.instrumentCatalog = [instrument];
        expect(instrument.status, 'SETTLING');
        expect(instrument.settleAsset, 'BTC');
        expect(Process.killPid(corePid, ProcessSignal.sigstop), true);
        paused = true;
        final trades = await api.recentTrades(
          instrument.symbol,
          productLine: 'INVERSE_DELIVERY',
        );
        expect(
          trades.map((r) => asString(r['tradeId'])).toSet(),
          asList(
            expected['trades'],
          ).map((r) => asString(asMap(r)['tradeId'])).toSet(),
        );
        final face = double.parse(asString(expected['quoteFacePerContract']));
        for (final row in trades) {
          expect(
            asDouble(row['quantity']),
            closeTo(
              asInt(row['quantitySteps']) * face / asDouble(row['price']),
              1e-15,
            ),
          );
        }
        final candles = await api.candles(
          instrument.symbol,
          '1m',
          productLine: 'INVERSE_DELIVERY',
        );
        expect(
          candles.fold<double>(0, (sum, c) => sum + c.volume),
          closeTo(
            double.parse(asString(expected['expectedBaseVolume'])),
            1e-15,
          ),
        );
        final higher = await api.candles(
          instrument.symbol,
          '4h',
          productLine: 'INVERSE_DELIVERY',
        );
        expect(
          higher.fold<double>(0, (sum, c) => sum + c.volume),
          closeTo(
            double.parse(asString(expected['expectedBaseVolume'])),
            1e-15,
          ),
        );
        final end = DateTime.now().toUtc();
        final raw = await api.get(
          '/api/v1/gateway/candlestick/candles',
          productLine: 'INVERSE_DELIVERY',
          query: {
            'instrumentId': instrument.instrumentId,
            'period': '1m',
            'limit': '300',
            'startTime': end
                .subtract(const Duration(hours: 5))
                .toIso8601String(),
            'endTime': end.toIso8601String(),
          },
        );
        final rows = asList(raw['candles']).map(asMap).toList();
        expect(rows.fold<int>(0, (sum, c) => sum + asInt(c['tradeCount'])), 3);
        expect(
          rows.fold<double>(0, (sum, c) => sum + asDouble(c['quoteVolume'])),
          closeTo(4000, 1e-8),
        );
        await File(
          '${root.path}/market-replay-client-evidence.json',
        ).writeAsString(
          jsonEncode({
            'productLine': 'INVERSE_DELIVERY',
            'instrumentId': instrument.instrumentId,
            'settlementAsset': instrument.settleAsset,
            'tradeCount': trades.length,
            'baseVolume': candles.fold<double>(0, (sum, c) => sum + c.volume),
            'quoteVolume': rows.fold<double>(
              0,
              (sum, c) => sum + asDouble(c['quoteVolume']),
            ),
            'corePausedReads': true,
            'typedCandleMapping': true,
            'coldHigherPeriod': '4h',
          }),
        );
      } finally {
        if (paused) Process.killPid(corePid, ProcessSignal.sigcont);
        http.close(force: true);
      }
    },
    skip: rootPath == null,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
