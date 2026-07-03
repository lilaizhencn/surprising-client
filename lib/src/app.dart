import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kline_chart/kline_chart.dart';

import 'app_state.dart';
import 'models.dart';

const _ink = Color(0xFF1F2430);
const _muted = Color(0xFF7C8598);
const _paper = Color(0xFFFFFBF7);
const _panel = Color(0xFFFFFFFF);
const _line = Color(0xFFE8DFEA);
const _pink = Color(0xFFFF7AB6);
const _violet = Color(0xFF8F7CFF);
const _mint = Color(0xFF00B894);
const _red = Color(0xFFFF5B6E);
const _amber = Color(0xFFFFB84D);

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    required AppState super.notifier,
    required super.child,
    super.key,
  });

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class SurprisingClientApp extends StatefulWidget {
  const SurprisingClientApp({super.key, this.state, this.bootstrap = true});

  final AppState? state;
  final bool bootstrap;

  @override
  State<SurprisingClientApp> createState() => _SurprisingClientAppState();
}

class _SurprisingClientAppState extends State<SurprisingClientApp> {
  late final AppState state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    if (widget.bootstrap) {
      unawaited(state.bootstrap());
    }
  }

  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Surprising',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: _paper,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _pink,
            primary: _pink,
            secondary: _violet,
            tertiary: _mint,
            surface: _panel,
            error: _red,
          ),
          textTheme: const TextTheme(
            titleLarge: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
            titleMedium: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
            bodyMedium: TextStyle(fontSize: 13, color: _ink),
            labelMedium: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
        home: const ClientShell(),
      ),
    );
  }
}

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int index = 0;
  String? seenNotice;
  String? seenError;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _showMessage(context, state);
    final page = switch (index) {
      0 => const HomePage(),
      1 => const MarketsPage(),
      2 => const TradePage(),
      3 => const WalletPage(),
      _ => const ProfilePage(),
    };
    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (next) => setState(() => index = next),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.query_stats_outlined),
            selectedIcon: Icon(Icons.query_stats),
            label: '行情',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_circle_outlined),
            selectedIcon: Icon(Icons.swap_vert_circle),
            label: '交易',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '钱包',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, AppState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final media = MediaQuery.maybeOf(context);
      final size = media?.size;
      if (size == null || size.width <= 0 || size.height <= 0) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      if (state.lastError != null && state.lastError != seenError) {
        seenError = state.lastError;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(content: Text(state.lastError!), backgroundColor: _red),
        );
        return;
      }
      if (state.lastNotice != null && state.lastNotice != seenNotice) {
        seenNotice = state.lastNotice;
        messenger.clearSnackBars();
        messenger.showSnackBar(SnackBar(content: Text(state.lastNotice!)));
      }
    });
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final instrument = state.selectedInstrument;
    final bestBid = state.orderBook.bids.isNotEmpty
        ? state.orderBook.bids.first
        : null;
    final bestAsk = state.orderBook.asks.isNotEmpty
        ? state.orderBook.asks.first
        : null;
    final latestPrice = state.latestPriceFor(instrument);
    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshPublicData();
        await state.refreshPrivateData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              const SparkleMark(size: 44),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Surprising',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _ink,
                      ),
                    ),
                    Text('现货 · U本位 · 币本位', style: TextStyle(color: _muted)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => state.refreshPublicData(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GradientPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instrument.displayName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${instrument.mode.label} · ${instrument.settleAsset}结算',
                        style: const TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        latestPrice == null
                            ? '--'
                            : money(
                                latestPrice,
                                digits: instrument.pricePrecision,
                              ),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: _mint,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MetricPill(
                      label: '买一',
                      value: bestBid == null
                          ? '--'
                          : compactInt(bestBid.quantitySteps),
                      color: _mint,
                    ),
                    const SizedBox(height: 8),
                    MetricPill(
                      label: '卖一',
                      value: bestAsk == null
                          ? '--'
                          : compactInt(bestAsk.quantitySteps),
                      color: _red,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: QuickTile(
                  icon: Icons.candlestick_chart,
                  title: 'K线',
                  value: state.period,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuickTile(
                  icon: Icons.stacked_line_chart,
                  title: '盘口',
                  value: 'L2',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuickTile(
                  icon: Icons.shield_outlined,
                  title: '风控',
                  value: state.accountRisk?.status ?? '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SectionTitle(
            title: '精选交易对',
            action: TextButton(
              onPressed: () => state.refreshInstruments(),
              child: const Text('刷新'),
            ),
          ),
          ...state.instruments
              .take(6)
              .map((item) => InstrumentRow(instrument: item)),
        ],
      ),
    );
  }
}

class MarketsPage extends StatelessWidget {
  const MarketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Column(
      children: [
        PageHeader(
          title: '行情',
          subtitle: '选择交易对',
          action: IconButton.filledTonal(
            onPressed: () => state.refreshInstruments(),
            icon: const Icon(Icons.refresh),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ModeSelector(
            value: state.mode,
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: state.visibleInstruments.map((instrument) {
              return InstrumentRow(
                instrument: instrument,
                selected: instrument.symbol == state.selectedSymbol,
                onTap: () => unawaited(state.selectSymbol(instrument.symbol)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final priceController = TextEditingController(text: '65000');
  final quantityController = TextEditingController(text: '1');
  String side = 'BUY';
  String orderType = 'LIMIT';
  String timeInForce = 'GTC';
  String marginMode = 'CROSS';
  String positionSide = 'NET';
  bool reduceOnly = false;
  bool postOnly = false;

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
    final latestPrice = state.latestPriceFor(instrument);
    if (state.orderBook.bids.isNotEmpty && priceController.text == '65000') {
      priceController.text = money(
        instrument.priceFromTicks(state.orderBook.bids.first.priceTicks),
        digits: instrument.pricePrecision,
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshPublicData();
        await state.refreshPrivateData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          PageHeader(
            title: '交易',
            subtitle:
                '${instrument.displayName} · ${instrument.mode.label} · 最新 ${latestPrice == null ? '--' : money(latestPrice, digits: instrument.pricePrecision)}',
            dense: true,
            action: IconButton.filledTonal(
              onPressed: () => state.refreshPublicData(),
              icon: const Icon(Icons.refresh),
            ),
          ),
          ModeSelector(
            value: state.mode,
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
          const SizedBox(height: 8),
          SymbolStrip(
            instruments: state.visibleInstruments,
            selected: state.selectedSymbol,
            onSelected: (symbol) => unawaited(state.selectSymbol(symbol)),
          ),
          const SizedBox(height: 10),
          KlinePanel(
            candles: state.candles,
            period: state.period,
            onPeriod: (period) => unawaited(state.selectPeriod(period)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 370,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: OrderTicket(
                    side: side,
                    orderType: orderType,
                    timeInForce: timeInForce,
                    marginMode: marginMode,
                    positionSide: positionSide,
                    reduceOnly: reduceOnly,
                    postOnly: postOnly,
                    priceController: priceController,
                    quantityController: quantityController,
                    instrument: instrument,
                    loggedIn: state.isLoggedIn,
                    onSide: (value) => setState(() => side = value),
                    onOrderType: (value) => setState(() => orderType = value),
                    onTimeInForce: (value) =>
                        setState(() => timeInForce = value),
                    onMarginMode: (value) => setState(() => marginMode = value),
                    onPositionSide: (value) =>
                        setState(() => positionSide = value),
                    onReduceOnly: (value) => setState(() => reduceOnly = value),
                    onPostOnly: (value) => setState(() => postOnly = value),
                    onSubmit: () {
                      if (!state.isLoggedIn) {
                        showAuthSheet(context);
                        return;
                      }
                      unawaited(
                        state.placeOrder(
                          side: side,
                          orderType: orderType,
                          timeInForce: timeInForce,
                          price: double.tryParse(priceController.text) ?? 0,
                          quantitySteps:
                              int.tryParse(quantityController.text) ?? 0,
                          marginMode: instrument.mode == ProductMode.spot
                              ? 'CROSS'
                              : marginMode,
                          positionSide: instrument.mode == ProductMode.spot
                              ? 'NET'
                              : positionSide,
                          reduceOnly: instrument.mode == ProductMode.spot
                              ? false
                              : reduceOnly,
                          postOnly: postOnly,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: OrderBookPanel(
                    instrument: instrument,
                    orderBook: state.orderBook,
                    latestPrice: latestPrice,
                    onPrice: (price) {
                      priceController.text = price;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PrivateTradingPanel(state: state),
        ],
      ),
    );
  }
}

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final amountController = TextEditingController(text: '10');
  final withdrawAmountController = TextEditingController(text: '0.1');
  final withdrawAddressController = TextEditingController();
  String source = 'SPOT';
  String target = 'USDT_PERPETUAL';
  String asset = 'USDT';
  String walletSymbol = 'USDT';
  String walletChain = 'ETH';

  @override
  void dispose() {
    amountController.dispose();
    withdrawAmountController.dispose();
    withdrawAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final total = state.balances.fold<double>(
      0,
      (sum, item) => sum + item.equity,
    );
    final symbols = _walletSymbols(state);
    final selectedSymbol = symbols.contains(walletSymbol)
        ? walletSymbol
        : symbols.first;
    final chains = _walletChains(state, selectedSymbol);
    final selectedChain = chains.contains(walletChain)
        ? walletChain
        : chains.first;
    final chainAsset = _walletChainAsset(state, selectedSymbol, selectedChain);
    final deposit = state.walletDepositAddress;
    final depositMatches =
        deposit != null &&
        deposit.symbol == selectedSymbol &&
        deposit.chain == selectedChain;
    return RefreshIndicator(
      onRefresh: state.refreshPrivateData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          PageHeader(
            title: '钱包',
            subtitle: state.isLoggedIn ? 'UID ${state.userId}' : '登录后查看资产',
            action: IconButton.filledTonal(
              onPressed: state.refreshPrivateData,
              icon: const Icon(Icons.refresh),
            ),
          ),
          GradientPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('总资产估值', style: TextStyle(color: _muted)),
                const SizedBox(height: 8),
                Text(
                  '${money(total, digits: 4)} USDT',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: MetricPill(
                        label: '交易账户',
                        value: '${money(total, digits: 4)} USDT',
                        color: _violet,
                      ),
                    ),
                    Expanded(
                      child: MetricPill(
                        label: '链上币种',
                        value: '${state.walletPortfolio.assetCount}',
                        color: _mint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: WalletAction(
                        icon: Icons.call_received,
                        label: '充币',
                        onTap: state.isLoggedIn
                            ? () => unawaited(
                                state.loadDepositAddress(
                                  chain: selectedChain,
                                  symbol: selectedSymbol,
                                ),
                              )
                            : () => showAuthSheet(context),
                      ),
                    ),
                    Expanded(
                      child: WalletAction(
                        icon: Icons.call_made,
                        label: '提币',
                        onTap: state.isLoggedIn
                            ? state.refreshWallet
                            : () => showAuthSheet(context),
                      ),
                    ),
                    Expanded(
                      child: WalletAction(
                        icon: Icons.swap_horiz,
                        label: '划转',
                        onTap: state.isLoggedIn
                            ? state.refreshPrivateData
                            : () => showAuthSheet(context),
                      ),
                    ),
                    Expanded(
                      child: WalletAction(
                        icon: Icons.receipt_long,
                        label: '记录',
                        onTap: state.isLoggedIn
                            ? state.refreshWallet
                            : () => showAuthSheet(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!state.isLoggedIn)
            PrimaryAction(
              label: '登录 / 注册',
              icon: Icons.login,
              onPressed: () => showAuthSheet(context),
            )
          else
            Column(
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: '充币地址',
                        action: IconButton.filledTonal(
                          onPressed: () => unawaited(
                            state.loadDepositAddress(
                              chain: selectedChain,
                              symbol: selectedSymbol,
                            ),
                          ),
                          icon: const Icon(Icons.qr_code),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: SmallDropdown(
                              value: selectedSymbol,
                              values: symbols,
                              onChanged: (value) {
                                final nextChains = _walletChains(state, value);
                                setState(() {
                                  walletSymbol = value;
                                  walletChain = nextChains.first;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SmallDropdown(
                              value: selectedChain,
                              values: chains,
                              onChanged: (value) =>
                                  setState(() => walletChain = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: PrimaryAction(
                              label: '获取地址',
                              icon: Icons.call_received,
                              onPressed: () => unawaited(
                                state.loadDepositAddress(
                                  chain: selectedChain,
                                  symbol: selectedSymbol,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => unawaited(
                                state.loadDepositAddress(
                                  chain: selectedChain,
                                  symbol: selectedSymbol,
                                  forceNew: true,
                                ),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('新地址'),
                            ),
                          ),
                        ],
                      ),
                      if (depositMatches) ...[
                        const SizedBox(height: 10),
                        DepositAddressCard(address: deposit),
                      ],
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: '提现'),
                      InfoLine(
                        label: '$selectedChain · $selectedSymbol 可用',
                        value: chainAsset == null
                            ? '--'
                            : money(chainAsset.availableBalance, digits: 8),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: withdrawAddressController,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          labelText: '到账地址',
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFFCFAFF),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: _line),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: withdrawAmountController,
                              label: '数量',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 92,
                            child: Center(
                              child: Text(
                                selectedSymbol,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PrimaryAction(
                        label: '确认提现',
                        icon: Icons.call_made,
                        onPressed: () => unawaited(
                          state.withdrawWallet(
                            chain: selectedChain,
                            symbol: selectedSymbol,
                            toAddress: withdrawAddressController.text,
                            amount: withdrawAmountController.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: '账户划转'),
                      Row(
                        children: [
                          Expanded(
                            child: SmallDropdown(
                              value: source,
                              values: const [
                                'SPOT',
                                'USDT_PERPETUAL',
                                'COIN_PERPETUAL',
                              ],
                              onChanged: (value) =>
                                  setState(() => source = value),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 18),
                          ),
                          Expanded(
                            child: SmallDropdown(
                              value: target,
                              values: const [
                                'SPOT',
                                'USDT_PERPETUAL',
                                'COIN_PERPETUAL',
                              ],
                              onChanged: (value) =>
                                  setState(() => target = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: amountController,
                              label: '数量',
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 86,
                            child: AppTextField(
                              initialValue: asset,
                              label: '资产',
                              onChanged: (value) => asset = value.toUpperCase(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PrimaryAction(
                        label: '确认划转',
                        icon: Icons.swap_horiz,
                        onPressed: () => unawaited(
                          state.transfer(
                            sourceAccountType: source,
                            targetAccountType: target,
                            asset: asset,
                            amount: double.tryParse(amountController.text) ?? 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SectionTitle(
                  title: '链上资产',
                  action: IconButton.filledTonal(
                    onPressed: () => unawaited(state.refreshWallet()),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                ...state.walletPortfolio.assets.map(
                  (walletAsset) => WalletAssetRow(asset: walletAsset),
                ),
                if (state.walletPortfolio.assets.isEmpty)
                  const EmptyState(text: '暂无链上资产数据'),
                const SectionTitle(title: '资金记录'),
                ...state.walletOrders.map(
                  (record) => WalletOrderRecordRow(record: record),
                ),
                if (state.walletOrders.isEmpty)
                  const EmptyState(text: '暂无资金记录'),
              ],
            ),
          const SizedBox(height: 12),
          const SectionTitle(title: '交易账户资产'),
          ...state.balances.map((balance) => BalanceRow(balance: balance)),
          if (state.balances.isEmpty) const EmptyState(text: '暂无资产数据'),
        ],
      ),
    );
  }

  List<String> _walletSymbols(AppState state) {
    final values =
        state.walletPortfolio.assets
            .map((asset) => asset.symbol)
            .where((symbol) => symbol.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values.isEmpty ? const ['USDT', 'BTC', 'ETH'] : values;
  }

  List<String> _walletChains(AppState state, String symbol) {
    final matches = state.walletPortfolio.assets.where(
      (asset) => asset.symbol == symbol,
    );
    final chains = matches.isEmpty
        ? <String>[]
        : matches.first.chains
              .map((chain) => chain.chain)
              .where((chain) => chain.isNotEmpty)
              .toSet()
              .toList();
    chains.sort();
    return chains.isEmpty ? const ['ETH', 'TRON', 'BTC'] : chains;
  }

  WalletChainAsset? _walletChainAsset(
    AppState state,
    String symbol,
    String chain,
  ) {
    for (final asset in state.walletPortfolio.assets) {
      if (asset.symbol != symbol) continue;
      for (final item in asset.chains) {
        if (item.chain == chain) return item;
      }
    }
    return null;
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PageHeader(
          title: '我的',
          subtitle: state.isLoggedIn ? state.session!.user.username : '未登录',
        ),
        Panel(
          child: Row(
            children: [
              const SparkleMark(size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isLoggedIn ? state.session!.user.username : '游客',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      state.isLoggedIn
                          ? 'UID ${state.userId} · ${state.session!.user.status}'
                          : '登录后同步订单、持仓和资产',
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
              ),
              if (state.isLoggedIn)
                IconButton.filledTonal(
                  onPressed: state.logout,
                  icon: const Icon(Icons.logout),
                )
              else
                FilledButton(
                  onPressed: () => showAuthSheet(context),
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              InfoLine(label: 'REST', value: state.config.gatewayBaseUrl),
              InfoLine(label: 'WebSocket', value: state.config.websocketUrl),
              InfoLine(
                label: 'WS本地回退',
                value: state.config.localWebSocketUserFallback
                    ? 'userId query'
                    : 'JWT token',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SectionTitle(title: '实时事件'),
        if (state.realtimeLog.isEmpty)
          const EmptyState(text: '暂无 WebSocket 事件'),
        ...state.realtimeLog.map(
          (line) => Panel(
            child: Text(
              line,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ),
      ],
    );
  }
}

class KlinePanel extends StatefulWidget {
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
  State<KlinePanel> createState() => _KlinePanelState();
}

class _KlinePanelState extends State<KlinePanel> {
  late final KLineController controller;

  @override
  void initState() {
    super.initState();
    controller = KLineController()
      ..itemCount = 38
      ..minCount = 12
      ..maxCount = 90
      ..showTimeAxis = true
      ..showMainIndicators = [IndicatorType.ma]
      ..showSubIndicators = [IndicatorType.vol, IndicatorType.macd]
      ..chartStyle = const KLineChartStyle(
        backgroundColor: Colors.transparent,
        gridLineColor: Color(0xFFEFE7F0),
        gridLineWidth: 0.6,
        rulerTextStyle: TextStyle(color: _muted, fontSize: 10),
      )
      ..candleStyle = const KLineCandleStyle(
        riseColor: _mint,
        fallColor: _red,
        riseWickColor: _mint,
        fallWickColor: _red,
      )
      ..volumeStyle = const KLineVolumeStyle(riseColor: _mint, fallColor: _red)
      ..indicatorColors = const [_amber, _violet, _pink];
    controller.priceFormatter = (value) =>
        value.toStringAsFixed(value > 1000 ? 1 : 4);
    controller.volumeFormatter = (value) => compactInt(value.round());
    _setData();
  }

  @override
  void didUpdateWidget(covariant KlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candles != widget.candles) _setData();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _setData() {
    controller.setData(
      widget.candles.map((candle) {
        return KLineData(
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          volume: candle.volume,
          time: candle.timeMillis,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        children: [
          Row(
            children: [
              const Text('K线', style: TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              for (final period in const ['1m', '5m', '15m', '1h', '4h'])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(period),
                    selected: widget.period == period,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => widget.onPeriod(period),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(height: 252, child: KLineView(controller: controller)),
        ],
      ),
    );
  }
}

class OrderTicket extends StatelessWidget {
  const OrderTicket({
    required this.side,
    required this.orderType,
    required this.timeInForce,
    required this.marginMode,
    required this.positionSide,
    required this.reduceOnly,
    required this.postOnly,
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
  final String positionSide;
  final bool reduceOnly;
  final bool postOnly;
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
    return Panel(
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BuySellSwitch(value: side, onChanged: onSide),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SmallDropdown(
                    value: orderType,
                    values: const ['LIMIT', 'MARKET'],
                    onChanged: onOrderType,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SmallDropdown(
                    value: timeInForce,
                    values: const ['GTC', 'IOC', 'FOK', 'GTX'],
                    onChanged: onTimeInForce,
                  ),
                ),
              ],
            ),
            if (instrument.mode != ProductMode.spot) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: SmallDropdown(
                      value: marginMode,
                      values: const ['CROSS', 'ISOLATED'],
                      onChanged: onMarginMode,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SmallDropdown(
                      value: positionSide,
                      values: const ['NET', 'LONG', 'SHORT'],
                      onChanged: onPositionSide,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            AppTextField(
              controller: priceController,
              label: '价格 ${instrument.quoteAsset}',
              enabled: orderType != 'MARKET',
            ),
            const SizedBox(height: 8),
            AppTextField(controller: quantityController, label: '数量 steps'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ToggleLine(
                    label: '只减仓',
                    value: reduceOnly,
                    enabled: instrument.mode != ProductMode.spot,
                    onChanged: onReduceOnly,
                  ),
                ),
                Expanded(
                  child: ToggleLine(
                    label: 'Post',
                    value: postOnly,
                    onChanged: onPostOnly,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: loggedIn ? (buy ? _mint : _red) : _violet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: onSubmit,
              icon: Icon(loggedIn ? Icons.flash_on : Icons.login),
              label: Text(loggedIn ? (buy ? '买入 / 开多' : '卖出 / 开空') : '登录后下单'),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderBookPanel extends StatelessWidget {
  const OrderBookPanel({
    required this.instrument,
    required this.orderBook,
    required this.latestPrice,
    required this.onPrice,
    super.key,
  });

  final Instrument instrument;
  final OrderBook orderBook;
  final double? latestPrice;
  final ValueChanged<String> onPrice;

  @override
  Widget build(BuildContext context) {
    final asks = orderBook.asks.take(6).toList().reversed.toList();
    final bids = orderBook.bids.take(6).toList();
    final fallbackPriceTicks = bids.isNotEmpty
        ? bids.first.priceTicks
        : (asks.isNotEmpty ? asks.last.priceTicks : 0);
    final displayPrice =
        latestPrice ??
        (fallbackPriceTicks == 0
            ? null
            : instrument.priceFromTicks(fallbackPriceTicks));
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  '价格',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              Text('数量', style: TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          for (final level in asks)
            BookLine(
              level: level,
              instrument: instrument,
              color: _red,
              onTap: onPrice,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              displayPrice == null
                  ? '--'
                  : money(displayPrice, digits: instrument.pricePrecision),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _mint,
              ),
            ),
          ),
          for (final level in bids)
            BookLine(
              level: level,
              instrument: instrument,
              color: _mint,
              onTap: onPrice,
            ),
          const Spacer(),
          Text(
            'Seq ${orderBook.sequence}',
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class PrivateTradingPanel extends StatelessWidget {
  const PrivateTradingPanel({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isLoggedIn) {
      return Panel(
        child: Column(
          children: [
            const EmptyState(text: '登录后查看委托、持仓和风险'),
            PrimaryAction(
              label: '登录 / 注册',
              icon: Icons.login,
              onPressed: () => showAuthSheet(context),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.accountRisk != null)
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '权益',
                    value: money(
                      unitsToDecimal(state.accountRisk!.equityUnits),
                      digits: 4,
                    ),
                    color: _violet,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '维持保证金',
                    value: money(
                      unitsToDecimal(state.accountRisk!.maintenanceMarginUnits),
                      digits: 4,
                    ),
                    color: _amber,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '保证金率',
                    value: percentageFromPpm(state.accountRisk!.marginRatioPpm),
                    color: _red,
                  ),
                ),
              ],
            ),
          ),
        const SectionTitle(title: '当前委托'),
        if (state.openOrders.isEmpty) const EmptyState(text: '暂无开放委托'),
        ...state.openOrders.map(
          (order) => OrderRow(
            order: order,
            instrument: state.selectedInstrument,
            onCancel: () => state.cancelOrder(order),
          ),
        ),
        const SectionTitle(title: '持仓'),
        if (state.positions.isEmpty) const EmptyState(text: '暂无持仓'),
        ...state.positions.map(
          (position) => PositionRow(position: position, state: state),
        ),
        const SectionTitle(title: '爆仓记录'),
        if (state.liquidationOrders.isEmpty) const EmptyState(text: '暂无爆仓记录'),
        ...state.liquidationOrders.map(
          (order) => Panel(
            child: InfoLine(
              label: '#${order.orderId} ${order.symbol}',
              value: '${order.status} · ${order.quantitySteps}',
            ),
          ),
        ),
      ],
    );
  }
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final username = TextEditingController(text: 'demo_user');
  final password = TextEditingController(text: 'demo_password');
  final email = TextEditingController(text: 'demo@example.com');
  bool register = false;

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                register ? '注册账户' : '登录账户',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          AppTextField(controller: username, label: '用户名'),
          const SizedBox(height: 8),
          AppTextField(controller: password, label: '密码', obscure: true),
          if (register) ...[
            const SizedBox(height: 8),
            AppTextField(controller: email, label: '邮箱'),
          ],
          const SizedBox(height: 12),
          PrimaryAction(
            label: register ? '创建并登录' : '登录',
            icon: register ? Icons.person_add : Icons.login,
            onPressed: () async {
              if (register) {
                await state.register(username.text, password.text, email.text);
              } else {
                await state.login(username.text, password.text);
              }
              if (context.mounted && state.isLoggedIn) Navigator.pop(context);
            },
          ),
          TextButton(
            onPressed: () => setState(() => register = !register),
            child: Text(register ? '已有账户，去登录' : '没有账户，去注册'),
          ),
        ],
      ),
    );
  }
}

void showAuthSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        AppScope(notifier: AppScope.of(context), child: const AuthSheet()),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    required this.subtitle,
    this.action,
    this.dense = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, dense ? 0 : 8, 0, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                Text(subtitle, style: const TextStyle(color: _muted)),
              ],
            ),
          ),
          ...action == null ? const <Widget>[] : [action!],
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: _pink.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class GradientPanel extends StatelessWidget {
  const GradientPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1F7), Color(0xFFF2F8FF), Color(0xFFFFFAE8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const Spacer(),
          ...action == null ? const <Widget>[] : [action!],
        ],
      ),
    );
  }
}

class ModeSelector extends StatelessWidget {
  const ModeSelector({required this.value, required this.onChanged, super.key});

  final ProductMode value;
  final ValueChanged<ProductMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ProductMode>(
      segments: ProductMode.values
          .map((mode) => ButtonSegment(value: mode, label: Text(mode.label)))
          .toList(),
      selected: {value},
      showSelectedIcon: false,
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
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: instruments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = instruments[index];
          return ChoiceChip(
            selected: item.symbol == selected,
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
              backgroundColor: value == 'BUY' ? _mint : const Color(0xFFEAF7F3),
              foregroundColor: value == 'BUY' ? Colors.white : _mint,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(6)),
              ),
            ),
            onPressed: () => onChanged('BUY'),
            child: const Text('买入'),
          ),
        ),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: value == 'SELL' ? _red : const Color(0xFFFFEEF1),
              foregroundColor: value == 'SELL' ? Colors.white : _red,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(6),
                ),
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

class SmallDropdown extends StatelessWidget {
  const SmallDropdown({
    required this.value,
    required this.values,
    required this.onChanged,
    super.key,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
        color: const Color(0xFFFCFAFF),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(
            fontSize: 12,
            color: _ink,
            fontWeight: FontWeight.w700,
          ),
          items: values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.initialValue,
    required this.label,
    this.enabled = true,
    this.obscure = false,
    this.onChanged,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final bool enabled;
  final bool obscure;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      enabled: enabled,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFCFAFF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
      ),
      keyboardType: obscure
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
    );
  }
}

class ToggleLine extends StatelessWidget {
  const ToggleLine({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: enabled ? _ink : _muted),
            ),
          ),
        ],
      ),
    );
  }
}

class BookLine extends StatelessWidget {
  const BookLine({
    required this.level,
    required this.instrument,
    required this.color,
    required this.onTap,
    super.key,
  });

  final OrderBookLevel level;
  final Instrument instrument;
  final Color color;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final price = money(
      instrument.priceFromTicks(level.priceTicks),
      digits: instrument.pricePrecision,
    );
    return InkWell(
      onTap: () => onTap(price),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                price,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              compactInt(level.quantitySteps),
              style: const TextStyle(fontSize: 12, color: _ink),
            ),
          ],
        ),
      ),
    );
  }
}

class InstrumentRow extends StatelessWidget {
  const InstrumentRow({
    required this.instrument,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final latestPrice = AppScope.of(context).latestPriceFor(instrument);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: selected ? _pink : const Color(0xFFFFEDF6),
              child: Text(
                instrument.baseAsset.isEmpty
                    ? '?'
                    : instrument.baseAsset.substring(0, 1),
                style: TextStyle(
                  color: selected ? Colors.white : _pink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${instrument.mode.label} · ${instrument.status} · ${(instrument.maxLeveragePpm / 1000000).round()}X',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            MetricPill(
              label: '最新',
              value: latestPrice == null
                  ? '--'
                  : money(latestPrice, digits: instrument.pricePrecision),
              color: _mint,
            ),
          ],
        ),
      ),
    );
  }
}

class BalanceRow extends StatelessWidget {
  const BalanceRow({required this.balance, super.key});

  final ProductBalance balance;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        children: [
          InfoLine(
            label: '${balance.accountType} · ${balance.asset}',
            value: money(balance.equity, digits: 4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '可用',
                  value: money(balance.available, digits: 4),
                  color: _mint,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: money(balance.locked, digits: 4),
                  color: _amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DepositAddressCard extends StatelessWidget {
  const DepositAddressCard({required this.address, super.key});

  final WalletDepositAddress address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
        color: const Color(0xFFFCFAFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QrImage(dataUrl: address.qrCodeDataUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${address.chain} · ${address.symbol}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      address.address,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (address.memo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      InfoLine(label: 'Memo', value: address.memo),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (address.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final warning in address.warnings.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  warning,
                  style: const TextStyle(color: _amber, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _QrImage extends StatelessWidget {
  const _QrImage({required this.dataUrl});

  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    if (!dataUrl.startsWith('data:image') || !dataUrl.contains(',')) {
      return _placeholder();
    }
    try {
      final bytes = base64Decode(dataUrl.split(',').last);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
      ),
      child: const Icon(Icons.qr_code_2, color: _muted),
    );
  }
}

class WalletAssetRow extends StatelessWidget {
  const WalletAssetRow({required this.asset, super.key});

  final WalletAssetSummary asset;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                asset.symbol,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              Text(
                money(asset.totalBalance, digits: 8),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '可用',
                  value: money(asset.availableBalance, digits: 8),
                  color: _mint,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: money(asset.lockedBalance, digits: 8),
                  color: _amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chain in asset.chains)
                Chip(
                  label: Text(
                    '${chain.chain} ${money(chain.totalBalance, digits: 6)}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class WalletOrderRecordRow extends StatelessWidget {
  const WalletOrderRecordRow({required this.record, super.key});

  final WalletOrderRecord record;

  @override
  Widget build(BuildContext context) {
    final isOut =
        record.type.contains('WITHDRAW') || record.type.contains('OUT');
    return Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isOut
                ? _red.withValues(alpha: 0.12)
                : _mint.withValues(alpha: 0.12),
            child: Icon(
              isOut ? Icons.call_made : Icons.call_received,
              color: isOut ? _red : _mint,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.type} · ${record.chain}/${record.symbol}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${record.status} · ${record.refNo}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.errorMessage.isNotEmpty)
                  Text(
                    record.errorMessage,
                    style: const TextStyle(color: _red, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isOut ? '-' : '+'}${money(record.amount, digits: 8)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isOut ? _red : _mint,
                ),
              ),
              if (record.fee > 0)
                Text(
                  'fee ${money(record.fee, digits: 8)}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
            ],
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
    super.key,
  });

  final OrderModel order;
  final Instrument instrument;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.side} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: order.side == 'BUY' ? _mint : _red,
                  ),
                ),
                Text(
                  '${order.orderType}/${order.timeInForce} · ${order.status}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  '价 ${money(instrument.priceFromTicks(order.priceTicks), digits: instrument.pricePrecision)} · 量 ${order.quantitySteps} · 成交 ${order.executedQuantitySteps}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onCancel,
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
    final instrument = state.instruments.firstWhere(
      (item) => item.symbol == position.symbol,
      orElse: () => state.selectedInstrument,
    );
    final matchingRisks = state.positionRisks.where(
      (item) => item.symbol == position.symbol,
    );
    final risk = matchingRisks.isEmpty ? null : matchingRisks.first;
    final long = position.signedQuantitySteps >= 0;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${position.symbol} ${long ? '多仓' : '空仓'}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: long ? _mint : _red,
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text('${position.marginMode} ${position.positionSide}'),
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => unawaited(state.closePosition(position)),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('平仓'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '数量',
                  value: '${position.signedQuantitySteps}',
                  color: long ? _mint : _red,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '开仓均价',
                  value: money(
                    instrument.priceFromTicks(position.entryPriceTicks),
                    digits: instrument.pricePrecision,
                  ),
                  color: _violet,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '未实现',
                  value: risk == null
                      ? '--'
                      : money(
                          unitsToDecimal(risk.unrealizedPnlUnits),
                          digits: 4,
                        ),
                  color: _amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WalletAction extends StatelessWidget {
  const WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: _violet),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  const QuickTile({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _violet),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          const Icon(Icons.inbox_outlined, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: _muted)),
          ),
        ],
      ),
    );
  }
}

class SparkleMark extends StatelessWidget {
  const SparkleMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [_pink, _violet, _amber],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(2),
        Radius.circular(size.width * .22),
      ),
      paint,
    );
    final star = Path();
    final center = Offset(size.width * .50, size.height * .46);
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? size.width * .24 : size.width * .10;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .22),
      size.width * .05,
      Paint()..color = Colors.white.withValues(alpha: .85),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
