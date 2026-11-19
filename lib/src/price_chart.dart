import 'dart:async';
import 'dart:math' as math;

import 'package:kline_chart/kline_chart.dart';
import 'package:material_ui/material_ui.dart';

import 'i18n/client_messages.dart';
import 'models.dart';

/// Validated, bounded OHLC bars; times are seconds until the native adapter.
List<Map<String, Object>> chartCandles(
  List<Candle> candles, {
  String? period,
  DateTime? now,
}) {
  final bySecond = <int, Candle>{};
  for (final candle in candles) {
    if (![
          candle.open,
          candle.high,
          candle.low,
          candle.close,
        ].every((p) => p.isFinite && p > 0) ||
        candle.high < math.max(candle.open, candle.close) ||
        candle.low > math.min(candle.open, candle.close)) {
      continue;
    }
    final second = candle.timeMillis ~/ 1000;
    final previous = bySecond[second];
    if (previous == null || !candle.openTime.isBefore(previous.openTime)) {
      bySecond[second] = candle;
    }
  }
  final seconds = bySecond.keys.toList()..sort();
  final source = <Map<String, Object>>[
    for (final second in seconds.skip(math.max(0, seconds.length - 120)))
      {
        'time': second,
        'open': bySecond[second]!.open,
        'high': bySecond[second]!.high,
        'low': bySecond[second]!.low,
        'close': bySecond[second]!.close,
        'volume':
            bySecond[second]!.volume.isFinite && bySecond[second]!.volume >= 0
            ? bySecond[second]!.volume
            : 0,
      },
  ];
  final interval = const {
    '1m': 60,
    '5m': 300,
    '15m': 900,
    '1h': 3600,
    '4h': 14400,
    '1d': 86400,
  }[period];
  if (interval == null || source.isEmpty) return source;
  final result = <Map<String, Object>>[];
  Map<String, Object> gap(int second, Object close) => {
    'time': second,
    'open': close,
    'high': close,
    'low': close,
    'close': close,
    'volume': 0,
  };
  for (final bar in source) {
    if (result.isNotEmpty) {
      final previous = result.last, nextTime = bar['time'] as int;
      for (
        var time = math.max(
          (previous['time'] as int) + interval,
          nextTime - 120 * interval,
        );
        time < nextTime;
        time += interval
      ) {
        result.add(gap(time, previous['close']!));
      }
    }
    result.add(bar);
  }
  final latest = result.last;
  final bucket =
      (now ?? DateTime.now()).millisecondsSinceEpoch ~/
      (interval * 1000) *
      interval;
  for (
    var time = math.max(
      (latest['time'] as int) + interval,
      bucket - 119 * interval,
    );
    time <= bucket;
    time += interval
  ) {
    result.add(gap(time, latest['close']!));
  }
  return result.skip(math.max(0, result.length - 120)).toList();
}

/// The original Flutter canvas renderer, shared by market and trading pages.
class NativePriceChart extends StatefulWidget {
  const NativePriceChart({
    required this.candles,
    required this.period,
    required this.instrument,
    super.key,
  });
  final List<Candle> candles;
  final String period;
  final Instrument instrument;

  @override
  State<NativePriceChart> createState() => _NativePriceChartState();
}

class _NativePriceChartState extends State<NativePriceChart> {
  final controller = KLineController()
    ..itemCount = 38
    ..minCount = 12
    ..maxCount = 90
    ..showTimeAxis = true
    ..showMainIndicators = [IndicatorType.ma]
    ..showSubIndicators = [IndicatorType.vol, IndicatorType.macd];
  Timer? chartClock;

  String marketKey(NativePriceChart chart) =>
      '${chart.instrument.mode.productLine}:${chart.instrument.instrumentId}:${chart.instrument.symbol}:${chart.period}';

  @override
  void initState() {
    super.initState();
    syncCandles(resetView: true);
    // Keep the existing zero-volume current-bucket rule without network work.
    chartClock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => syncCandles(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    applyTheme();
  }

  void applyTheme() {
    final colors = Theme.of(context).colorScheme;
    const figures = [FontFeature.tabularFigures()];
    final ruler = TextStyle(
      color: colors.onSurfaceVariant,
      fontSize: 10,
      fontFeatures: figures,
    );
    controller
      ..chartStyle = KLineChartStyle(
        backgroundColor: colors.surface,
        gridLineColor: colors.outlineVariant.withValues(alpha: .3),
        gridLineWidth: .5,
        rulerTextStyle: ruler,
        highLowLineColor: colors.onSurfaceVariant,
        highLowTextStyle: ruler,
        currentPriceLineColor: colors.primary.withValues(alpha: .65),
        currentPriceBackgroundColor: colors.surfaceContainerHighest,
        currentPriceTextStyle: ruler.copyWith(color: colors.onSurface),
      )
      ..candleStyle = KLineCandleStyle(
        riseColor: colors.tertiary,
        fallColor: colors.error,
        riseWickColor: colors.tertiary.withValues(alpha: .62),
        fallWickColor: colors.error.withValues(alpha: .62),
      )
      ..volumeStyle = KLineVolumeStyle(
        riseColor: colors.tertiary,
        fallColor: colors.error,
      )
      ..indicatorColors = [colors.primary, colors.secondary, colors.tertiary]
      ..crosshairStyle = KLineCrosshairStyle(
        color: colors.primary,
        strokeWidth: .5,
      )
      ..infoStyle = KLineInfoStyle(
        backgroundColor: colors.surface.withValues(alpha: .96),
        textStyle: ruler.copyWith(color: colors.onSurface, fontSize: 11),
      )
      ..infoWidgetBorder = Border.all(color: colors.outlineVariant, width: .5);
    controller.priceFormatter = (value) =>
        money(value, digits: widget.instrument.pricePrecision.clamp(0, 12));
    controller.volumeFormatter = (value) =>
        value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
    controller.indicatorFormatter = (value, type, period) => switch (type) {
      IndicatorType.vol ||
      IndicatorType.maVol => controller.formatVolume(value),
      IndicatorType.macd => compactMacd(value),
      _ => controller.formatPrice(value),
    };
  }

  // MACD is a derived delta, not an order/price quote. Short notation keeps
  // nonzero micro-price deltas readable without extending legends off-screen.
  // Candle prices, rulers, crosshair and MA retain instrument pricePrecision.
  String compactMacd(double value) {
    if (value == 0) return '0';
    var decimal = value.toStringAsPrecision(2);
    if (!decimal.contains('e') && decimal.contains('.')) {
      decimal = decimal.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    final exponent = value
        .toStringAsExponential(1)
        .replaceFirst(RegExp(r'\.0(?=e)'), '')
        .replaceFirst('e+', 'e');
    return decimal.length <= exponent.length ? decimal : exponent;
  }

  @override
  void didUpdateWidget(covariant NativePriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedMarket = marketKey(oldWidget) != marketKey(widget);
    if (changedMarket) {
      controller.itemCount = 38;
      controller.longPressOffset.update(Offset.zero);
    }
    syncCandles(resetView: changedMarket);
  }

  bool sameBar(KLineData a, KLineData b) =>
      a.time == b.time &&
      a.open == b.open &&
      a.high == b.high &&
      a.low == b.low &&
      a.close == b.close &&
      a.volume == b.volume;

  void syncCandles({bool resetView = false}) {
    final next = [
      for (final bar in chartCandles(widget.candles, period: widget.period))
        KLineData(
          // Candle -> normalized seconds -> native library milliseconds, once.
          time: (bar['time'] as int) * 1000,
          open: (bar['open'] as num).toDouble(),
          high: (bar['high'] as num).toDouble(),
          low: (bar['low'] as num).toDouble(),
          close: (bar['close'] as num).toDouble(),
          volume: (bar['volume'] as num).toDouble(),
        ),
    ];
    final previous = controller.data;
    if (next.isEmpty) {
      if (previous.isNotEmpty) controller.clearData();
      return;
    }
    if (resetView || previous.isEmpty) {
      controller.setData(next);
      return;
    }
    var common = 0;
    while (common < math.min(previous.length, next.length) &&
        sameBar(previous[common], next[common])) {
      common++;
    }
    if (common == previous.length && common == next.length) return;
    if (next.length == previous.length &&
        common == next.length - 1 &&
        previous.last.time == next.last.time) {
      controller.updateLast(next.last);
    } else if (next.length == previous.length + 1 &&
        common == previous.length) {
      controller.append(next.last);
    } else {
      // History correction or the bounded 120-bar window advancing: keep zoom.
      controller.setData(next, resetView: false);
    }
  }

  @override
  void dispose() {
    chartClock?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 330,
    child: controller.data.isEmpty
        ? const Center(child: LText('暂无 K 线数据'))
        : LayoutBuilder(
            builder: (context, constraints) {
              controller.infoWidgetMaxWidth = math.min(
                constraints.maxWidth - 16,
                math.max(160, constraints.maxWidth * .7),
              );
              return Semantics(
                label:
                    '${widget.instrument.symbol} ${widget.period} MA VOL MACD',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: KLineView(
                        key: ValueKey(marketKey(widget)),
                        controller: controller,
                      ),
                    ),
                    Text(
                      'VOL · ${widget.instrument.baseAsset}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
  );
}
