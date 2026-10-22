import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../models.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import 'trading_details.dart';

class OrderBookPanel extends StatelessWidget {
  const OrderBookPanel({
    required this.instrument,
    required this.orderBook,
    required this.latestPrice,
    required this.onPrice,
    this.recovering = false,
    super.key,
  });

  final bool recovering;
  final Instrument instrument;
  final OrderBook orderBook;
  final double? latestPrice;
  final ValueChanged<String> onPrice;

  @override
  Widget build(BuildContext context) {
    final maxQuantity = [
      ...orderBook.asks.take(5),
      ...orderBook.bids.take(5),
    ].fold<int>(0, (value, level) => math.max(value, level.quantitySteps));
    final asks = orderBook.asks.take(5).toList().reversed.toList();
    final bids = orderBook.bids.take(5).toList();
    final askTotal = asks.fold<BigInt>(
      BigInt.zero,
      (sum, level) => sum + BigInt.from(level.quantitySteps),
    );
    final bidTotal = bids.fold<BigInt>(
      BigInt.zero,
      (sum, level) => sum + BigInt.from(level.quantitySteps),
    );
    final buyRatio = bidTotal + askTotal == BigInt.zero
        ? .5
        : bidTotal / (bidTotal + askTotal);
    final fallbackPriceTicks = bids.isNotEmpty
        ? bids.first.priceTicks
        : (asks.isNotEmpty ? asks.last.priceTicks : 0);
    final displayPrice =
        latestPrice ??
        (fallbackPriceTicks == 0
            ? null
            : instrument.priceFromTicks(fallbackPriceTicks));
    return Panel(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '价格',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                instrument.isSpot ? '数量 (${instrument.baseAsset})' : '数量（张）',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (recovering)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '盘口恢复中',
                key: ValueKey('depth-recovering'),
                style: TextStyle(fontSize: 10),
              ),
            ),
          for (final level in asks)
            BookLine(
              level: level,
              maxQuantity: maxQuantity,
              instrument: instrument,
              color: Theme.of(context).colorScheme.error,
              onTap: onPrice,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              displayPrice == null
                  ? '--'
                  : money(displayPrice, digits: instrument.pricePrecision),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
          for (final level in bids)
            BookLine(
              level: level,
              maxQuantity: maxQuantity,
              instrument: instrument,
              color: Theme.of(context).colorScheme.tertiary,
              onTap: onPrice,
            ),
          const Spacer(),
          if (bids.isNotEmpty || asks.isNotEmpty)
            OrderBookRatioBar(buyRatio: buyRatio)
          else
            const SizedBox(height: 16),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AppScope(
                notifier: AppScope.of(context),
                child: FullOrderBookSheet(onPrice: onPrice),
              ),
            ),
            child: const Text('查看20档', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class OrderBookRatioBar extends StatelessWidget {
  const OrderBookRatioBar({required this.buyRatio, super.key});

  final double buyRatio;

  @override
  Widget build(BuildContext context) {
    final buy = buyRatio.clamp(0.0, 1.0);
    final sell = 1 - buy;
    return Row(
      children: [
        Text(
          '${(buy * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Theme.of(context).colorScheme.tertiary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 4,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, (buy * 1000).round()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(999),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  color: Theme.of(context).colorScheme.surface,
                ),
                Expanded(
                  flex: math.max(1, (sell * 1000).round()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${(sell * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class OrderBookLayoutIcon extends StatelessWidget {
  const OrderBookLayoutIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(28),
      painter: _BookGridPainter(),
    );
  }
}

class _BookGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      ClientColors.negative,
      ClientColors.muted,
      ClientColors.positive,
      ClientColors.muted,
    ];
    final rects = [
      Rect.fromLTWH(size.width * .08, size.height * .10, 7, 7),
      Rect.fromLTWH(size.width * .08, size.height * .42, 7, 7),
      Rect.fromLTWH(size.width * .08, size.height * .74, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .10, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .42, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .74, 7, 7),
    ];
    for (var i = 0; i < rects.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(1.4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BookLine extends StatelessWidget {
  const BookLine({
    required this.level,
    required this.maxQuantity,
    required this.instrument,
    required this.color,
    required this.onTap,
    super.key,
  });

  final OrderBookLevel level;
  final int maxQuantity;
  final Instrument instrument;
  final Color color;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final price = scaledAmount(
      BigInt.from(level.priceTicks) * BigInt.from(instrument.priceTickUnits),
      instrument.quoteScaleUnits,
    );
    final depth = maxQuantity <= 0
        ? 0.0
        : (level.quantitySteps / maxQuantity).clamp(0.0, 1.0);
    return InkWell(
      onTap: price == '--' ? null : () => onTap(price),
      child: SizedBox(
        height: 20,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: depth,
                child: Container(color: color.withValues(alpha: .14)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    price,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  instrument.isSpot
                      ? scaledAmount(
                          BigInt.from(level.quantitySteps) *
                              BigInt.from(instrument.quantityStepUnits),
                          instrument.baseScaleUnits,
                        )
                      : compactInt(level.quantitySteps),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _positiveDecimalText(Object? value) {
  if (value is! String && value is! num) return null;
  final text = '$value';
  if (text.length > 256) return null;
  final parsed = double.tryParse(text);
  return parsed != null && parsed.isFinite && parsed > 0 ? text : null;
}

String _recentTradePrice(Map<String, dynamic> trade, Instrument instrument) {
  if (trade['priceTicks'] == null) {
    return _positiveDecimalText(trade['price']) ?? '--';
  }
  final ticks = parseInt64(trade['priceTicks']);
  return ticks == null || ticks <= 0
      ? '--'
      : scaledAmount(
          BigInt.from(ticks) * BigInt.from(instrument.priceTickUnits),
          instrument.quoteScaleUnits,
        );
}

String _recentTradeQuantity(Map<String, dynamic> trade, Instrument instrument) {
  if (trade['quantitySteps'] == null) {
    return _positiveDecimalText(trade['quantity']) ?? '--';
  }
  final steps = parseInt64(trade['quantitySteps']);
  return steps == null || steps <= 0
      ? '--'
      : tradingQuantity(instrument, steps);
}

class RecentTradesPanel extends StatelessWidget {
  const RecentTradesPanel({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final instrument = state.selectedInstrument;
    return ExpansionTile(
      title: const Text('最新成交'),
      children: [
        if (state.recentTrades.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无成交')),
        for (final trade in state.recentTrades.take(50))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    asNullableDateTime(
                          trade['eventTime'],
                        )?.toLocal().toIso8601String().substring(11, 19) ??
                        '--',
                  ),
                ),
                Expanded(
                  child: Text(
                    _recentTradePrice(trade, instrument),
                    style: TextStyle(
                      color: trade['side'] == 'BUY'
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    _recentTradeQuantity(trade, instrument),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class FullOrderBookSheet extends StatefulWidget {
  const FullOrderBookSheet({this.onPrice, super.key});
  final ValueChanged<String>? onPrice;
  @override
  State<FullOrderBookSheet> createState() => _FullOrderBookSheetState();
}

class _FullOrderBookSheetState extends State<FullOrderBookSheet> {
  int multiple = 1;
  int depth = 20;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), instrument = state.selectedInstrument;
    final bids = aggregateBookLevels(
      state.orderBook.bids,
      multiple,
      bids: true,
    ).take(depth).toList();
    final asks = aggregateBookLevels(
      state.orderBook.asks,
      multiple,
      bids: false,
    ).take(depth).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          ListTile(
            title: Text('${instrument.displayName} · 盘口'),
            subtitle: const Text('实时完整快照，最多 20 档'),
            trailing: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('价格档位'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    key: const ValueKey('book-precision'),
                    isExpanded: true,
                    value: multiple,
                    items: [
                      for (final value in [
                        1,
                        10,
                        100,
                        500,
                        1000,
                        10000,
                        100000,
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            money(
                              instrument.priceFromTicks(value),
                              digits: instrument.pricePrecision,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => multiple = value ?? 1),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('档数'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  key: const ValueKey('book-depth'),
                  value: depth,
                  items: [
                    for (final value in [10, 20])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() => depth = value ?? 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.market.depthRecovering)
                  const Text('盘口恢复中，请稍候')
                else if (bids.isEmpty && asks.isEmpty)
                  const Text('暂无盘口'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _side(
                        instrument,
                        bids,
                        '买盘',
                        Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _side(
                        instrument,
                        asks,
                        '卖盘',
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _side(
    Instrument instrument,
    List<OrderBookLevel> levels,
    String title,
    Color color,
  ) {
    var total = BigInt.zero;
    final rows = <({OrderBookLevel level, BigInt total})>[];
    for (final level in levels) {
      total += BigInt.from(level.quantitySteps);
      rows.add((level: level, total: total));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: widget.onPrice == null
                      ? null
                      : () {
                          widget.onPrice!(
                            scaledAmount(
                              BigInt.from(row.level.priceTicks) *
                                  BigInt.from(instrument.priceTickUnits),
                              instrument.quoteScaleUnits,
                            ),
                          );
                          Navigator.pop(context);
                        },
                  child: Text(
                    scaledAmount(
                      BigInt.from(row.level.priceTicks) *
                          BigInt.from(instrument.priceTickUnits),
                      instrument.quoteScaleUnits,
                    ),
                    style: TextStyle(color: color),
                  ),
                ),
                Text(
                  '数量 ${tradingQuantity(instrument, row.level.quantitySteps)}',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  '累计 ${instrument.isSpot ? '${scaledAmount(row.total * BigInt.from(instrument.quantityStepUnits), instrument.baseScaleUnits)} ${instrument.baseAsset}' : '${row.total} 张'}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Product selection remains visible while a trading page scrolls. Each tab
/// selects a complete product context, rather than sharing a symbol-only view.
