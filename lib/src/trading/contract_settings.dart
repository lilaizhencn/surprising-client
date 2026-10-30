import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../api.dart' show clientErrorMessage;
import '../auth/auth_sheet.dart';
import '../models.dart';
import '../option_market.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';

class TradeSymbolHeader extends StatelessWidget {
  const TradeSymbolHeader({
    required this.instrument,
    required this.latestPrice,
    required this.onRefresh,
    required this.onChart,
    super.key,
  });

  final Instrument instrument;
  final double? latestPrice;
  final VoidCallback onRefresh;
  final VoidCallback onChart;

  @override
  Widget build(BuildContext context) {
    final change = instrument.change24h;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      instrument.displayName.replaceAll('-', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  if (instrument.isDerivative)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: LText(
                        instrument.contractLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: change == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : change >= 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: clientLabel(context, 'K线'),
          onPressed: onChart,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.candlestick_chart_outlined, size: 20),
        ),
        IconButton(
          tooltip: clientLabel(context, '更多'),
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 21),
        ),
      ],
    );
  }
}

class ProductLifecyclePanel extends StatelessWidget {
  const ProductLifecyclePanel({
    required this.state,
    required this.instrument,
    required this.latestPrice,
    super.key,
  });

  final AppState state;
  final Instrument instrument;
  final double? latestPrice;

  @override
  Widget build(BuildContext context) {
    final isOption = instrument.isOption;
    final reference = state.optionReference;
    final underlyingPrice = reference?.underlyingIndexPrice;
    final strike = scaledAmount(
      instrument.strikePriceUnits == null
          ? null
          : BigInt.from(instrument.strikePriceUnits!),
      instrument.quoteScaleUnits,
    );
    final intrinsic = reference?.intrinsicValue;
    final chain = optionChain(instrument, state.instruments);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOption ? Icons.auto_graph : Icons.event_available_outlined,
                size: 18,
                color: ClientColors.warningFor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: LText(
                  isOption ? '期权合约' : '交割合约生命周期',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                instrument.mode.productLine,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              LifecycleChip(
                label: clientLabel(context, '状态'),
                value: instrument.status,
              ),
              if (instrument.mode == ProductMode.inverseDelivery)
                LifecycleChip(
                  label: clientLabel(context, '每张面值'),
                  value:
                      (instrument.notionalMultiplierUnits ?? 0) > 0 &&
                          (instrument.quoteScaleUnits ?? 0) > 0
                      ? '${scaledAmount(BigInt.from(instrument.notionalMultiplierUnits!), instrument.quoteScaleUnits)} ${instrument.quoteAsset}'
                      : '--',
                ),
              LifecycleChip(
                label: clientLabel(context, '到期'),
                value: shortDateTime(instrument.expiryTime),
              ),
              LifecycleChip(
                label: isOption ? '行权' : '交割',
                value: shortDateTime(instrument.deliveryTime),
              ),
              LifecycleChip(
                label: instrument.isDelivery ? '距到期' : '剩余',
                value: timeLeft(instrument.expiryTime),
              ),
              LifecycleChip(
                label: clientLabel(context, '结算'),
                value: instrument.settlementMethod ?? '--',
              ),
              LifecycleChip(
                label: clientLabel(context, '账户'),
                value: instrument.mode.accountType,
              ),
              if (isOption)
                LifecycleChip(
                  label: clientLabel(context, '期权类型'),
                  value: switch (instrument.optionType) {
                    'CALL' => '看涨 CALL',
                    'PUT' => '看跌 PUT',
                    _ => '--',
                  },
                ),
              if (isOption)
                LifecycleChip(
                  label: clientLabel(context, '标的'),
                  value:
                      '${instrument.baseAsset} · ${instrument.underlyingInstrumentId ?? '--'}',
                ),
            ],
          ),
          if (isOption) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MetricPill(
                  label: clientLabel(context, '标的指数'),
                  value: underlyingPrice == null
                      ? '--'
                      : money(
                          underlyingPrice,
                          digits: instrument.pricePrecision,
                        ),
                  color: Theme.of(context).colorScheme.secondary,
                ),
                MetricPill(
                  label: clientLabel(context, '行权价'),
                  value: '$strike ${instrument.quoteAsset}',
                  color: ClientColors.warningFor(context),
                ),
                MetricPill(
                  label: clientLabel(context, '权利金'),
                  value: reference == null
                      ? '--'
                      : money(
                          reference.premiumPrice,
                          digits: instrument.pricePrecision,
                        ),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                MetricPill(
                  label: clientLabel(context, '内在价值'),
                  value: intrinsic == null
                      ? '--'
                      : money(intrinsic, digits: instrument.pricePrecision),
                  color: intrinsic != null && intrinsic > 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                MetricPill(
                  label: clientLabel(context, '同到期远期价'),
                  value: reference == null
                      ? '--'
                      : money(
                          reference.sameExpiryForwardPrice,
                          digits: instrument.pricePrecision,
                        ),
                  color: ClientColors.warningFor(context),
                ),
                for (final entry in <String, double?>{
                  '隐含波动率%': reference?.greeks == null
                      ? null
                      : reference!.greeks!.impliedVolatility * 100,
                  '远期 Delta': reference?.greeks?.forwardDelta,
                  '远期 Gamma': reference?.greeks?.forwardGamma,
                  'Vega / 波动率1%': reference?.greeks?.vegaPerVolPoint,
                  'Theta / 天': reference?.greeks?.thetaPerDay,
                }.entries)
                  MetricPill(
                    label: entry.key,
                    value: entry.value == null
                        ? '--'
                        : '${money(entry.value!, digits: entry.key == '远期 Gamma' ? 10 : 6)}${entry.key.startsWith('Vega') || entry.key.startsWith('Theta') ? ' ${instrument.quoteAsset}' : ''}',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            LText(
              'Black-76 参考值 · 零贴现 · 每1 ${instrument.baseAsset}',
              style: const TextStyle(fontSize: 11),
            ),
            LText(
              reference == null
                  ? '参考报价暂不可用或已过期'
                  : reference.greeks == null
                  ? '当前报价无法在参考模型下求得隐含波动率'
                  : '报价时间 ${shortDateTime(reference.asOf)}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 8),
            if (chain.isEmpty)
              const LText('暂无同到期期权链')
            else
              Column(
                children: [
                  InfoLine(
                    label: clientLabel(context, '同到期期权链'),
                    value: 'CALL / 行权价 / PUT',
                  ),
                  for (final row in chain)
                    Row(
                      children: [
                        for (final isCall in [true, false]) ...[
                          if (!isCall)
                            Expanded(
                              child: Text(
                                scaledAmount(
                                  row.strikeUnits,
                                  instrument.quoteScaleUnits,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          Expanded(
                            child: Column(
                              children: [
                                for (final contract
                                    in isCall ? row.calls : row.puts)
                                  TextButton(
                                    key: ValueKey(
                                      'option-chain-${contract.instrumentId}',
                                    ),
                                    onPressed: () => unawaited(
                                      state.selectSymbol(contract.symbol),
                                    ),
                                    child: Text(
                                      '${contract.symbol}\n${contract.status}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                if ((isCall ? row.calls : row.puts).isEmpty)
                                  const Text('--'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: clientLabel(context, '方向'),
                    value: instrument.mode == ProductMode.inverseDelivery
                        ? '币本位反向'
                        : 'U本位正向',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: clientLabel(context, '结算资产'),
                    value: instrument.settleAsset,
                    color: ClientColors.warningFor(context),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: clientLabel(context, '最大杠杆'),
                    value: '${(instrument.maxLeveragePpm / 1000000).round()}x',
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class LifecycleChip extends StatelessWidget {
  const LifecycleChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class ContractQuickSettings extends StatelessWidget {
  const ContractQuickSettings({
    required this.marginMode,
    required this.leverage,
    this.showLeverage = true,
    required this.positionMode,
    required this.onMarginMode,
    required this.onPositionMode,
    super.key,
  });

  final String marginMode;
  final String leverage;
  final bool showLeverage;
  final String positionMode;
  final ValueChanged<String> onMarginMode;
  final ValueChanged<String> onPositionMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TradeSettingButton(
            label: marginMode == 'ISOLATED' ? '逐仓' : '全仓',
            onTap: () =>
                onMarginMode(marginMode == 'ISOLATED' ? 'CROSS' : 'ISOLATED'),
          ),
        ),
        const SizedBox(width: 5),
        if (showLeverage)
          Expanded(
            child: TradeSettingButton(
              label: clientLabel(context, '杠杆'),
              onTap: () {
                final state = AppScope.of(context);
                if (!state.isLoggedIn) {
                  showAuthSheet(context);
                  return;
                }
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => TradingLeverageSheet(
                    state: state,
                    instrument: state.selectedInstrument,
                    marginMode: marginMode,
                  ),
                );
              },
            ),
          ),
        const SizedBox(width: 5),
        Expanded(
          child: TradeSettingButton(
            label: positionMode == 'HEDGE' ? '双' : '单',
            onTap: () =>
                onPositionMode(positionMode == 'HEDGE' ? 'ONE_WAY' : 'HEDGE'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 4,
          child: LText(
            _fundingLabel(AppScope.of(context)),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9.5,
              height: 1.12,
            ),
          ),
        ),
      ],
    );
  }
}

class TradeSettingButton extends StatelessWidget {
  const TradeSettingButton({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: LText(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

String _fundingLabel(AppState state) {
  if (!state.mode.isPerpetual) return '';
  final metrics =
      state.marketMetrics['${state.mode.productLine}:${state.selectedSymbol}'];
  final rate = parseInt64(metrics?['fundingRatePpm']);
  return '资金费率\n${rate == null ? '--' : '${(rate / 10000).toStringAsFixed(4)}%'}';
}

class TradingLeverageSheet extends StatefulWidget {
  const TradingLeverageSheet({
    required this.state,
    required this.instrument,
    required this.marginMode,
    super.key,
  });
  final AppState state;
  final Instrument instrument;
  final String marginMode;
  @override
  State<TradingLeverageSheet> createState() => _TradingLeverageSheetState();
}

class _TradingLeverageSheetState extends State<TradingLeverageSheet> {
  final controller = TextEditingController();
  late final int? userId;
  late final String? token;
  Map<String, dynamic>? setting;
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    userId = widget.state.userId;
    token = widget.state.session?.accessToken;
    unawaited(load());
  }

  bool get sameSession =>
      userId != null &&
      widget.state.userId == userId &&
      widget.state.session?.accessToken == token;
  Future<void> load() async {
    try {
      if (!sameSession) throw StateError('请先登录');
      final row = await widget.state.api.leverageSetting(
        userId!,
        widget.instrument,
        widget.marginMode,
      );
      if (!mounted) return;
      if (!sameSession) throw StateError('登录状态已变化，请重新打开');
      final maximum = parseInt64(row['maxLeveragePpm']);
      final current = parseInt64(row['leveragePpm']);
      if (maximum == null ||
          current == null ||
          maximum < 1000000 ||
          current < 1000000 ||
          current > maximum) {
        throw StateError('杠杆配置尚未就绪');
      }
      setState(() {
        setting = row;
        controller.text = scaledAmount(BigInt.from(current), 1000000);
        loading = false;
      });
    } catch (cause) {
      if (mounted) {
        setState(() {
          error = '加载杠杆失败：${clientErrorMessage(cause)}';
          loading = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (saving || setting == null) return;
    final ppm = decimalIncrement(controller.text, 1, scaleUnits: 1000000);
    if (!sameSession ||
        ppm == null ||
        ppm < 1000000 ||
        ppm > asInt(setting!['maxLeveragePpm'])) {
      setState(() => error = sameSession ? '请输入有效范围内的杠杆倍数' : '登录状态已变化，请重新打开');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.state.api.updateLeverage(
        userId!,
        widget.instrument,
        widget.marginMode,
        ppm,
      );
      if (!mounted) return;
      if (!sameSession) {
        setState(() => error = '登录状态已变化，请核对设置');
        return;
      }
      widget.state.leverageUpdated();
      Navigator.pop(context);
    } catch (cause) {
      if (mounted) {
        setState(() => error = '修改杠杆失败：${clientErrorMessage(cause)}');
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            '${widget.instrument.symbol} · ${widget.marginMode == 'ISOLATED' ? '逐仓' : '全仓'}杠杆',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (setting != null) ...[
            LText('允许范围 1–${asInt(setting!['maxLeveragePpm']) / 1000000}×'),
            TextField(
              controller: controller,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: clientLabel(context, '杠杆倍数'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : save,
              child: LText(saving ? '保存中…' : '保存杠杆'),
            ),
          ],
          if (error != null)
            LText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
