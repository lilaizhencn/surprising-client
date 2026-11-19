import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kline_chart/kline_chart.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/price_chart.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

Instrument chartInstrument({int precision = 8, String symbol = 'SMALL-USDT'}) =>
    Instrument(
      instrumentId: symbol,
      symbol: symbol,
      instrumentType: 'PERPETUAL',
      contractType: 'LINEAR_PERPETUAL',
      baseAsset: symbol.split('-').first,
      quoteAsset: 'USDT',
      settleAsset: 'USDT',
      priceTickUnits: 1,
      quantityStepUnits: 1,
      pricePrecision: precision,
      quantityPrecision: 6,
      maxLeveragePpm: 1000000,
      status: 'TRADING',
    );

// Explicit synthetic OHLC, never network or account data.
// Fixed future times keep the live clock from adding buckets during a test;
// real current-bucket/gap behavior is covered by price_chart_test.dart.
List<Candle> chartFixture({int length = 80, int minutes = 1}) {
  final interval = minutes * 60000;
  final bucket =
      DateTime.utc(2100, 1, 1, 12).millisecondsSinceEpoch ~/
      interval *
      interval;
  return [
    for (var i = 0; i < length; i++)
      Candle(
        openTime: DateTime.fromMillisecondsSinceEpoch(
          bucket - (length - i - 1) * interval,
          isUtc: true,
        ),
        open: .00001 + math.sin(i * .3) * .000001,
        high: .0000105 + math.sin(i * .3) * .000001,
        low: .0000095 + math.sin(i * .3) * .000001,
        close:
            .00001 + math.sin(i * .3) * .000001 + math.sin(i * .7) * .0000003,
        volume: 3000 + i * 17,
      ),
  ];
}

Candle revise(Candle c, {double? close, DateTime? time}) => Candle(
  openTime: time ?? c.openTime,
  open: c.open,
  high: c.high,
  low: c.low,
  close: close ?? c.close,
  volume: c.volume + 1,
);

Future<void> showChart(
  WidgetTester tester,
  List<Candle> candles, {
  String period = '1m',
  Instrument? instrument,
  ClientTheme theme = ClientTheme.dark,
  double scale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildClientTheme(theme),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: NativePriceChart(
          candles: candles,
          period: period,
          instrument: instrument ?? chartInstrument(),
        ),
      ),
    ),
  ),
);

KLineController nativeController(WidgetTester tester) =>
    tester.widget<KLineView>(find.byType(KLineView)).controller;

void main() {
  testWidgets(
    'uses original native MA/VOL/MACD with instrument precision and milliseconds',
    (tester) async {
      final candles = chartFixture();
      await showChart(tester, [candles.last, ...candles, candles.last]);
      await tester.pumpAndSettle();
      final controller = nativeController(tester);
      expect(controller.showMainIndicators, [IndicatorType.ma]);
      expect(controller.showSubIndicators, [
        IndicatorType.vol,
        IndicatorType.macd,
      ]);
      expect(controller.itemCount, 38);
      expect(controller.minCount, 12);
      expect(controller.maxCount, 90);
      expect(controller.data.length, candles.length);
      expect(controller.data.last.time, candles.last.timeMillis);
      expect(controller.formatPrice(.00001234), '0.00001234');
      expect(controller.formatPrice(12345.67890123), '12345.67890123');
      expect(controller.formatVolume(.000123), '0.000123');
      expect(controller.formatVolume(1000), '1000');
      expect(
        controller.formatIndicator(.00001234, IndicatorType.ma),
        '0.00001234',
      );
      expect(find.text('VOL · SMALL'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'last-bar revisions and new bars preserve zoom; identical clock ticks do no data work',
    (tester) async {
      final candles = chartFixture(length: 40);
      await showChart(tester, candles);
      await tester.pumpAndSettle();
      final controller = nativeController(tester)..itemCount = 24;
      final revised = [...candles]
        ..[candles.length - 1] = revise(candles.last, close: candles.last.open);
      await showChart(tester, revised);
      expect(controller.lastDataChange!.type, KLineDataChangeType.updateLast);
      expect(controller.itemCount, 24);
      expect(controller.data.last.close, revised.last.close);
      final version = controller.dataVersion;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.dataVersion, version);
      // Synthetic next minute: exercises append without any market/network writes.
      final next = revise(
        revised.last,
        time: revised.last.openTime.add(const Duration(minutes: 1)),
      );
      await showChart(tester, [...revised, next]);
      await tester.pumpAndSettle();
      expect(controller.lastDataChange!.type, KLineDataChangeType.append);
      expect(controller.data.last.time, next.timeMillis);
      expect(controller.itemCount, 24);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'period and symbol changes reset viewport and clear old crosshair/data',
    (tester) async {
      await showChart(tester, chartFixture());
      await tester.pumpAndSettle();
      final controller = nativeController(tester)..itemCount = 18;
      controller.longPressOffset.update(const Offset(20, 20));
      final changed = chartFixture(length: 35, minutes: 5);
      await showChart(
        tester,
        changed,
        period: '5m',
        instrument: chartInstrument(precision: 12, symbol: 'OTHER-USDT'),
      );
      await tester.pumpAndSettle();
      expect(controller.itemCount, 38);
      expect(controller.longPressOffset.value, Offset.zero);
      expect(controller.lastDataChange!.resetView, isTrue);
      expect(controller.data.length, changed.length);
      expect(controller.data.first.time, changed.first.timeMillis);
      expect(controller.formatPrice(.000000000123), '0.000000000123');
      expect(find.text('VOL · OTHER'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty/invalid and flat zero-volume data render without a platform WebView',
    (tester) async {
      await showChart(tester, []);
      await tester.pumpAndSettle();
      expect(find.text('暂无 K 线数据'), findsOneWidget);
      expect(find.byType(KLineView), findsNothing);
      final candle = chartFixture(length: 1).single;
      await showChart(tester, [
        Candle(
          openTime: candle.openTime,
          open: 1,
          high: 1,
          low: 1,
          close: double.nan,
          volume: 0,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(KLineView), findsNothing);
      await showChart(tester, [
        Candle(
          openTime: candle.openTime,
          open: .00000001,
          high: .00000001,
          low: .00000001,
          close: .00000001,
          volume: 0,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(KLineView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '320px high-precision chart adapts all themes and supports native pinch/long press',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final candles = chartFixture();
      for (final theme in ClientTheme.values) {
        await showChart(
          tester,
          candles,
          theme: theme,
          scale: 1.3,
          instrument: chartInstrument(precision: 12),
        );
        await tester.pumpAndSettle();
        final controller = nativeController(tester);
        expect(
          controller.chartStyle.backgroundColor,
          clientColorScheme(theme).surface,
        );
        expect(
          controller.candleStyle.riseColor,
          clientColorScheme(theme).tertiary,
        );
        expect(controller.formatPrice(.000000000123), '0.000000000123');
        expect(tester.takeException(), isNull, reason: theme.name);
      }
      final center = tester.getCenter(find.byType(KLineView));
      final first = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await tester.pump();
      for (var offset = 35.0; offset <= 90; offset += 5) {
        await second.moveTo(center + Offset(offset, 0));
        await first.moveTo(center - Offset(offset, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(nativeController(tester).itemCount, inInclusiveRange(12, 90));
      expect(nativeController(tester).itemCount, isNot(38));
      await tester.longPressAt(center);
      await tester.pump();
      expect(
        nativeController(tester).longPressOffset.value,
        isNot(Offset.zero),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('native 320px dark/light visual regression uses synthetic data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final theme in [ClientTheme.dark, ClientTheme.light]) {
      await showChart(tester, chartFixture(), theme: theme);
      await tester.pumpAndSettle();
      final controller = nativeController(tester);
      // Golden-only UTC formatter avoids machine-timezone differences.
      controller.timeFormatter = (time, granularity) =>
          '${time.toUtc().hour.toString().padLeft(2, '0')}:${time.toUtc().minute.toString().padLeft(2, '0')}';
      controller.setData(controller.data, resetView: false);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(NativePriceChart),
        matchesGoldenFile('goldens/native_kline_320_${theme.name}.png'),
      );
      await tester.pumpWidget(const SizedBox());
    }
  });
}
