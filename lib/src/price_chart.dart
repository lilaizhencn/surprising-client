import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models.dart';

/// Web PriceChart parity: deduplication, zero-volume gap bars and a 120-bar window.
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
  WebViewController? controller;
  bool started = false, ready = false, failed = false;
  Timer? timeout;
  Timer? chartClock;

  @override
  void initState() {
    super.initState();
    chartClock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_render()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      unawaited(_initialize());
    } else {
      unawaited(_render());
    }
  }

  Future<void> _initialize() async {
    if (WebViewPlatform.instance == null) {
      if (mounted) setState(() => failed = true);
      return;
    }
    try {
      final background = Theme.of(context).colorScheme.surface;
      final surface = Theme.of(context).brightness == Brightness.dark
          ? '#191c23'
          : '#ffffff';
      final view = WebViewController();
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await view.setBackgroundColor(background);
      await view.addJavaScriptChannel(
        'ChartReady',
        onMessageReceived: (_) {
          if (!mounted) return;
          timeout?.cancel();
          setState(() {
            ready = true;
            failed = false;
          });
          unawaited(_render());
        },
      );
      await view.addJavaScriptChannel(
        'ChartError',
        onMessageReceived: (_) {
          if (mounted) setState(() => failed = true);
        },
      );
      await view.addJavaScriptChannel(
        'ChartLink',
        onMessageReceived: (message) {
          final uri = Uri.tryParse(message.message);
          if (uri?.scheme == 'https' &&
              ['www.tradingview.com', 'tradingview.com'].contains(uri?.host)) {
            unawaited(
              launchUrl(
                uri!,
                mode: LaunchMode.externalApplication,
              ).catchError((Object _) => false),
            );
          }
        },
      );
      await view.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
      final assets = await Future.wait([
        rootBundle.loadString('assets/charts/chart.html'),
        rootBundle.loadString(
          'assets/charts/lightweight-charts.standalone.production.js',
        ),
        rootBundle.loadString('assets/charts/chart_bridge.js'),
      ]);
      if (!mounted) return;
      final html = assets[0]
          .replaceAll('__SURFACE__', surface)
          .replaceFirst(
            '<!-- CHART_LIBRARY -->',
            '<script>${assets[1]}</script>',
          )
          .replaceFirst(
            '<!-- CHART_BRIDGE -->',
            '<script>${assets[2]}</script>',
          );
      setState(() {
        controller = view;
        ready = false;
        failed = false;
      });
      timeout?.cancel();
      timeout = Timer(const Duration(seconds: 12), () {
        if (mounted && !ready) setState(() => failed = true);
      });
      await view.loadHtmlString(html);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant NativePriceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_render());
  }

  Future<void> _render() async {
    final view = controller;
    if (!mounted || view == null || !ready) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final instrument = widget.instrument;
    final precision = instrument.pricePrecision.clamp(0, 12);
    final tick = instrument.priceFromTicks(1);
    final payload = {
      'market':
          '${instrument.mode.productLine}:${instrument.instrumentId}:${instrument.symbol}:${widget.period}',
      'bars': chartCandles(widget.candles, period: widget.period),
      'precision': precision,
      'minMove': tick.isFinite && tick > 0 ? tick : math.pow(10, -precision),
      'volumeUnit': instrument.baseAsset,
      'theme': {
        'background': dark ? '#191c23' : '#ffffff',
        'ink': dark ? '#c6c9d1' : '#434656',
        'border': dark ? '#343a49' : '#c3c5d9',
        'grid': dark ? '#292e39' : '#e9e7ea',
        'up': dark ? '#55df9a' : '#006d3f',
        'down': dark ? '#ff7d86' : '#9e0d22',
        'wickUp': dark ? 'rgba(85,223,154,.62)' : 'rgba(0,109,63,.62)',
        'wickDown': dark ? 'rgba(255,125,134,.62)' : 'rgba(158,13,34,.62)',
      },
    };
    try {
      await view.runJavaScript('window.renderChart(${jsonEncode(payload)})');
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    chartClock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 330,
    child: failed
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('图表暂不可用'),
                TextButton(
                  onPressed: () => unawaited(_initialize()),
                  child: const Text('重试'),
                ),
              ],
            ),
          )
        : Stack(
            children: [
              if (controller != null)
                Positioned.fill(
                  child: WebViewWidget(
                    controller: controller!,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                ),
              if (!ready) const Center(child: CircularProgressIndicator()),
            ],
          ),
  );
}
