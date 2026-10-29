import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../auth/auth_sheet.dart';
import '../market/market_chart.dart';
import '../models.dart';
import 'advanced_orders.dart';
import 'contract_settings.dart';
import 'order_book.dart';
import 'order_ticket.dart';
import 'private_trading.dart';

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final priceController = TextEditingController();
  final quantityController = TextEditingController();
  String side = 'BUY';
  String orderType = 'LIMIT';
  String timeInForce = 'GTC';
  String marginMode = 'CROSS';
  String positionSide = 'NET';
  bool reduceOnly = false;
  bool postOnly = false;
  bool bboEnabled = false;
  String bboPriceMode = 'OPPONENT_1';
  bool priceInitialized = false;

  @override
  void dispose() {
    priceController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final instrument = state.selectedInstrument;
    if (instrument.symbol.isEmpty) {
      return Column(
        children: [
          ProductLineTabs(
            value: state.mode,
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await state.refreshInstruments();
                await state.selectMode(state.mode);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const SizedBox(height: 40),
                  Text(
                    '${state.mode.label}暂无可交易合约',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text('可切换其他产品，或下拉刷新合约列表。', textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final latestPrice = state.latestPriceFor(instrument);
    if (state.orderBook.bids.isNotEmpty && !priceInitialized) {
      priceInitialized = true;
      priceController.text = scaledAmount(
        BigInt.from(state.orderBook.bids.first.priceTicks) *
            BigInt.from(instrument.priceTickUnits),
        instrument.quoteScaleUnits,
      );
    }
    return Column(
      children: [
        ProductLineTabs(
          value: state.mode,
          onChanged: (mode) => unawaited(state.selectMode(mode)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await state.refreshPublicData();
              await state.refreshPrivateData();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
              children: [
                TradeSymbolHeader(
                  instrument: instrument,
                  latestPrice: latestPrice,
                  onChart: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MarketChartPage(),
                    ),
                  ),
                  onRefresh: state.refreshPublicData,
                ),
                if (instrument.isDelivery || instrument.isOption) ...[
                  const SizedBox(height: 6),
                  ProductLifecyclePanel(
                    state: state,
                    instrument: instrument,
                    latestPrice: latestPrice,
                  ),
                ],
                if (instrument.isDerivative) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text(
                          '最新价 ${latestPrice == null ? '--' : money(latestPrice, digits: instrument.pricePrecision)}',
                        ),
                        Text(
                          '标记价 ${state.markPrices['${state.mode.productLine}:${instrument.symbol}'] == null ? '--' : money(instrument.priceFromTicks(state.markPrices['${state.mode.productLine}:${instrument.symbol}']!), digits: instrument.pricePrecision)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ContractQuickSettings(
                    marginMode: marginMode,
                    showLeverage: !instrument.isOption,
                    leverage:
                        '${(instrument.maxLeveragePpm / 1000000).round()}x',
                    positionMode: state.positionMode,
                    onMarginMode: (value) => setState(() => marginMode = value),
                    onPositionMode: (mode) =>
                        unawaited(state.changePositionMode(mode)),
                  ),
                ],
                const SizedBox(height: 6),
                SymbolStrip(
                  instruments: state.visibleInstruments,
                  selected: state.selectedSymbol,
                  onSelected: (symbol) => unawaited(state.selectSymbol(symbol)),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final entry = SizedBox(
                      height: 376,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 12,
                            child: OrderTicket(
                              side: side,
                              orderType: orderType,
                              timeInForce: timeInForce,
                              marginMode: marginMode,
                              positionMode: state.positionMode,
                              positionSide: positionSide,
                              reduceOnly: reduceOnly,
                              postOnly: postOnly,
                              bboEnabled: bboEnabled,
                              bboPriceMode: bboPriceMode,
                              onBboEnabled: (value) =>
                                  setState(() => bboEnabled = value),
                              onBboPriceMode: (value) =>
                                  setState(() => bboPriceMode = value),
                              priceController: priceController,
                              quantityController: quantityController,
                              instrument: instrument,
                              loggedIn: state.isLoggedIn,
                              onSide: (value) => setState(() => side = value),
                              onOrderType: (value) => setState(() {
                                orderType = value;
                                postOnly = false;
                                bboEnabled = false;
                                timeInForce = value == 'MARKET' ? 'IOC' : 'GTC';
                              }),
                              onTimeInForce: (value) => setState(() {
                                timeInForce = value;
                                postOnly = value == 'GTX';
                              }),
                              onMarginMode: (value) =>
                                  setState(() => marginMode = value),
                              onPositionSide: (value) =>
                                  setState(() => positionSide = value),
                              onReduceOnly: (value) =>
                                  setState(() => reduceOnly = value),
                              onPostOnly: (value) => setState(() {
                                postOnly = value;
                                timeInForce = value ? 'GTX' : 'GTC';
                              }),
                              onSubmit: () {
                                if (state.submittingOrder) return;
                                if (!state.isLoggedIn) {
                                  showAuthSheet(context);
                                  return;
                                }
                                if (orderType != 'MARKET' &&
                                    !bboEnabled &&
                                    instrument.priceTicksFromText(
                                          priceController.text,
                                        ) ==
                                        null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('价格必须符合最小价格变动'),
                                    ),
                                  );
                                  return;
                                }
                                unawaited(
                                  state.placeOrder(
                                    side: side,
                                    orderType: orderType,
                                    timeInForce: timeInForce,
                                    price:
                                        double.tryParse(priceController.text) ??
                                        0,
                                    priceText: priceController.text,
                                    quantitySteps: instrument.isSpot
                                        ? decimalIncrement(
                                                quantityController.text,
                                                instrument.quantityStepUnits,
                                                scaleUnits:
                                                    instrument.baseScaleUnits ??
                                                    0,
                                              ) ??
                                              0
                                        : int.tryParse(
                                                quantityController.text,
                                              ) ??
                                              0,
                                    marginMode: instrument.isSpot
                                        ? 'CROSS'
                                        : marginMode,
                                    positionSide:
                                        instrument.isSpot ||
                                            state.positionMode == 'ONE_WAY'
                                        ? 'NET'
                                        : positionSide == 'NET'
                                        ? (side == 'SELL' ? 'SHORT' : 'LONG')
                                        : positionSide,
                                    reduceOnly: instrument.isSpot
                                        ? false
                                        : reduceOnly,
                                    postOnly: postOnly,
                                    bboPriceMode:
                                        orderType == 'LIMIT' && bboEnabled
                                        ? bboPriceMode
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 9,
                            child: OrderBookPanel(
                              instrument: instrument,
                              orderBook: state.orderBook,
                              recovering: state.market.depthRecovering,
                              latestPrice: latestPrice,
                              onPrice: (price) {
                                setState(() {
                                  bboEnabled = false;
                                  orderType = 'LIMIT';
                                  timeInForce = 'GTC';
                                  postOnly = false;
                                  priceController.text = price;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                    if (constraints.maxWidth < 1000) return entry;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: KlinePanel(
                            candles: state.candles,
                            period: state.period,
                            onPeriod: (period) =>
                                unawaited(state.selectPeriod(period)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(flex: 7, child: entry),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (state.submittingOrder) const LinearProgressIndicator(),
                RecentTradesPanel(state: state),
                const SizedBox(height: 12),
                PrivateTradingPanel(state: state),
                if (instrument.isDerivative) ...[
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                      childrenPadding: EdgeInsets.zero,
                      collapsedIconColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      iconColor: Theme.of(context).colorScheme.onSurface,
                      title: const Text(
                        '高级委托',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      children: [
                        AlgoOrderPanel(state: state, marginMode: marginMode),
                        const SizedBox(height: 6),
                        TriggerOrderPanel(
                          key: ValueKey(
                            '${state.mode}-${state.selectedSymbol}-$marginMode-${state.positionMode}',
                          ),
                          state: state,
                          marginMode: marginMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                    collapsedIconColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    title: Text(
                      '${instrument.displayName.replaceAll('-', '')} ${instrument.contractLabel} K线图表',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      KlinePanel(
                        candles: state.candles,
                        period: state.period,
                        onPeriod: (period) =>
                            unawaited(state.selectPeriod(period)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProductLineTabs extends StatefulWidget {
  const ProductLineTabs({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final ProductMode value;
  final ValueChanged<ProductMode> onChanged;
  @override
  State<ProductLineTabs> createState() => _ProductLineTabsState();
}

class _ProductLineTabsState extends State<ProductLineTabs> {
  final anchors = {for (final mode in ProductMode.values) mode: GlobalKey()};
  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant ProductLineTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = anchors[widget.value]?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        key: const ValueKey('product-line-tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final mode in ProductMode.values)
              Padding(
                key: anchors[mode],
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('product-tab-${mode.name}'),
                  label: Text(mode.label),
                  selected: widget.value == mode,
                  onSelected: (_) {
                    if (mode != widget.value) widget.onChanged(mode);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
