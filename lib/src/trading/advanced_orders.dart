import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';

class AlgoOrderPanel extends StatefulWidget {
  const AlgoOrderPanel({
    required this.state,
    required this.marginMode,
    super.key,
  });

  final AppState state;
  final String marginMode;

  @override
  State<AlgoOrderPanel> createState() => _AlgoOrderPanelState();
}

class _AlgoOrderPanelState extends State<AlgoOrderPanel> {
  String algoType = 'TWAP';
  String side = 'BUY';
  String positionSide = 'LONG';
  bool reduceOnly = false;
  bool postOnly = false;
  bool submitting = false;
  late final TextEditingController priceTicksController;
  final quantityController = TextEditingController(text: '2');
  final childQuantityController = TextEditingController(text: '1');
  final intervalController = TextEditingController(text: '5');
  final durationController = TextEditingController(text: '20');

  @override
  void initState() {
    super.initState();
    priceTicksController = TextEditingController(
      text: _defaultPriceTicks().toString(),
    );
  }

  @override
  void dispose() {
    priceTicksController.dispose();
    quantityController.dispose();
    childQuantityController.dispose();
    intervalController.dispose();
    durationController.dispose();
    super.dispose();
  }

  int _defaultPriceTicks() {
    final instrument = widget.state.selectedInstrument;
    final latestPrice = widget.state.latestPriceFor(instrument);
    if (latestPrice != null && latestPrice > 0) {
      return instrument.ticksFromPrice(latestPrice);
    }
    final book = widget.state.orderBook;
    if (book.symbol == instrument.symbol) {
      if (side == 'BUY' && book.asks.isNotEmpty) {
        return book.asks.first.priceTicks;
      }
      if (side == 'SELL' && book.bids.isNotEmpty) {
        return book.bids.first.priceTicks;
      }
    }
    return 0;
  }

  bool get _valid {
    final priceTicks = int.tryParse(priceTicksController.text) ?? 0;
    final quantity = int.tryParse(quantityController.text) ?? 0;
    final childQuantity = int.tryParse(childQuantityController.text) ?? 0;
    final interval = int.tryParse(intervalController.text) ?? 0;
    final duration = int.tryParse(durationController.text) ?? 0;
    if (quantity <= 0 || childQuantity <= 0 || childQuantity > quantity) {
      return false;
    }
    if (duration <= 0 || algoType == 'TWAP' && interval <= 0) return false;
    return algoType == 'TWAP' || priceTicks > 0;
  }

  Future<void> submit() async {
    if (!_valid || submitting) return;
    setState(() => submitting = true);
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    final effectivePositionSide = hedgeMode ? positionSide : 'NET';
    await widget.state.placeAlgoOrder(
      AlgoOrderDraft(
        algoType: algoType,
        side: side,
        priceTicks: int.tryParse(priceTicksController.text) ?? 0,
        quantitySteps: int.tryParse(quantityController.text) ?? 0,
        childQuantitySteps: int.tryParse(childQuantityController.text) ?? 0,
        intervalSeconds: algoType == 'TWAP'
            ? int.tryParse(intervalController.text) ?? 0
            : 0,
        durationSeconds: int.tryParse(durationController.text) ?? 0,
        marginMode: widget.marginMode,
        positionSide: effectivePositionSide,
        reduceOnly: reduceOnly,
        postOnly: algoType == 'ICEBERG' && postOnly,
      ),
    );
    if (mounted) setState(() => submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LText('算法单', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmallDropdown(
                  value: algoType,
                  values: const ['TWAP', 'ICEBERG'],
                  labelBuilder: algoTypeLabel,
                  onChanged: (value) => setState(() {
                    algoType = value;
                    if (value == 'TWAP') postOnly = false;
                  }),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SmallDropdown(
                  value: side,
                  values: const ['BUY', 'SELL'],
                  onChanged: (value) => setState(() => side = value),
                ),
              ),
              if (hedgeMode) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: SmallDropdown(
                    value: positionSide,
                    values: const ['LONG', 'SHORT'],
                    labelBuilder: positionSideLabel,
                    onChanged: (value) => setState(() => positionSide = value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: priceTicksController,
                  label: clientLabel(context, '价格 ticks'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: quantityController,
                  label: clientLabel(context, '总量 steps'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: childQuantityController,
                  label: clientLabel(context, '切片 steps'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (algoType == 'TWAP') ...[
                Expanded(
                  child: AppTextField(
                    controller: intervalController,
                    label: clientLabel(context, '间隔秒'),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: AppTextField(
                  controller: durationController,
                  label: clientLabel(context, '时长秒'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ToggleLine(
                  label: clientLabel(context, '只减仓'),
                  value: reduceOnly,
                  onChanged: (value) => setState(() => reduceOnly = value),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ToggleLine(
                  label: 'Post',
                  value: postOnly,
                  enabled: algoType == 'ICEBERG',
                  onChanged: (value) => setState(() => postOnly = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: _valid && !submitting ? submit : null,
            icon: Icon(submitting ? Icons.hourglass_top : Icons.schedule),
            label: LText(submitting ? '提交中' : '提交 ${algoTypeLabel(algoType)}'),
          ),
        ],
      ),
    );
  }
}

class TriggerOrderPanel extends StatefulWidget {
  const TriggerOrderPanel({
    required this.state,
    required this.marginMode,
    super.key,
  });

  final AppState state;
  final String marginMode;

  @override
  State<TriggerOrderPanel> createState() => _TriggerOrderPanelState();
}

class _TriggerOrderPanelState extends State<TriggerOrderPanel> {
  final List<_TriggerLevelInput> levels = [];
  bool submitting = false;
  bool oco = false;
  String priceSource = 'MARK';

  void addLevel(String triggerType) {
    if (submitting) return;
    final defaultPrice = _defaultTriggerPrice();
    setState(() {
      levels.add(
        _TriggerLevelInput(
          id: '${DateTime.now().microsecondsSinceEpoch}-${levels.length}',
          triggerType: triggerType,
          closeTarget: 'LONG',
          triggerPriceTicks: triggerType == 'TRAILING_STOP'
              ? '0'
              : defaultPrice,
          activationPriceTicks: triggerType == 'TRAILING_STOP'
              ? defaultPrice
              : '',
          callbackRatePpm: triggerType == 'TRAILING_STOP' ? '0.1' : '',
          quantitySteps: '1',
        ),
      );
    });
  }

  String _defaultTriggerPrice() {
    final instrument = widget.state.selectedInstrument;
    final price = widget.state.latestPriceFor(instrument);
    return price == null
        ? ''
        : price.toStringAsFixed(instrument.pricePrecision);
  }

  List<TriggerOrderDraft> _drafts() {
    final scale = widget.state.selectedInstrument.quoteScaleUnits;
    if (scale == null || scale <= 0) return [];
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    return levels
        .where(
          (level) =>
              level.triggerType != 'TRAILING_STOP' ||
              level.activationPriceTicks.trim().isEmpty ||
              decimalIncrement(
                    level.activationPriceTicks,
                    widget.state.selectedInstrument.priceTickUnits,
                    scaleUnits: scale,
                  ) !=
                  null,
        )
        .map((level) {
          final triggerPriceTicks =
              decimalIncrement(
                level.triggerPriceTicks,
                widget.state.selectedInstrument.priceTickUnits,
                scaleUnits: scale,
              ) ??
              0;
          final activationPriceTicks = decimalIncrement(
            level.activationPriceTicks,
            widget.state.selectedInstrument.priceTickUnits,
            scaleUnits: scale,
          );
          final callbackRatePpm = decimalIncrement(
            level.callbackRatePpm,
            10000,
          );
          final quantitySteps = int.tryParse(level.quantitySteps) ?? 0;
          return TriggerOrderDraft(
            side: level.closeTarget == 'LONG' ? 'SELL' : 'BUY',
            triggerType: level.triggerType,
            triggerPriceTicks: triggerPriceTicks,
            activationPriceTicks: level.triggerType == 'TRAILING_STOP'
                ? activationPriceTicks
                : null,
            callbackRatePpm: level.triggerType == 'TRAILING_STOP'
                ? callbackRatePpm
                : null,
            quantitySteps: quantitySteps,
            marginMode: widget.marginMode,
            positionSide: hedgeMode ? level.closeTarget : 'NET',
            priceSource: priceSource,
            orderType: level.orderType,
            priceTicks: level.orderType == 'MARKET'
                ? 0
                : decimalIncrement(
                        level.limitPrice,
                        widget.state.selectedInstrument.priceTickUnits,
                        scaleUnits: scale,
                      ) ??
                      0,
          );
        })
        .where(_validDraft)
        .toList();
  }

  bool _validDraft(TriggerOrderDraft draft) {
    if (draft.quantitySteps <= 0 ||
        (draft.orderType == 'LIMIT' && draft.priceTicks <= 0)) {
      return false;
    }
    if (draft.triggerType == 'TRAILING_STOP') {
      if (draft.orderType != 'MARKET') return false;
      final callbackRate = draft.callbackRatePpm;
      return draft.triggerPriceTicks >= 0 &&
          (draft.activationPriceTicks == null ||
              draft.activationPriceTicks! >= 0) &&
          callbackRate != null &&
          callbackRate >= 1000 &&
          callbackRate <= 100000;
    }
    return draft.triggerPriceTicks > 0;
  }

  Future<void> submit() async {
    final drafts = _drafts();
    if (drafts.isEmpty || drafts.length != levels.length || submitting) return;
    final submittedIds = levels.map((level) => level.id).toList();
    final before = widget.state.pendingTradingCommand;
    final owner = widget.state.userId;
    final instrument = widget.state.selectedInstrument;
    setState(() => submitting = true);
    final submitted = oco
        ? await widget.state.placeOco(drafts)
        : await widget.state.placeTriggerOrders(drafts);
    if (mounted) {
      // A sent-but-unconfirmed tier belongs to the durable request, never to a
      // new draft submission. Unsent tiers remain available after confirmation.
      final pending = widget.state.pendingTradingCommand;
      final movedToRecovery =
          pending != null &&
              pending != before &&
              pending.userId == owner &&
              pending.instrumentId == instrument.instrumentId &&
              widget.state.userId == owner
          ? (pending.clientTriggerOrderId != null
                ? 1
                : oco && pending.ocoTakeProfitClientId != null
                ? submittedIds.length
                : 0)
          : 0;
      setState(() {
        levels.removeWhere(
          (level) =>
              submittedIds.take(submitted + movedToRecovery).contains(level.id),
        );
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _drafts().length;
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: LText(
                  '条件单',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (!oco)
                IconButton.filledTonal(
                  tooltip: clientLabel(context, '新增止盈'),
                  onPressed: () => addLevel('TAKE_PROFIT'),
                  icon: const Icon(Icons.add_chart, size: 18),
                ),
              const SizedBox(width: 6),
              if (!oco)
                IconButton.filledTonal(
                  tooltip: clientLabel(context, '新增止损'),
                  onPressed: () => addLevel('STOP_LOSS'),
                  icon: const Icon(Icons.add_alert, size: 18),
                ),
              const SizedBox(width: 6),
              if (!oco)
                IconButton.filledTonal(
                  tooltip: clientLabel(context, '新增追踪止损'),
                  onPressed: () => addLevel('TRAILING_STOP'),
                  icon: const Icon(Icons.timeline, size: 18),
                ),
            ],
          ),
          if (widget.state.selectedInstrument.mode.isDerivative) ...[
            const SizedBox(height: 8),
            SmallDropdown(
              value: oco ? 'OCO' : 'SINGLE',
              values: const ['SINGLE', 'OCO'],
              labelBuilder: (v) => v == 'OCO' ? 'TP/SL 双腿 OCO' : '独立条件单',
              enabled: !submitting && !widget.state.tradingCommandPending,
              onChanged: (v) {
                setState(() {
                  oco = v == 'OCO';
                  levels.clear();
                });
                if (oco) {
                  addLevel('TAKE_PROFIT');
                  addLevel('STOP_LOSS');
                }
              },
            ),
            if (oco)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LText('双腿一起接受；一腿触发提交减仓委托，另一腿撤销。触发不保证成交。'),
              ),
            if (!oco)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: LText('逐档提交；结果待确认时停止后续发送。已发档位移出草稿，请查询原请求。'),
              ),
          ],
          const SizedBox(height: 6),
          SmallDropdown(
            value: priceSource,
            values: const ['MARK', 'LAST', 'INDEX'],
            labelBuilder: (v) => '触发源：${triggerPriceSourceLabel(v)}',
            enabled: !submitting,
            onChanged: (v) => setState(() => priceSource = v),
          ),
          if (levels.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: LText(
                '暂无待提交档位',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final level in levels) _levelRow(level),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ClientColors.warning,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(38),
              ),
              onPressed:
                  validCount == 0 ||
                      validCount != levels.length ||
                      submitting ||
                      widget.state.tradingCommandPending ||
                      !widget.state.selectedInstrument.canPlaceTrigger()
                  ? null
                  : submit,
              icon: Icon(
                submitting ? Icons.hourglass_top : Icons.notifications,
              ),
              label: LText(
                submitting
                    ? '提交中'
                    : oco
                    ? '一起提交 TP/SL'
                    : '提交 $validCount 档',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelRow(_TriggerLevelInput level) {
    return AbsorbPointer(
      absorbing: submitting,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ClientColors.border),
          color: ClientColors.surfaceRaised,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SmallDropdown(
                    value: level.triggerType,
                    values: const ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP'],
                    labelBuilder: triggerTypeLabel,
                    enabled: !oco,
                    onChanged: (value) => setState(() {
                      level.triggerType = value;
                      if (value == 'TRAILING_STOP') {
                        level.orderType = 'MARKET';
                        level.triggerPriceTicks = '0';
                        if (level.activationPriceTicks.isEmpty) {
                          level.activationPriceTicks = _defaultTriggerPrice();
                        }
                        if (level.callbackRatePpm.isEmpty) {
                          level.callbackRatePpm = '0.1';
                        }
                      } else {
                        if (level.triggerPriceTicks == '0') {
                          level.triggerPriceTicks = _defaultTriggerPrice();
                        }
                        level.activationPriceTicks = '';
                        level.callbackRatePpm = '';
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SmallDropdown(
                    value: level.closeTarget,
                    values: const ['LONG', 'SHORT'],
                    labelBuilder: (value) => value == 'LONG' ? '平多' : '平空',
                    onChanged: (value) => setState(() {
                      if (oco) {
                        for (final item in levels) {
                          item.closeTarget = value;
                        }
                      } else {
                        level.closeTarget = value;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: clientLabel(context, '删除'),
                  onPressed: oco
                      ? null
                      : () => setState(() => levels.remove(level)),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LText(
              level.triggerType == 'TRAILING_STOP'
                  ? '激活后按回调比例触发平仓'
                  : '${triggerPriceSourceLabel(priceSource)} ${(level.triggerType == 'TAKE_PROFIT') == (level.closeTarget == 'LONG') ? '≥' : '≤'} 触发价时提交${level.orderType == 'MARKET' ? '市价' : '限价'}减仓委托',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: ValueKey('${level.id}-price'),
                    initialValue: level.triggerPriceTicks,
                    label: clientLabel(
                      context,
                      '触发价 (${widget.state.selectedInstrument.quoteAsset})',
                    ),
                    onChanged: (value) =>
                        setState(() => level.triggerPriceTicks = value),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: oco && level != levels.first
                      ? LText('平仓数量（张）\n${level.quantitySteps} · 两腿共用')
                      : AppTextField(
                          key: ValueKey('${level.id}-quantity'),
                          initialValue: level.quantitySteps,
                          label: clientLabel(context, '平仓数量（张）'),
                          onChanged: (value) => setState(() {
                            if (oco) {
                              for (final item in levels) {
                                item.quantitySteps = value;
                              }
                            } else {
                              level.quantitySteps = value;
                            }
                          }),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SmallDropdown(
              value: level.orderType,
              values: level.triggerType == 'TRAILING_STOP'
                  ? const ['MARKET']
                  : const ['MARKET', 'LIMIT'],
              labelBuilder: (v) => v == 'MARKET' ? '触发后市价执行' : '触发后限价执行',
              onChanged: (v) => setState(() => level.orderType = v),
            ),
            if (level.orderType == 'LIMIT') ...[
              const SizedBox(height: 8),
              AppTextField(
                key: ValueKey('${level.id}-limit'),
                initialValue: level.limitPrice,
                label: clientLabel(
                  context,
                  '委托限价 (${widget.state.selectedInstrument.quoteAsset})',
                ),
                onChanged: (v) => setState(() => level.limitPrice = v),
              ),
            ],
            if (level.triggerType == 'TRAILING_STOP') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      key: ValueKey('${level.id}-activation'),
                      initialValue: level.activationPriceTicks,
                      label: clientLabel(context, '激活价格'),
                      onChanged: (value) =>
                          setState(() => level.activationPriceTicks = value),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppTextField(
                      key: ValueKey('${level.id}-callback'),
                      initialValue: level.callbackRatePpm,
                      label: clientLabel(context, '回调比例 (%)'),
                      onChanged: (value) =>
                          setState(() => level.callbackRatePpm = value),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TriggerLevelInput {
  _TriggerLevelInput({
    required this.id,
    required this.triggerType,
    required this.closeTarget,
    required this.triggerPriceTicks,
    required this.activationPriceTicks,
    required this.callbackRatePpm,
    required this.quantitySteps,
  });

  final String id;
  String triggerType;
  String closeTarget;
  String triggerPriceTicks;
  String orderType = 'MARKET';
  String limitPrice = '';
  String activationPriceTicks;
  String callbackRatePpm;
  String quantitySteps;
}
