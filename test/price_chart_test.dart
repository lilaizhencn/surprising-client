import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/price_chart.dart';

Candle candle(int second, {double close = 12, double volume = 3}) => Candle(
  openTime: DateTime.fromMillisecondsSinceEpoch(second * 1000, isUtc: true),
  open: 10,
  high: 15,
  low: 8,
  close: close,
  volume: volume,
);

void main() {
  test(
    'matches Web gap and current bucket bars without inventing trading volume',
    () {
      final bars = chartCandles(
        [candle(60), candle(240, close: 13)],
        period: '1m',
        now: DateTime.fromMillisecondsSinceEpoch(450000, isUtc: true),
      );
      expect(bars.map((bar) => bar['time']), [
        60,
        120,
        180,
        240,
        300,
        360,
        420,
      ]);
      expect(bars[1], {
        'time': 120,
        'open': 12.0,
        'high': 12.0,
        'low': 12.0,
        'close': 12.0,
        'volume': 0,
      });
      expect(bars[3]['volume'], 3);
      expect(bars.last, {
        'time': 420,
        'open': 13.0,
        'high': 13.0,
        'low': 13.0,
        'close': 13.0,
        'volume': 0,
      });
    },
  );

  test(
    'a long inactive interval is bounded and an empty market stays empty',
    () {
      final now = DateTime.fromMillisecondsSinceEpoch(1000000000, isUtc: true);
      final bars = chartCandles([candle(60)], period: '1m', now: now);
      expect(bars, hasLength(120));
      expect(bars.first['time'], 992820);
      expect(bars.last['time'], 999960);
      expect(
        bars.every((bar) => bar['volume'] == 0 && bar['close'] == 12),
        isTrue,
      );
      expect(chartCandles([], period: '1m', now: now), isEmpty);
    },
  );

  test(
    'sorts timestamps in seconds and replaces repeated bars without changing OHLC prices',
    () {
      final prepared = chartCandles([
        candle(300),
        candle(100),
        candle(200),
        candle(300, close: 13),
      ]);
      expect(prepared.map((bar) => bar['time']), [100, 200, 300]);
      expect(prepared.last, {
        'time': 300,
        'open': 10.0,
        'high': 15.0,
        'low': 8.0,
        'close': 13.0,
        'volume': 3.0,
      });
    },
  );

  test(
    'invalid price bars never reach the chart and malformed volume is not rendered as NaN',
    () {
      final prepared = chartCandles([
        candle(100, close: double.nan),
        candle(200, close: 18),
        candle(300, close: -1),
        candle(400, volume: double.nan),
      ]);
      expect(prepared, hasLength(1));
      expect(prepared.single['time'], 400);
      expect(prepared.single['volume'], 0);
    },
  );

  test('bounds the rendered window to the latest 120 bars', () {
    final prepared = chartCandles([
      for (var i = 1; i <= 150; i++) candle(i * 60),
    ]);
    expect(prepared, hasLength(120));
    expect(prepared.first['time'], 31 * 60);
    expect(prepared.last['time'], 150 * 60);
  });
}
