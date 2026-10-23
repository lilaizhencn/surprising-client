import 'trading_details.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../account_records.dart' show formatExecutionPrice;
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../funding_records_page.dart';
import '../models.dart';
import '../spot_algo_order_sheet.dart';
import '../spot_amend_order_sheet.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';

Future<void> confirmSpotCancellation(
  BuildContext context,
  AppState state,
) async {
  final user = state.userId,
      onlyCurrent = state.onlyCurrentTradingPair,
      symbol = state.selectedSymbol;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(onlyCurrent ? '撤销 $symbol 当前委托？' : '撤销全部现货委托？'),
      content: const Text('只处理本次读取到的委托。部分成交或已结束的订单可能无法撤销，请查看逐项结果。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('确认撤单'),
        ),
      ],
    ),
  );
  if (accepted == true &&
      context.mounted &&
      state.userId == user &&
      state.mode == ProductMode.spot &&
      (!onlyCurrent || state.selectedSymbol == symbol)) {
    await state.cancelOpenSpotOrders(onlyCurrentPair: onlyCurrent);
  }
}

class PrivateTradingPanel extends StatefulWidget {
  const PrivateTradingPanel({required this.state, super.key});

  final AppState state;

  @override
  State<PrivateTradingPanel> createState() => _PrivateTradingPanelState();
}

class _PrivateTradingPanelState extends State<PrivateTradingPanel> {
  int tab = 0;
  (ProductMode, int?)? _selectionScope;
  AppState get state => widget.state;
  @override
  Widget build(BuildContext context) {
    // AppState is mutable; compare the last rendered owner rather than oldWidget.state.
    final scope = (state.mode, state.userId);
    if (_selectionScope != scope) {
      _selectionScope = scope;
      tab = state.mode.isSpot ? 1 : 0;
    }
    final algoOrders = state.visibleAlgoOrders;
    final risk = state.accountRisk;
    String riskAmount(int units) {
      final asset = risk!.settleAsset;
      final text = scaledAmount(
        BigInt.from(units),
        state.assetScaleUnits(asset),
      );
      return text == '--' ? text : '$text $asset';
    }

    final botCount = algoOrders.length + state.openTriggerOrders.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.mode.isSpot && state.isLoggedIn)
          Wrap(
            spacing: 8,
            children: [
              for (final item in const {
                'order': '历史委托',
                'trade': '成交记录',
              }.entries)
                TextButton.icon(
                  key: ValueKey('spot-history-${item.key}'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FundingRecordsPage(
                        state: state,
                        initialCategory: item.key,
                        initialInstrumentId: state.onlyCurrentTradingPair
                            ? state.selectedInstrument.instrumentId
                            : '',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: Text(item.value),
                ),
            ],
          ),
        if (state.pendingTradingCommand?.cancelOrderId != null ||
            state.pendingTradingCommand?.amendRequestId != null ||
            state.pendingTradingCommand?.cancelPlan != null) ...[
          Text(tradingPendingMessage(state.pendingTradingCommand)),
          TextButton(
            onPressed: state.submittingOrder
                ? null
                : state.checkPendingTradingCommand,
            child: Text(tradingRecoveryLabel(state.pendingTradingCommand)),
          ),
        ],
        if (state.isLoggedIn &&
            !(state.privateViews[state.mode]?.ready ?? false))
          const Text('账户同步中 / Syncing account'),
        if (!state.mode.isSpot && state.isLoggedIn && risk != null)
          Panel(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '权益',
                    value: riskAmount(risk.equityUnits),
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '维持保证金',
                    value: riskAmount(risk.maintenanceMarginUnits),
                    color: ClientColors.warning,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '保证金率',
                    value: percentageFromPpm(risk.marginRatioPpm),
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        if (!state.mode.isSpot && state.isLoggedIn && risk == null)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                state.privateViews[state.mode]?.ready != true
                    ? '账户风险等待账户同步'
                    : state.loadingAccountRisk
                    ? '账户风险加载中…'
                    : state.accountRiskError ?? '账户风险尚未同步',
              ),
              TextButton(
                onPressed:
                    state.loadingAccountRisk ||
                        state.privateViews[state.mode]?.ready != true
                    ? null
                    : state.refreshRiskDetails,
                child: const Text('刷新风险'),
              ),
            ],
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in [
                if (!state.mode.isSpot) (0, '持仓 (${state.positions.length})'),
                (1, '当前委托 (${state.openOrders.length})'),
                (2, '止盈止损 / 策略 ($botCount)'),
                (3, '最近订单更新'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.$2),
                    selected: tab == entry.$1,
                    onSelected: (_) {
                      setState(() => tab = entry.$1);
                      if (entry.$1 == 0) {
                        unawaited(state.refreshRiskDetails());
                      }
                      if (entry.$1 == 2) unawaited(state.refreshAlgoOrders());
                    },
                  ),
                ),
            ],
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('仅当前交易对'),
          value: state.onlyCurrentTradingPair,
          onChanged: (value) => state.setTradingPairFilter(value ?? true),
        ),
        if (tab == 3) ...[
          const Text('本次连接收到的最近 100 条订单更新'),
          if (state.recentOrderUpdates.isEmpty)
            const TradingEmptyState(text: '暂无订单更新'),
          for (final order in state.recentOrderUpdates)
            OrderRow(
              order: order,
              instrument:
                  state.instruments
                      .where(
                        (i) => i.mode == state.mode && i.symbol == order.symbol,
                      )
                      .firstOrNull ??
                  Instrument.empty(state.mode),
              onAmend:
                  !state.mode.isSpot ||
                      state.submittingOrder ||
                      state.tradingCommandPending
                  ? null
                  : () {
                      final instrument = state.instruments
                          .where(
                            (i) =>
                                i.mode == state.mode &&
                                i.symbol == order.symbol,
                          )
                          .firstOrNull;
                      if (instrument != null) {
                        showSpotAmendOrderSheet(
                          context,
                          state,
                          order,
                          instrument,
                        );
                      }
                    },
              onCancel: state.submittingOrder || state.tradingCommandPending
                  ? null
                  : () => state.cancelOrder(order),
            ),
        ],
        if (!state.isLoggedIn)
          TextButton(
            onPressed: () => showAuthSheet(context),
            child: Text(state.mode.isSpot ? '登录查看账户与委托' : '登录查看持仓与委托'),
          ),
        if (tab == 0) ...[
          if (state.positions.isEmpty)
            const TradingEmptyState(text: '暂无仓位')
          else
            ...state.positions.map(
              (position) => PositionRow(position: position, state: state),
            ),
        ],
        if (tab == 1 && state.mode == ProductMode.spot && state.isLoggedIn) ...[
          OutlinedButton(
            onPressed: state.submittingOrder || state.tradingCommandPending
                ? null
                : () => confirmSpotCancellation(context, state),
            child: Text(
              state.onlyCurrentTradingPair ? '撤销当前交易对委托' : '撤销全部现货委托',
            ),
          ),
          if (state.lastCancellationResult?.userId == state.userId) ...[
            Text(
              '已处理 ${state.lastCancellationResult!.requested} 笔，成功 ${state.lastCancellationResult!.completed} 笔，失败 ${state.lastCancellationResult!.failed} 笔',
            ),
            if (state.lastCancellationResult!.failed > 0)
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => AnimatedBuilder(
                    animation: state,
                    builder: (context, _) {
                      final result = state.lastCancellationResult;
                      if (result == null || result.userId != state.userId) {
                        return const SafeArea(child: Text('账户已变化，请关闭此窗口'));
                      }
                      return SafeArea(
                        child: ListView.builder(
                          itemCount: result.failures.length,
                          itemBuilder: (context, i) {
                            final failure = result.failures[i];
                            return ListTile(
                              title: Text('订单 #${failure.orderId}'),
                              subtitle: Text(
                                failure.code == 'ORDER_NOT_FOUND'
                                    ? '订单不存在或已结束'
                                    : failure.code == 'ORDER_OWNER_MISMATCH'
                                    ? '批次包含其他账户订单，未执行该批'
                                    : '撤单未被接受，请查看最新订单状态',
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                child: const Text('查看失败订单'),
              ),
          ],
        ],
        if (tab == 1 && state.openOrders.isEmpty)
          const TradingEmptyState(text: '暂无委托'),
        if (tab == 1 && state.openOrders.isNotEmpty) ...[
          const SectionTitle(title: '当前委托'),
          ...state.openOrders.map(
            (order) => OrderRow(
              order: order,
              instrument:
                  state.instruments
                      .where(
                        (i) => i.mode == state.mode && i.symbol == order.symbol,
                      )
                      .firstOrNull ??
                  Instrument.empty(state.mode),
              onAmend:
                  !state.mode.isSpot ||
                      state.submittingOrder ||
                      state.tradingCommandPending
                  ? null
                  : () {
                      final instrument = state.instruments
                          .where(
                            (i) =>
                                i.mode == state.mode &&
                                i.symbol == order.symbol,
                          )
                          .firstOrNull;
                      if (instrument != null) {
                        showSpotAmendOrderSheet(
                          context,
                          state,
                          order,
                          instrument,
                        );
                      }
                    },
              onCancel: state.submittingOrder || state.tradingCommandPending
                  ? null
                  : () => state.cancelOrder(order),
            ),
          ),
          if (state.openOrdersHasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: state.loadingMoreOpenOrders
                    ? null
                    : state.loadMoreOpenOrders,
                icon: const Icon(Icons.expand_more),
                label: Text(state.loadingMoreOpenOrders ? '加载中...' : '加载更多委托'),
              ),
            ),
        ],
        if (tab == 2 && state.isLoggedIn) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  '算法委托',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (state.mode.isSpot)
                TextButton.icon(
                  key: const ValueKey('create-spot-algo-order'),
                  onPressed: state.submittingOrder
                      ? null
                      : () => showSpotAlgoOrderSheet(context, state),
                  icon: const Icon(Icons.add),
                  label: const Text('创建策略'),
                ),
              TextButton.icon(
                key: const ValueKey('refresh-algo-orders'),
                onPressed: state.loadingAlgoOrders
                    ? null
                    : state.refreshAlgoOrders,
                icon: const Icon(Icons.refresh),
                label: Text(state.loadingAlgoOrders ? '加载中' : '刷新策略'),
              ),
            ],
          ),
          if (state.loadingAlgoOrders) const LinearProgressIndicator(),
          if (state.algoOrdersError != null)
            Text(
              state.algoOrdersError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (algoOrders.length == 1000)
            const Text('已显示最近 1000 笔未完成策略，请按交易对筛选'),
        ],
        if (tab == 2 &&
            botCount == 0 &&
            !state.loadingAlgoOrders &&
            state.algoOrdersError == null)
          const TradingEmptyState(text: '暂无止盈止损或策略委托'),
        if (tab == 2 && algoOrders.isNotEmpty) ...[
          ...algoOrders.map(
            (order) => AlgoOrderRow(
              order: order,
              state: state,
              onCancel:
                  state.submittingOrder ||
                      state.tradingCommandPending ||
                      state.loadingAlgoOrders
                  ? null
                  : () => state.cancelAlgoOrder(order),
            ),
          ),
        ],
        if (tab == 2 && state.openTriggerOrders.isNotEmpty) ...[
          const SectionTitle(title: '止盈止损'),
          ...state.openTriggerOrders.map(
            (order) => TriggerOrderRow(
              order: order,
              state: state,
              onCancel: () => state.cancelTriggerOrder(order),
            ),
          ),
        ],
        if (tab == 0 && state.liquidationOrders.isNotEmpty) ...[
          const SectionTitle(title: '爆仓记录'),
          ...state.liquidationOrders.map(
            (order) => Panel(
              child: InfoLine(
                label: '#${order.orderId} ${order.symbol}',
                value: '${order.status} · ${order.quantitySteps}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class TradingPanelTabs extends StatelessWidget {
  const TradingPanelTabs({
    required this.positionCount,
    required this.orderCount,
    required this.botCount,
    super.key,
  });

  final int positionCount;
  final int orderCount;
  final int botCount;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      '持有仓位 ($positionCount)',
      '当前委托 ($orderCount)',
      '交易机器人${botCount > 0 ? ' ($botCount)' : ''}',
    ];
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabs[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: index == 0 ? 24 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: ClientColors.warning,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
            if (index != tabs.length - 1) const SizedBox(width: 10),
          ],
          IconButton(
            tooltip: '订单筛选',
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              side: BorderSide.none,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.document_scanner_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class TradingEmptyState extends StatelessWidget {
  const TradingEmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.content_paste_search_outlined,
            size: 38,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: .62),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderRow extends StatelessWidget {
  const OrderRow({
    required this.order,
    required this.instrument,
    required this.onCancel,
    this.onAmend,
    super.key,
  });
  final OrderModel order;
  final Instrument instrument;
  final VoidCallback? onCancel;
  final VoidCallback? onAmend;
  @override
  Widget build(BuildContext context) {
    final multiplier = instrument.notionalMultiplierUnits;
    final linear =
        instrument.mode == ProductMode.linear ||
        instrument.mode == ProductMode.linearDelivery;
    final executed = BigInt.tryParse(order.executedValueTicks ?? '');
    final hasNotional =
        (instrument.isSpot || linear) && multiplier != null && multiplier > 0;
    final canCancel = [
      'OPEN',
      'NEW',
      'ACCEPTED',
      'PARTIALLY_FILLED',
      'PENDING_RESERVE',
    ].contains(order.status);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.side == 'BUY' ? '买入' : '卖出'} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: order.side == 'BUY'
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              if (canCancel &&
                  order.orderType == 'LIMIT' &&
                  order.status != 'PENDING_RESERVE' &&
                  onAmend != null)
                TextButton(onPressed: onAmend, child: const Text('改单')),
              if (canCancel && onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('撤单')),
            ],
          ),
          Text(
            instrument.isSpot
                ? '${order.orderType == 'MARKET' ? '市价' : '限价'} · ${tradingStatus(order)}'
                : '${order.orderType} · ${order.marginMode == 'ISOLATED' ? '逐仓' : '全仓'} · ${positionSideLabel(order.positionSide)} · ${tradingStatus(order)}',
          ),
          const SizedBox(height: 10),
          TradingDetails(
            values: {
              '委托价格': order.orderType == 'MARKET'
                  ? '市价'
                  : formatExecutionPrice(
                      order.priceTicks,
                      instrument.priceTickUnits,
                      instrument.quoteScaleUnits?.toString(),
                    ),
              '成交均价': order.executedQuantitySteps == 0
                  ? '—'
                  : formatExecutionPrice(
                      order.averagePriceTicks,
                      instrument.priceTickUnits,
                      instrument.quoteScaleUnits?.toString(),
                    ),
              '委托数量': tradingQuantity(instrument, order.quantitySteps),
              '已成交数量': tradingQuantity(instrument, order.executedQuantitySteps),
              '剩余数量': tradingQuantity(instrument, order.remainingQuantitySteps),
              '成交进度': order.fillProgress,
              '委托价值': !hasNotional || order.orderType == 'MARKET'
                  ? '--'
                  : tradingAmount(
                      BigInt.from(order.priceTicks) *
                          BigInt.from(order.quantitySteps) *
                          BigInt.from(multiplier),
                      instrument,
                    ),
              '成交价值': !hasNotional || executed == null
                  ? '--'
                  : tradingAmount(
                      executed * BigInt.from(multiplier),
                      instrument,
                    ),
              '累计手续费': tradingAmount(order.cumulativeFeeUnits, instrument),
              if (instrument.isSpot)
                '计价币种': instrument.quoteAsset
              else
                '结算币种': instrument.settleAsset,
              if (instrument.isSpot)
                '只做 Maker': order.postOnly ? '是' : '否'
              else
                '只减仓 / 只做 Maker':
                    '${order.reduceOnly ? '是' : '否'} / ${order.postOnly ? '是' : '否'}',
              '有效方式': order.timeInForce,
              '委托时间': tradingTime(order.createdAt),
              '更新时间': tradingTime(order.updatedAt),
              '订单编号': '${order.orderId}',
            },
          ),
        ],
      ),
    );
  }
}

class AlgoOrderRow extends StatelessWidget {
  const AlgoOrderRow({
    required this.order,
    required this.state,
    required this.onCancel,
    super.key,
  });

  final AlgoOrderModel order;
  final AppState state;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final instrument = state.algoInstrumentFor(order);
    final priceText = order.priceTicks > 0
        ? formatExecutionPrice(
            order.priceTicks,
            instrument?.priceTickUnits,
            instrument?.quoteScaleUnits?.toString(),
          )
        : '市价';
    String quantity(int steps) =>
        instrument == null ? '—' : tradingQuantity(instrument, steps);
    final status =
        const {
          'PENDING': '待运行',
          'RUNNING': '运行中',
          'CANCEL_REQUESTED': '取消中',
          'CANCELED': '已撤销',
          'COMPLETED': '已完成',
          'FAILED': '失败',
        }[order.status] ??
        order.status;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${algoTypeLabel(order.algoType)} · ${order.side == 'BUY' ? '买入' : '卖出'} · ${instrument?.symbol ?? '#${order.instrumentId}'}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: order.side == 'BUY'
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          Text(
            '#${order.algoOrderId} · $status',
            style: const TextStyle(fontSize: 12),
          ),
          if (instrument == null) const Text('合约资料未就绪，暂不显示价格和数量'),
          Text(
            '${order.product.isSpot ? '现货' : '${order.marginMode} ${positionSideLabel(order.positionSide)}'} · ${order.timeInForce}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          Text(
            '价格：$priceText${instrument == null || order.priceTicks == 0 ? '' : ' ${instrument.quoteAsset}'}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '已成交：${quantity(order.executedQuantitySteps)} / 总量：${quantity(order.quantitySteps)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '挂单中：${quantity(order.activeQuantitySteps)} · 每片：${quantity(order.childQuantitySteps)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '${order.algoType == 'TWAP' ? '间隔 ${order.intervalSeconds} 秒 · ' : ''}'
            '时长 ${order.durationSeconds} 秒 · 已提交 ${order.childOrderCount} 片',
            style: const TextStyle(fontSize: 12),
          ),
          if (order.rejectReason != null && order.rejectReason!.isNotEmpty)
            Text(
              order.rejectReason!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              label: Text(order.status == 'CANCEL_REQUESTED' ? '继续撤销' : '撤销策略'),
            ),
          ),
        ],
      ),
    );
  }
}

class TriggerOrderRow extends StatelessWidget {
  const TriggerOrderRow({
    required this.order,
    required this.state,
    required this.onCancel,
    super.key,
  });

  final TriggerOrderModel order;
  final AppState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final instrument = state.instruments.firstWhere(
      (item) =>
          item.mode == state.mode &&
          (item.instrumentId == order.instrumentId ||
              item.symbol == order.symbol),
      orElse: () => state.selectedInstrument,
    );
    final isTakeProfit = order.triggerType == 'TAKE_PROFIT';
    final triggerText = order.triggerType == 'TRAILING_STOP'
        ? '激活 ${order.activationPriceTicks == null ? '立即' : money(instrument.priceFromTicks(order.activationPriceTicks!), digits: instrument.pricePrecision)} / 回调 ${((order.callbackRatePpm ?? 0) / 10000).toStringAsFixed(2)}%'
        : '${triggerPriceSourceLabel(order.priceSource)}触发 ${money(instrument.priceFromTicks(order.triggerPriceTicks), digits: instrument.pricePrecision)}';
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.ocoGroupId == null ? '' : 'OCO · '}${triggerTypeLabel(order.triggerType)} ${instrument.displayName}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isTakeProfit
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                Text(
                  '${triggerCloseLabel(order.side, order.positionSide)} · ${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.status}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$triggerText · 量 ${order.quantitySteps}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  order.orderType == 'LIMIT'
                      ? '触发后限价 ${scaledAmount(BigInt.from(order.priceTicks) * BigInt.from(instrument.priceTickUnits), instrument.quoteScaleUnits)} ${instrument.quoteAsset} · ${order.timeInForce}'
                      : '触发后市价 · ${order.timeInForce}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed:
                state.submittingOrder ||
                    state.submittingTriggers ||
                    state.tradingCommandPending ||
                    order.status != 'PENDING'
                ? null
                : onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class PositionRow extends StatelessWidget {
  const PositionRow({required this.position, required this.state, super.key});
  final Position position;
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final instrument =
        state.instruments
            .where((i) => i.mode == state.mode && i.symbol == position.symbol)
            .firstOrNull ??
        Instrument.empty(state.mode);
    final view = state.privateViews[state.mode];
    final risk = view?.ready == true
        ? state.positionRisks
              .where(
                (r) =>
                    r.symbol == position.symbol &&
                    r.positionSide == position.positionSide,
              )
              .firstOrNull
        : null;
    final queriedRisk = state.queriedPositionRisks
        .where(
          (r) =>
              r.symbol == position.symbol &&
              r.positionSide == position.positionSide,
        )
        .firstOrNull;
    final leverage = view
        ?.rows('leverage')
        .where(
          (r) =>
              (r['instrumentId'] == instrument.instrumentId ||
                  r['symbol'] == instrument.symbol) &&
              r['marginMode'] == position.marginMode,
        )
        .firstOrNull;
    final mark = state.markTicksFor(instrument);
    final leveragePpm = parseInt64(leverage?['leveragePpm']);
    final pnl = state.unrealizedPnlFor(position) ?? risk?.unrealizedPnlUnits;
    final triggers =
        view
            ?.rows('trigger')
            .where(
              (r) =>
                  r['symbol'] == position.symbol &&
                  r['positionSide'] == position.positionSide,
            )
            .toList() ??
        [];
    String price(int? ticks) =>
        ticks == null || ticks <= 0 || instrument.symbol.isEmpty
        ? '--'
        : formatExecutionPrice(
            ticks,
            instrument.priceTickUnits,
            instrument.quoteScaleUnits?.toString(),
          );
    final asset = position.marginAsset.isEmpty
        ? instrument.settleAsset
        : position.marginAsset;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${position.symbol} ${position.isLong ? '多' : '空'}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: position.isLong
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              Chip(
                label: Text(
                  '${position.marginMode == 'ISOLATED' ? '逐仓' : '全仓'} · ${positionSideLabel(position.positionSide)}',
                ),
                visualDensity: VisualDensity.compact,
              ),
              TextButton.icon(
                onPressed: () => unawaited(state.closePosition(position)),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('平仓'),
              ),
            ],
          ),
          TradingDetails(
            values: {
              '持仓数量': tradingQuantity(
                instrument,
                position.signedQuantitySteps,
                absolute: true,
              ),
              if (!instrument.isOption)
                '杠杆': leveragePpm == null || leveragePpm <= 0
                    ? '--'
                    : '${scaledAmount(BigInt.from(leveragePpm), 1000000)}×',
              '开仓均价': price(position.entryPriceTicks),
              '标记价格': price(mark),
              '未实现盈亏': tradingAmount(pnl, instrument, asset),
              '已实现盈亏': tradingAmount(
                position.realizedPnlUnits,
                instrument,
                asset,
              ),
              '持仓保证金': tradingAmount(
                position.positionMarginUnits,
                instrument,
                asset,
              ),
              '维持保证金': tradingAmount(
                risk?.maintenanceMarginUnits,
                instrument,
                asset,
              ),
              '保证金率': risk?.marginRatioPpm == null
                  ? '--'
                  : percentageFromPpm(risk!.marginRatioPpm!),
              '强平价格（快照）': price(queriedRisk?.liquidationPriceTicks),
              '风险状态': risk?.status ?? '风险数据同步中',
              '止盈止损': view?.ready != true
                  ? '同步中'
                  : triggers.isEmpty
                  ? '未设置'
                  : triggers
                        .map(
                          (r) =>
                              '${triggerTypeLabel(asString(r['triggerType']))} ${price(parseInt64(r['triggerPriceTicks']))}',
                        )
                        .join(' / '),
            },
          ),
        ],
      ),
    );
  }
}
