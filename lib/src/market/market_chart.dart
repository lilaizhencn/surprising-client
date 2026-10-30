import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../models.dart';
import '../price_chart.dart';
import '../ui/client_components.dart';

class MarketChartPage extends StatelessWidget {
  const MarketChartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final instrument = state.selectedInstrument;
    return Scaffold(
      appBar: AppBar(
        title: Text('${instrument.displayName} · ${state.mode.label}'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: state.refreshPublicData,
          child: ListView(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                state.latestPriceFor(instrument) == null
                    ? '—'
                    : money(
                        state.latestPriceFor(instrument)!,
                        digits: instrument.pricePrecision,
                      ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              KlinePanel(
                candles: state.candles,
                period: state.period,
                onPeriod: (period) => unawaited(state.selectPeriod(period)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KlinePanel extends StatelessWidget {
  const KlinePanel({
    required this.candles,
    required this.period,
    required this.onPeriod,
    super.key,
  });
  final List<Candle> candles;
  final String period;
  final ValueChanged<String> onPeriod;
  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in const ['1m', '5m', '15m', '1h', '4h', '1d'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(value),
                    selected: period == value,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onPeriod(value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (candles.isEmpty)
          const SizedBox(height: 330, child: Center(child: LText('暂无 K 线数据')))
        else
          NativePriceChart(
            candles: candles,
            period: period,
            instrument: AppScope.of(context).selectedInstrument,
          ),
      ],
    ),
  );
}
