import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../funding_records_page.dart';
import '../models.dart';
import '../spot_order.dart';
import '../ui/client_components.dart';
import 'trading_details.dart';

class OrderTicket extends StatelessWidget {
  const OrderTicket({
    required this.side,
    required this.orderType,
    required this.timeInForce,
    required this.marginMode,
    required this.positionMode,
    required this.positionSide,
    required this.reduceOnly,
    required this.postOnly,
    required this.bboEnabled,
    required this.bboPriceMode,
    required this.onBboEnabled,
    required this.onBboPriceMode,
    required this.priceController,
    required this.quantityController,
    required this.instrument,
    required this.loggedIn,
    required this.onSide,
    required this.onOrderType,
    required this.onTimeInForce,
    required this.onMarginMode,
    required this.onPositionSide,
    required this.onReduceOnly,
    required this.onPostOnly,
    required this.onSubmit,
    super.key,
  });

  final String side;
  final String orderType;
  final String timeInForce;
  final String marginMode;
  final String positionMode;
  final String positionSide;
  final bool reduceOnly;
  final bool postOnly;
  final bool bboEnabled;
  final String bboPriceMode;
  final ValueChanged<bool> onBboEnabled;
  final ValueChanged<String> onBboPriceMode;
  final TextEditingController priceController;
  final TextEditingController quantityController;
  final Instrument instrument;
  final bool loggedIn;
  final ValueChanged<String> onSide;
  final ValueChanged<String> onOrderType;
  final ValueChanged<String> onTimeInForce;
  final ValueChanged<String> onMarginMode;
  final ValueChanged<String> onPositionSide;
  final ValueChanged<bool> onReduceOnly;
  final ValueChanged<bool> onPostOnly;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final buy = side == 'BUY';
    final priceMetadataReady =
        (instrument.quoteScaleUnits ?? 0) > 0 && instrument.priceTickUnits > 0;
    final hedgeMode = instrument.isDerivative && positionMode == 'HEDGE';
    final effectiveReduceOnly = instrument.effectiveReduceOnly(
      reduceOnly: reduceOnly,
      side: side,
      positionMode: positionMode,
      positionSide: positionSide,
    );
    void stepPrice(int direction) {
      if (orderType == 'MARKET') return;
      final scale = instrument.quoteScaleUnits;
      if (scale == null || scale <= 0 || instrument.priceTickUnits <= 0) return;
      final current = instrument.priceTicksFromText(priceController.text);
      if (current == null && priceController.text.trim().isNotEmpty) return;
      final next = BigInt.from(current ?? 0) + BigInt.from(direction);
      if (next > BigInt.parse('9223372036854775807')) return;
      priceController.text = scaledAmount(
        (next.isNegative ? BigInt.zero : next) *
            BigInt.from(instrument.priceTickUnits),
        scale,
      );
    }

    void stepQuantity(int direction) {
      final current = instrument.isSpot
          ? decimalIncrement(
                  quantityController.text,
                  instrument.quantityStepUnits,
                  scaleUnits: instrument.baseScaleUnits ?? 0,
                ) ??
                0
          : int.tryParse(quantityController.text) ?? 0;
      final next = math.max(0, current + direction);
      quantityController.text = instrument.isSpot
          ? scaledAmount(
              BigInt.from(next) * BigInt.from(instrument.quantityStepUnits),
              instrument.baseScaleUnits,
            )
          : next.toString();
    }

    return Panel(
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BuySellSwitch(value: side, onChanged: onSide),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, constraints) {
                final orderTypeField = SmallDropdown(
                  value: orderType,
                  values: const ['LIMIT', 'MARKET'],
                  labelBuilder: orderTypeLabel,
                  onChanged: onOrderType,
                );
                final timeInForceField = SmallDropdown(
                  value: timeInForce,
                  values: orderType == 'MARKET'
                      ? const ['IOC', 'FOK']
                      : const ['GTC', 'IOC', 'FOK', 'GTX'],
                  labelBuilder: timeInForceLabel,
                  onChanged: onTimeInForce,
                );
                // Reserve label, arrow and padding space at the user's font size.
                final minimumRowWidth = MediaQuery.textScalerOf(
                  context,
                ).scale(150);
                if (constraints.maxWidth < minimumRowWidth) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      orderTypeField,
                      const SizedBox(height: 5),
                      timeInForceField,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: orderTypeField),
                    const SizedBox(width: 5),
                    Expanded(child: timeInForceField),
                  ],
                );
              },
            ),
            if (instrument.isDerivative) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: SmallDropdown(
                      value: marginMode,
                      values: const ['CROSS', 'ISOLATED'],
                      labelBuilder: marginModeLabel,
                      onChanged: onMarginMode,
                    ),
                  ),
                  if (hedgeMode) ...[
                    const SizedBox(width: 5),
                    Expanded(
                      child: SmallDropdown(
                        value: positionSide == 'NET'
                            ? (instrument.isDelivery && side == 'SELL'
                                  ? 'SHORT'
                                  : 'LONG')
                            : positionSide,
                        values: const ['LONG', 'SHORT'],
                        labelBuilder: positionSideLabel,
                        onChanged: onPositionSide,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 5),
            if (orderType == 'LIMIT') ...[
              Row(
                children: [
                  Expanded(
                    child: ToggleLine(
                      label: 'BBO 最优价',
                      value: bboEnabled,
                      onChanged: onBboEnabled,
                    ),
                  ),
                  if (!bboEnabled)
                    BestPriceButton(
                      enabled: true,
                      onTap: () {
                        final book = AppScope.of(context).orderBook;
                        final levels = buy ? book.asks : book.bids;
                        if (levels.isEmpty) return;
                        if (book.symbol != instrument.symbol) return;
                        priceController.text = scaledAmount(
                          BigInt.from(levels.first.priceTicks) *
                              BigInt.from(instrument.priceTickUnits),
                          instrument.quoteScaleUnits,
                        );
                      },
                    ),
                ],
              ),
              if (bboEnabled) ...[
                SmallDropdown(
                  key: const ValueKey('bbo-price-mode'),
                  value: bboPriceMode,
                  values: bboPriceModes,
                  labelBuilder: bboPriceModeLabel,
                  onChanged: onBboPriceMode,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '提交时按所选盘口档位确定限价，不随行情自动改价。',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ],
            if (orderType == 'LIMIT') const SizedBox(height: 10),
            if (!bboEnabled || orderType == 'MARKET')
              TradeNumericField(
                controller: priceController,
                label: '价格 (${instrument.quoteAsset})',
                enabled: orderType != 'MARKET',
                onMinus: () => stepPrice(-1),
                onPlus: () => stepPrice(1),
              ),
            const SizedBox(height: 5),
            TradeNumericField(
              controller: quantityController,
              label: '数量',
              suffixLabel: instrument.isSpot ? instrument.baseAsset : '张',
              onMinus: () => stepQuantity(-1),
              onPlus: () => stepQuantity(1),
            ),
            if (instrument.isSpot)
              SpotOrderSizing(
                instrument: instrument,
                side: side,
                orderType: orderType,
                bboMode: bboEnabled && orderType == 'LIMIT'
                    ? bboPriceMode
                    : null,
                price: priceController,
                quantity: quantityController,
                loggedIn: loggedIn,
              ),
            if (instrument.isOption)
              ListenableBuilder(
                listenable: Listenable.merge([
                  priceController,
                  quantityController,
                ]),
                builder: (context, _) {
                  final state = AppScope.of(context);
                  final sameSide =
                      orderType == 'LIMIT' &&
                      bboEnabled &&
                      bboPriceMode.startsWith('SAME_SIDE_');
                  final levels = (side == 'BUY') != sameSide
                      ? state.orderBook.asks
                      : state.orderBook.bids;
                  final rank =
                      orderType == 'LIMIT' &&
                          bboEnabled &&
                          bboPriceMode.endsWith('_5')
                      ? 4
                      : 0;
                  final reference = orderType == 'LIMIT' && !bboEnabled
                      ? decimalIncrement(
                          priceController.text,
                          instrument.priceTickUnits,
                          scaleUnits: instrument.quoteScaleUnits ?? 0,
                        )
                      : levels.length > rank
                      ? levels[rank].priceTicks
                      : null;
                  final terms = optionPremiumTerms(
                    instrument: instrument,
                    side: side,
                    priceTicks: reference,
                    quantity: quantityController.text,
                    takerFeeRatePpm: state.optionOrderTerms?.takerFeeRatePpm,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${side == 'BUY' ? '买入权利金及手续费' : '卖出权利金扣费后'} ${terms?.cash ?? '--'} ${instrument.settleAsset}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      if (side == 'SELL')
                        const Text(
                          '卖方保证金按提交时的期权风险核定',
                          style: TextStyle(fontSize: 10),
                        ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 6),
            Text(
              '最小价格变动 ${scaledAmount(BigInt.from(instrument.priceTickUnits), instrument.quoteScaleUnits)} ${instrument.quoteAsset}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 3),
            LayoutBuilder(
              builder: (context, constraints) {
                final postOnlyField = ToggleLine(
                  label: 'Post Only',
                  value: postOnly,
                  enabled: orderType == 'LIMIT',
                  onChanged: onPostOnly,
                );
                if (!instrument.isDerivative) return postOnlyField;
                final reduceOnlyField = ToggleLine(
                  label: '只减仓',
                  value: effectiveReduceOnly,
                  enabled: !(effectiveReduceOnly && !reduceOnly),
                  onChanged: onReduceOnly,
                );
                if (constraints.maxWidth <
                    MediaQuery.textScalerOf(context).scale(180)) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [reduceOnlyField, postOnlyField],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: reduceOnlyField),
                    Expanded(child: postOnlyField),
                  ],
                );
              },
            ),
            if (instrument.status != 'TRADING')
              Text(
                instrument.isDelivery && instrument.status == 'SETTLING'
                    ? '合约结算中，仅允许减仓；撤单与持仓仍可查看'
                    : instrument.status == 'CLOSED'
                    ? '合约已结束，可查看历史记录'
                    : instrument.status == 'PRE_TRADING'
                    ? '该交易对尚未开放交易'
                    : '该交易对已暂停交易',
                style: const TextStyle(fontSize: 11),
              ),
            if (instrument.isExpiring)
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FundingRecordsPage(
                      state: AppScope.of(context),
                      initialCategory: instrument.isOption
                          ? 'option-exercise'
                          : 'delivery-ledger',
                    ),
                  ),
                ),
                child: Text(instrument.isOption ? '期权行权现金流水' : '交割现金流水'),
              ),
            const SizedBox(height: 6),
            if (AppScope.of(context).tradingCommandPending) ...[
              Text(
                tradingPendingMessage(
                  AppScope.of(context).pendingTradingCommand,
                ),
                style: const TextStyle(fontSize: 11),
              ),
              TextButton(
                onPressed: AppScope.of(context).submittingOrder
                    ? null
                    : () => unawaited(
                        AppScope.of(context).checkPendingTradingCommand(),
                      ),
                child: Text(
                  tradingRecoveryLabel(
                    AppScope.of(context).pendingTradingCommand,
                  ),
                ),
              ),
            ],
            FilledButton.icon(
              key: const ValueKey('order-ticket-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: loggedIn
                    ? (buy
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error)
                    : Theme.of(context).colorScheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed:
                  AppScope.of(context).submittingOrder ||
                      AppScope.of(context).tradingCommandPending ||
                      (loggedIn &&
                          (!priceMetadataReady ||
                              !instrument.canPlaceOrder(
                                reduceOnly: effectiveReduceOnly,
                              )))
                  ? null
                  : onSubmit,
              icon: Icon(loggedIn ? Icons.flash_on : Icons.login, size: 16),
              label: Text(
                loggedIn
                    ? instrument.isExpiring && effectiveReduceOnly
                          ? (buy ? '买入平空' : '卖出平多')
                          : instrument.isOption
                          ? (buy ? '买入期权' : '卖出期权')
                          : instrument.isSpot
                          ? (buy ? '买入' : '卖出')
                          : hedgeMode
                          ? (buy ? '买入' : '卖出')
                          : (buy ? '买入 / 开多' : '卖出 / 开空')
                    : '登录',
              ),
            ),
            if (!priceMetadataReady)
              const Text('价格精度未同步，请刷新合约资料', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class SpotOrderSizing extends StatelessWidget {
  const SpotOrderSizing({
    required this.instrument,
    required this.side,
    required this.orderType,
    required this.bboMode,
    required this.price,
    required this.quantity,
    required this.loggedIn,
    super.key,
  });
  final Instrument instrument;
  final String side, orderType;
  final String? bboMode;
  final TextEditingController price, quantity;
  final bool loggedIn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: price,
    builder: (context, _) {
      final state = AppScope.of(context);
      final asset = side == 'BUY'
          ? instrument.quoteAsset
          : instrument.baseAsset;
      final balance = state.balances
          .where(
            (row) =>
                row.accountType == 'SPOT' &&
                row.asset.toUpperCase() == asset.toUpperCase(),
          )
          .firstOrNull;
      final terms = state.spotOrderTerms;
      String? size(int percent) => spotOrderQuantity(
        instrument: instrument,
        balance: balance,
        book: state.orderBook,
        side: side,
        orderType: orderType,
        price: price.text,
        bboMode: bboMode,
        takerFeeRatePpm: terms?.takerFeeRatePpm,
        marketMaxSlippagePpm: terms?.marketMaxSlippagePpm,
        percentage: percent,
      );
      final ready = loggedIn && size(100) != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            '可用 ${scaledAmount(balance == null ? null : BigInt.from(balance.availableUnits), side == 'BUY' ? instrument.quoteScaleUnits : instrument.baseScaleUnits)} $asset',
            style: const TextStyle(fontSize: 10),
          ),
          Row(
            children: [
              for (final percent in [25, 50, 75, 100])
                Expanded(
                  child: TextButton(
                    key: ValueKey('spot-percent-$percent'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: ready
                        ? () {
                            final value = size(percent);
                            if (value != null) {
                              quantity.text = value == '0' ? '' : value;
                            }
                          }
                        : null,
                    child: Text('$percent%'),
                  ),
                ),
            ],
          ),
          if (loggedIn && !ready)
            TextButton(
              onPressed: () => unawaited(() async {
                await state.refreshInstruments(silent: true);
                await state.refreshOrderTerms();
              }()),
              child: const Text('刷新下单资料'),
            ),
        ],
      );
    },
  );
}

class ModeSelector extends StatelessWidget {
  const ModeSelector({required this.value, required this.onChanged, super.key});

  final ProductMode value;
  final ValueChanged<ProductMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ProductMode>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .20)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
      segments: ProductMode.values
          .map((mode) => ButtonSegment(value: mode, label: Text(mode.label)))
          .toList(),
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class PositionModeSelector extends StatelessWidget {
  const PositionModeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.secondary.withValues(alpha: .18)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      segments: const [
        ButtonSegment(value: 'ONE_WAY', label: Text('净仓')),
        ButtonSegment(value: 'HEDGE', label: Text('双向持仓')),
      ],
      selected: {value == 'HEDGE' ? 'HEDGE' : 'ONE_WAY'},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class SymbolStrip extends StatelessWidget {
  const SymbolStrip({
    required this.instruments,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<Instrument> instruments;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: instruments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = instruments[index];
          return ChoiceChip(
            selected: item.symbol == selected,
            selectedColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: .20),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: item.symbol == selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            labelStyle: TextStyle(
              color: item.symbol == selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            label: Text(item.displayName),
            onSelected: (_) => onSelected(item.symbol),
          );
        },
      ),
    );
  }
}

class BuySellSwitch extends StatelessWidget {
  const BuySellSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: value == 'BUY'
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .86),
              foregroundColor: value == 'BUY'
                  ? Colors.white
                  : Theme.of(context).colorScheme.tertiary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => onChanged('BUY'),
            child: const Text('买入'),
          ),
        ),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: value == 'SELL'
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .86),
              foregroundColor: value == 'SELL'
                  ? Colors.white
                  : Theme.of(context).colorScheme.error,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => onChanged('SELL'),
            child: const Text('卖出'),
          ),
        ),
      ],
    );
  }
}

class TradeNumericField extends StatelessWidget {
  const TradeNumericField({
    required this.controller,
    required this.label,
    required this.onMinus,
    required this.onPlus,
    this.suffixLabel,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixLabel;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    const suffixWidth = 24.0;
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => LayoutBuilder(
        builder: (context, constraints) {
          final measure = TextPainter(
            text: TextSpan(text: value.text, style: textStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final available = math.max(
            1.0,
            constraints.maxWidth - 24 - suffixWidth - 20,
          );
          final fontSize = measure.width <= available
              ? 13.0
              : (13 * available / measure.width).clamp(10.0, 13.0);
          measure.dispose();
          return SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: textStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: fontSize,
              ),
              decoration: InputDecoration(
                isDense: true,
                labelText: suffixLabel == null
                    ? label
                    : '$label ($suffixLabel)',
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                prefixIcon: IconButton(
                  tooltip: '减少',
                  onPressed: enabled ? onMinus : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.remove, size: 16),
                ),
                suffixIcon: IconButton(
                  tooltip: '增加',
                  onPressed: enabled ? onPlus : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 28,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                ),
                prefixIconConstraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 40,
                ),
                suffixIconConstraints: BoxConstraints.tightFor(
                  width: suffixWidth,
                  height: 40,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BestPriceButton extends StatelessWidget {
  const BestPriceButton({
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          enabled ? '最优价' : '市价',
          style: TextStyle(
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class OrderMetaRow extends StatelessWidget {
  const OrderMetaRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderAmountSlider extends StatelessWidget {
  const OrderAmountSlider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            right: 8,
            child: Container(
              height: 3,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              return Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: index == 0 ? 14 : 10,
                  height: index == 0 ? 14 : 10,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? Theme.of(context).colorScheme.surface
                        : Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: index == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
