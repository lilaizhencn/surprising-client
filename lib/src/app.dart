import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kline_chart/kline_chart.dart';

import 'app_state.dart';
import 'models.dart';

const _ink = Color(0xFFEAECEF);
const _muted = Color(0xFF848E9C);
const _paper = Color(0xFF0B0E11);
const _panel = Color(0xFF181A20);
const _panelSoft = Color(0xFF1E2329);
const _line = Color(0xFF2B3139);
const _pink = Color(0xFFFCD535);
const _violet = Color(0xFFA3E635);
const _mint = Color(0xFF00C076);
const _red = Color(0xFFF6465D);
const _amber = Color(0xFFFCD535);
const _lime = Color(0xFFB7FF2A);

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
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: _paper,
          colorScheme: const ColorScheme.dark(
            primary: _pink,
            secondary: _violet,
            tertiary: _mint,
            surface: _panel,
            surfaceContainerHighest: _panelSoft,
            error: _red,
          ),
          canvasColor: _paper,
          dividerColor: _line,
          textTheme: const TextTheme(
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
            titleMedium: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
            bodyMedium: TextStyle(fontSize: 12, color: _ink),
            labelMedium: TextStyle(fontSize: 11, color: _muted),
          ),
          snackBarTheme: const SnackBarThemeData(
            backgroundColor: _panel,
            contentTextStyle: TextStyle(color: _ink, fontSize: 13),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: _panel,
            surfaceTintColor: Colors.transparent,
            dragHandleColor: _line,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: _panel,
            indicatorColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                color: states.contains(WidgetState.selected) ? _ink : _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                color: states.contains(WidgetState.selected) ? _amber : _muted,
              ),
            ),
          ),
          chipTheme: ChipThemeData(
            backgroundColor: _panelSoft,
            selectedColor: _pink.withValues(alpha: .20),
            side: const BorderSide(color: _line),
            labelStyle: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            secondaryLabelStyle: const TextStyle(
              color: _ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              backgroundColor: _panelSoft,
              foregroundColor: _ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: _line),
              ),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _pink,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _panelSoft,
              disabledForegroundColor: _muted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: _line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
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
      2 => TradePage(key: ValueKey('trade-${state.mode.name}')),
      3 => TradePage(key: ValueKey('contract-${state.mode.name}')),
      _ => const WalletPage(),
    };
    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: ExchangeBottomNav(
        selectedIndex: index,
        onSelected: (next) {
          if (next == 2) {
            unawaited(state.selectMode(ProductMode.spot));
          } else if (next == 3 && state.mode.isSpot) {
            unawaited(state.selectMode(ProductMode.linear));
          }
          setState(() => index = next);
        },
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

class ExchangeBottomNav extends StatelessWidget {
  const ExchangeBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const exchangeItems = [
      _ExchangeNavItem(Icons.grid_view_outlined, Icons.grid_view, '首页'),
      _ExchangeNavItem(Icons.show_chart, Icons.show_chart, '行情'),
      _ExchangeNavItem(Icons.sync_alt, Icons.sync_alt, '交易'),
      _ExchangeNavItem(Icons.receipt_long_outlined, Icons.receipt_long, '合约'),
      _ExchangeNavItem(
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet,
        '资产',
      ),
    ];
    const items = exchangeItems;
    return Container(
      height: 56 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _line, width: .7)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(i),
                child: _ExchangeNavButton(
                  item: items[i],
                  selected: selectedIndex == i,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExchangeNavItem {
  const _ExchangeNavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _ExchangeNavButton extends StatelessWidget {
  const _ExchangeNavButton({required this.item, required this.selected});

  final _ExchangeNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = item.label == '资产' ? _lime : _amber;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExchangeNavGlyph(
          label: item.label,
          color: selected ? selectedColor : _muted,
          selected: selected,
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            color: selected ? selectedColor : _muted,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: selected ? 14 : 0,
          height: 2,
          decoration: BoxDecoration(
            color: selectedColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class ExchangeNavGlyph extends StatelessWidget {
  const ExchangeNavGlyph({
    required this.label,
    required this.color,
    required this.selected,
    super.key,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(24),
      painter: _ExchangeNavGlyphPainter(
        label: label,
        color: color,
        selected: selected,
      ),
    );
  }
}

class _ExchangeNavGlyphPainter extends CustomPainter {
  const _ExchangeNavGlyphPainter({
    required this.label,
    required this.color,
    required this.selected,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.4 : 2.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (label) {
      case '首页':
        _drawHome(canvas, size, fill);
      case '行情':
        _drawMarket(canvas, size, stroke);
      case '探索':
        _drawExplore(canvas, size, fill);
      case '交易':
        _drawTrade(canvas, size, stroke);
      case '合约':
        _drawContract(canvas, size, stroke, fill);
      case '资产':
        _drawWallet(canvas, size, stroke, fill);
      default:
        canvas.drawCircle(size.center(Offset.zero), size.width * .34, stroke);
    }
  }

  void _drawExplore(Canvas canvas, Size size, Paint fill) {
    final center = size.center(Offset.zero);
    final path = Path()
      ..moveTo(center.dx, size.height * .16)
      ..lineTo(size.width * .72, size.height * .72)
      ..lineTo(center.dx, size.height * .60)
      ..lineTo(size.width * .28, size.height * .72)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _drawHome(Canvas canvas, Size size, Paint fill) {
    final unit = size.width / 5.6;
    final gap = unit * .54;
    final start = Offset(size.width * .18, size.height * .18);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        final rect = Rect.fromLTWH(
          start.dx + col * (unit + gap),
          start.dy + row * (unit + gap),
          unit,
          unit,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(unit * .14)),
          fill,
        );
      }
    }
  }

  void _drawMarket(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .70)
      ..lineTo(size.width * .34, size.height * .52)
      ..lineTo(size.width * .48, size.height * .62)
      ..lineTo(size.width * .75, size.height * .34);
    canvas.drawPath(path, stroke);
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .75, size.height * .52),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .57, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .18, size.height * .82),
      Offset(size.width * .68, size.height * .82),
      stroke,
    );
  }

  void _drawTrade(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * .22, size.height * .34),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .22),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .46),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .78, size.height * .66),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .54),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .78),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
  }

  void _drawContract(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .24,
      size.height * .14,
      size.width * .50,
      size.height * .68,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .06)),
      stroke,
    );
    for (final y in [.32, .48, .64]) {
      canvas.drawLine(
        Offset(size.width * .34, size.height * y),
        Offset(size.width * .64, size.height * y),
        stroke,
      );
    }
    final diamond = Path()
      ..moveTo(size.width * .76, size.height * .70)
      ..lineTo(size.width * .84, size.height * .78)
      ..lineTo(size.width * .76, size.height * .86)
      ..lineTo(size.width * .68, size.height * .78)
      ..close();
    canvas.drawPath(diamond, fill);
  }

  void _drawWallet(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .17,
      size.height * .25,
      size.width * .66,
      size.height * .50,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .08)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .27, size.height * .25),
      Offset(size.width * .43, size.height * .12),
      stroke,
    );
    final pocket = Rect.fromLTWH(
      size.width * .54,
      size.height * .41,
      size.width * .29,
      size.height * .22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pocket, Radius.circular(size.width * .05)),
      stroke,
    );
    canvas.drawCircle(Offset(size.width * .65, size.height * .52), 1.5, fill);
  }

  @override
  bool shouldRepaint(covariant _ExchangeNavGlyphPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
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
                    Text('现货 · 永续 · 交割 · 期权', style: TextStyle(color: _muted)),
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
    final instruments = state.visibleInstruments;
    return RefreshIndicator(
      onRefresh: state.refreshInstruments,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Expanded(child: ExchangeSearchBox(hint: '搜索代币交易对和趋势')),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '更多',
                  onPressed: state.refreshInstruments,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    foregroundColor: _ink,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_horiz, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const MarketPrimaryTabs(selectedIndex: 1),
          const Divider(height: 1, color: _line),
          ProductPageSelector(
            value: state.mode,
            title: '行情产品页',
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
          const CategoryStrip(),
          const MarketSortHeader(),
          if (instruments.isEmpty)
            const EmptyState(text: '暂无行情数据')
          else
            ...instruments.map((instrument) {
              return MarketTickerRow(
                instrument: instrument,
                selected: instrument.symbol == state.selectedSymbol,
                onTap: () => unawaited(state.selectSymbol(instrument.symbol)),
              );
            }),
          const SizedBox(height: 24),
        ],
      ),
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
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
        children: [
          ProductPageSelector(
            value: state.mode,
            title: '交易产品页',
            compact: true,
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
          const Divider(height: 10, color: _line),
          TradeSymbolHeader(
            instrument: instrument,
            latestPrice: latestPrice,
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
            const SizedBox(height: 6),
            ContractQuickSettings(
              marginMode: marginMode,
              leverage: '${(instrument.maxLeveragePpm / 1000000).round()}x',
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
          SizedBox(
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
                          marginMode: instrument.isSpot ? 'CROSS' : marginMode,
                          positionSide:
                              instrument.isSpot ||
                                  state.positionMode == 'ONE_WAY'
                              ? 'NET'
                              : positionSide == 'NET'
                              ? (side == 'SELL' ? 'SHORT' : 'LONG')
                              : positionSide,
                          reduceOnly: instrument.isSpot ? false : reduceOnly,
                          postOnly: postOnly,
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
                    latestPrice: latestPrice,
                    onPrice: (price) {
                      priceController.text = price;
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          PrivateTradingPanel(state: state),
          if (instrument.isDerivative) ...[
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                childrenPadding: EdgeInsets.zero,
                collapsedIconColor: _muted,
                iconColor: _ink,
                title: const Text(
                  '高级委托',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                children: [
                  AlgoOrderPanel(state: state, marginMode: marginMode),
                  const SizedBox(height: 6),
                  TriggerOrderPanel(state: state, marginMode: marginMode),
                ],
              ),
            ),
            const SizedBox(height: 2),
          ],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 2),
              collapsedIconColor: _muted,
              iconColor: _ink,
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
                  onPeriod: (period) => unawaited(state.selectPeriod(period)),
                ),
              ],
            ),
          ),
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
    final tradingTotal = state.balances.fold<double>(
      0,
      (sum, item) => sum + item.equity,
    );
    final displayPortfolio = state.walletPortfolio.assets.isEmpty
        ? fallbackWalletPortfolio()
        : state.walletPortfolio;
    final walletTotalCny = walletPortfolioCny(displayPortfolio);
    final tradingTotalCny = tradingTotal * 7.18;
    final totalCny = walletTotalCny + tradingTotalCny;
    final pnlCny = totalCny == 0 ? 0.0 : -totalCny * 0.0185;
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
    return Material(
      color: Colors.black,
      child: RefreshIndicator(
        onRefresh: state.refreshPrivateData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            Row(
              children: [
                const Text(
                  '总资产估值',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.visibility_outlined, color: _muted, size: 16),
                const Spacer(),
                IconButton(
                  tooltip: '资金记录',
                  onPressed: state.isLoggedIn
                      ? () => unawaited(state.refreshWallet())
                      : () => showAuthSheet(context),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    foregroundColor: _ink,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.receipt_long_outlined, size: 21),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    money(totalCny, digits: 2),
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text(
                    'CNY',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 3, bottom: 8),
                  child: Icon(Icons.arrow_drop_down, color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '今日收益 ${pnlCny >= 0 ? '+' : ''}${money(pnlCny, digits: 2)} (${totalCny == 0 ? '0.00' : '-1.85'}%)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: pnlCny >= 0 ? _mint : _red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right, color: _ink, size: 18),
                const SizedBox(width: 8),
                const SizedBox(width: 78, height: 36, child: AssetSparkline()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                WalletAction(
                  icon: Icons.file_download_outlined,
                  label: '充币',
                  onTap: () => _openRechargeFlow(context, state),
                ),
                WalletAction(
                  icon: Icons.file_upload_outlined,
                  label: '提币',
                  onTap: state.isLoggedIn
                      ? state.refreshWallet
                      : () => showAuthSheet(context),
                ),
                WalletAction(
                  icon: Icons.swap_horiz,
                  label: '划转',
                  onTap: state.isLoggedIn
                      ? state.refreshPrivateData
                      : () => showAuthSheet(context),
                ),
                WalletAction(
                  icon: Icons.link,
                  label: '赚币',
                  onTap: state.isLoggedIn
                      ? state.refreshWallet
                      : () => showAuthSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
              decoration: BoxDecoration(
                color: const Color(0xFF202124),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '启用 DEX 交易功能',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '在交易所交易 DEX 代币',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _lime.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: _lime,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  '资产组合',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '筛选',
                  onPressed: state.refreshPrivateData,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    foregroundColor: _ink,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.tune, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  AssetPortfolioCard(
                    icon: Icons.savings_outlined,
                    title: '资金账户',
                    amount: '¥${money(walletTotalCny, digits: 2)}',
                  ),
                  AssetPortfolioCard(
                    icon: Icons.swap_vert,
                    title: '交易账户',
                    amount: '¥${money(tradingTotalCny, digits: 2)}',
                  ),
                  const AssetPortfolioCard(
                    icon: Icons.link,
                    title: '赚币',
                    amount: '¥0',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Text(
                  '代币',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Spacer(),
                Icon(Icons.keyboard_arrow_up, color: _ink),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Text('名称/数量', style: TextStyle(color: _muted, fontSize: 12)),
                Spacer(),
                Text('价值/现货收益', style: TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            if (displayPortfolio.assets.isNotEmpty)
              ...displayPortfolio.assets.map(
                (walletAsset) => WalletTokenRow(asset: walletAsset),
              ),
            if (!state.isLoggedIn)
              PrimaryAction(
                label: '登录 / 注册',
                icon: Icons.login,
                onPressed: () => showAuthSheet(context),
              )
            else
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  collapsedIconColor: _ink,
                  iconColor: _ink,
                  title: const Text(
                    '钱包工具',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
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
                                    final nextChains = _walletChains(
                                      state,
                                      value,
                                    );
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
                              color: _ink,
                            ),
                            decoration: InputDecoration(
                              labelText: '到账地址',
                              labelStyle: const TextStyle(color: _muted),
                              isDense: true,
                              filled: true,
                              fillColor: _panelSoft,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: _line),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: _pink),
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
                                  values: productAccountTypes,
                                  labelBuilder: productAccountLabel,
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
                                  values: productAccountTypes,
                                  labelBuilder: productAccountLabel,
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
                                  onChanged: (value) =>
                                      asset = value.toUpperCase(),
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
                                amount:
                                    double.tryParse(amountController.text) ?? 0,
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
              ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                collapsedIconColor: _ink,
                iconColor: _ink,
                title: const Text(
                  '交易账户资产',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                children: [
                  ...state.balances.map(
                    (balance) => BalanceRow(balance: balance),
                  ),
                  if (state.balances.isEmpty) const EmptyState(text: '暂无资产数据'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRechargeFlow(BuildContext context, AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RechargeCoinPage()));
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

class RechargeCoinPage extends StatefulWidget {
  const RechargeCoinPage({super.key});

  @override
  State<RechargeCoinPage> createState() => _RechargeCoinPageState();
}

class _RechargeCoinPageState extends State<RechargeCoinPage> {
  final queryController = TextEditingController();

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final query = queryController.text.trim().toUpperCase();
    final symbols = rechargeSymbols(
      state,
    ).where((symbol) => query.isEmpty || symbol.contains(query)).toList();
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            RechargeHeader(
              title: '选择资产',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '帮助',
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                    ),
                    icon: const Icon(Icons.help_outline, size: 30),
                  ),
                  IconButton(
                    tooltip: '记录',
                    onPressed: () => unawaited(state.refreshWallet()),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 30),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            RechargeSearchField(
              controller: queryController,
              hint: '搜索数字货币',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 26),
            const Text(
              '数字货币',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            for (final symbol in symbols)
              RechargeCoinRow(
                symbol: symbol,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RechargeNetworkPage(symbol: symbol),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class RechargeNetworkPage extends StatelessWidget {
  const RechargeNetworkPage({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final chains = rechargeChains(state, symbol);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            const RechargeHeader(title: '选择网络'),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info, color: _ink, size: 24),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '不清楚如何选择网络？',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '请确保您选择的网络，与汇出平台或钱包的网络保持一致。',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 17,
                            height: 1.45,
                          ),
                        ),
                        SizedBox(height: 18),
                        Text(
                          '了解更多  →',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 34),
            const Row(
              children: [
                Text('网络', style: TextStyle(color: _muted, fontSize: 17)),
                Spacer(),
                Text(
                  '到账时间/最小充币金额',
                  style: TextStyle(color: _muted, fontSize: 17),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Text(
              '可用',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            for (final chain in chains)
              RechargeNetworkRow(
                symbol: symbol,
                chain: chain,
                onTap: () async {
                  await state.loadDepositAddress(chain: chain, symbol: symbol);
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RechargeAddressPage(symbol: symbol, chain: chain),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class RechargeAddressPage extends StatefulWidget {
  const RechargeAddressPage({
    required this.symbol,
    required this.chain,
    super.key,
  });

  final String symbol;
  final String chain;

  @override
  State<RechargeAddressPage> createState() => _RechargeAddressPageState();
}

class _RechargeAddressPageState extends State<RechargeAddressPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppScope.of(context);
      final address = state.walletDepositAddress;
      if (address == null ||
          address.symbol != widget.symbol ||
          address.chain != widget.chain) {
        unawaited(
          state.loadDepositAddress(chain: widget.chain, symbol: widget.symbol),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final address = state.walletDepositAddress;
    final matches =
        address != null &&
        address.symbol == widget.symbol &&
        address.chain == widget.chain;
    final addressText = matches ? address.address : '地址生成中...';
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            RechargeHeader(
              title: '',
              trailing: IconButton(
                tooltip: '更多',
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                ),
                icon: const Icon(Icons.more_horiz, size: 30),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '充值 ${widget.symbol}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _QrImage(
                      dataUrl: matches ? address.qrCodeDataUrl : '',
                      size: 244,
                    ),
                    Container(
                      width: 50,
                      height: 50,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CryptoAvatar(symbol: widget.symbol, size: 42),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 34),
            const Text(
              '地址 〉',
              style: TextStyle(
                color: _muted,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    addressText,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                InkWell(
                  onTap: matches
                      ? () => Clipboard.setData(
                          ClipboardData(text: address.address),
                        )
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1F1F1F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.copy, size: 28),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              '切换至 0x 地址  ⇄',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 28),
            const Divider(color: Color(0xFF262626)),
            RechargeInfoLine(
              label: '网络',
              value: networkDisplayName(widget.chain, widget.symbol),
              leading: CryptoAvatar(
                symbol: chainSymbol(widget.chain),
                size: 18,
              ),
            ),
            const RechargeInfoLine(label: '充值账户', value: '资金账户'),
            RechargeInfoLine(
              label: '最小充币金额',
              value: '0.01 ${widget.symbol}',
              showChevron: false,
              showInfo: true,
            ),
            RechargeInfoLine(
              label: '到账时间',
              value: networkEta(widget.chain),
              showChevron: false,
              showInfo: true,
            ),
            RechargeInfoLine(
              label: '可提币时间',
              value: networkEta(widget.chain),
              showChevron: false,
              showInfo: true,
            ),
            const RechargeInfoLine(label: '合约地址', value: '查看详情'),
            if (!matches) ...[
              const SizedBox(height: 18),
              PrimaryAction(
                label: state.loadingPrivate ? '加载中' : '重新获取地址',
                icon: Icons.refresh,
                onPressed: () => unawaited(
                  state.loadDepositAddress(
                    chain: widget.chain,
                    symbol: widget.symbol,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RechargeHeader extends StatelessWidget {
  const RechargeHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
              ),
              icon: const Icon(Icons.arrow_back_ios_new, size: 27),
            ),
          ),
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing!),
        ],
      ),
    );
  }
}

class RechargeSearchField extends StatelessWidget {
  const RechargeSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: _muted,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        prefixIcon: const Icon(Icons.search, color: _ink, size: 30),
        filled: true,
        fillColor: const Color(0xFF1F1F1F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class RechargeCoinRow extends StatelessWidget {
  const RechargeCoinRow({required this.symbol, required this.onTap, super.key});

  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            CryptoAvatar(symbol: symbol, size: 56),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (symbol == 'USDG') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _mint.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '3.5% 年化收益',
                            style: TextStyle(
                              color: _mint,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    assetDisplayName(symbol),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RechargeNetworkRow extends StatelessWidget {
  const RechargeNetworkRow({
    required this.symbol,
    required this.chain,
    required this.onTap,
    super.key,
  });

  final String symbol;
  final String chain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            CryptoAvatar(symbol: chainSymbol(chain), size: 52),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                networkDisplayName(chain, symbol),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  networkEta(chain),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '0.01 $symbol',
                  style: const TextStyle(color: _muted, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RechargeInfoLine extends StatelessWidget {
  const RechargeInfoLine({
    required this.label,
    required this.value,
    this.leading,
    this.showChevron = true,
    this.showInfo = false,
    super.key,
  });

  final String label;
  final String value;
  final Widget? leading;
  final bool showChevron;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (showInfo) ...[
                const SizedBox(width: 6),
                const Icon(Icons.info_outline, color: _muted, size: 18),
              ],
            ],
          ),
          const Spacer(),
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down, color: _muted),
          ],
        ],
      ),
    );
  }
}

List<String> rechargeSymbols(AppState state) {
  final symbols =
      state.walletPortfolio.assets
          .map((asset) => asset.symbol.toUpperCase())
          .where((symbol) => symbol.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (symbols.isNotEmpty) return symbols;
  return const [
    'USDT',
    'USDG',
    'USDC',
    'BTC',
    'ETH',
    'XAUT',
    'SOL',
    'TRX',
    '1INCH',
  ];
}

List<String> rechargeChains(AppState state, String symbol) {
  for (final asset in state.walletPortfolio.assets) {
    if (asset.symbol.toUpperCase() != symbol.toUpperCase()) continue;
    final chains = asset.chains
        .map((chain) => chain.chain)
        .where((chain) => chain.isNotEmpty)
        .toSet()
        .toList();
    if (chains.isNotEmpty) return chains;
  }
  if (symbol == 'BTC') return const ['BTC'];
  if (symbol == 'ETH') return const ['ETH', 'ARB', 'AVAX'];
  return const [
    'Surprising Chain',
    'TRON',
    'ETH',
    'APTOS',
    'ARB',
    'AVAX',
    'BERA',
  ];
}

String chainSymbol(String chain) {
  final upper = chain.toUpperCase();
  if (upper.contains('TRON') || upper == 'TRX') return 'TRX';
  if (upper.contains('ETH')) return 'ETH';
  if (upper.contains('BTC')) return 'BTC';
  if (upper.contains('SOL')) return 'SOL';
  if (upper.contains('SURPRISING')) return 'SPEX';
  if (upper.contains('APTOS')) return 'APTOS';
  if (upper.contains('ARB')) return 'ARB';
  if (upper.contains('AVAX') || upper.contains('AVALANCHE')) return 'AVAX';
  if (upper.contains('BERA')) return 'BERA';
  return upper.isEmpty ? '?' : upper.substring(0, 1);
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
        gridLineColor: _line,
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
              const Text('K线', style: TextStyle(fontWeight: FontWeight.w700)),
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
    required this.positionMode,
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
  final String positionMode;
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
    final hedgeMode = instrument.isDerivative && positionMode == 'HEDGE';
    void stepPrice(int direction) {
      if (orderType == 'MARKET') return;
      final current = double.tryParse(priceController.text) ?? 0;
      final tick = instrument.priceFromTicks(1).abs();
      final next = math.max(0.0, current + tick * direction);
      priceController.text = money(next, digits: instrument.pricePrecision);
    }

    void stepQuantity(int direction) {
      final current = int.tryParse(quantityController.text) ?? 0;
      quantityController.text = math.max(0, current + direction).toString();
    }

    return Panel(
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BuySellSwitch(value: side, onChanged: onSide),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: SmallDropdown(
                    value: orderType,
                    values: const ['LIMIT', 'MARKET'],
                    labelBuilder: orderTypeLabel,
                    onChanged: onOrderType,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: SmallDropdown(
                    value: timeInForce,
                    values: const ['GTC', 'IOC', 'FOK', 'GTX'],
                    labelBuilder: timeInForceLabel,
                    onChanged: onTimeInForce,
                  ),
                ),
              ],
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
                        value: positionSide == 'NET' ? 'LONG' : positionSide,
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
            Row(
              children: [
                Expanded(
                  child: TradeNumericField(
                    controller: priceController,
                    label: '价格 (${instrument.quoteAsset})',
                    enabled: orderType != 'MARKET',
                    onMinus: () => stepPrice(-1),
                    onPlus: () => stepPrice(1),
                  ),
                ),
                const SizedBox(width: 5),
                BestPriceButton(
                  enabled: orderType != 'MARKET',
                  onTap: () {
                    final bids = AppScope.of(context).orderBook.bids;
                    if (bids.isEmpty) return;
                    priceController.text = money(
                      instrument.priceFromTicks(bids.first.priceTicks),
                      digits: instrument.pricePrecision,
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 5),
            TradeNumericField(
              controller: quantityController,
              label: '数量',
              suffixLabel: instrument.baseAsset,
              onMinus: () => stepQuantity(-1),
              onPlus: () => stepQuantity(1),
            ),
            const SizedBox(height: 6),
            const OrderAmountSlider(),
            const SizedBox(height: 5),
            OrderMetaRow(label: '可用', value: '--  ⇆'),
            OrderMetaRow(label: '最大', value: '0.000 ${instrument.baseAsset}'),
            if (instrument.isDerivative)
              OrderMetaRow(
                label: '保证金',
                value: '0.00 ${instrument.quoteAsset}',
              ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: ToggleLine(
                    label: '只减仓',
                    value: reduceOnly,
                    enabled: instrument.isDerivative,
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
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: loggedIn ? (buy ? _mint : _red) : _violet,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(34),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: onSubmit,
              icon: Icon(loggedIn ? Icons.flash_on : Icons.login, size: 16),
              label: Text(
                loggedIn
                    ? instrument.isSpot
                          ? (buy ? '买入' : '卖出')
                          : hedgeMode
                          ? (buy ? '买入' : '卖出')
                          : (buy ? '买入 / 开多' : '卖出 / 开空')
                    : '登录',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (interval <= 0 || duration <= 0) return false;
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
        intervalSeconds: int.tryParse(intervalController.text) ?? 0,
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
          const Text('算法单', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  label: '价格 ticks',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: quantityController,
                  label: '总量 steps',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: childQuantityController,
                  label: '切片 steps',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: intervalController,
                  label: '间隔秒',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: durationController,
                  label: '时长秒',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ToggleLine(
                  label: '只减仓',
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
              backgroundColor: _violet,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: _valid && !submitting ? submit : null,
            icon: Icon(submitting ? Icons.hourglass_top : Icons.schedule),
            label: Text(submitting ? '提交中' : '提交 ${algoTypeLabel(algoType)}'),
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

  void addLevel(String triggerType) {
    final defaultPrice = _defaultTriggerPriceTicks().toString();
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
          callbackRatePpm: triggerType == 'TRAILING_STOP' ? '1000' : '',
          quantitySteps: '1',
        ),
      );
    });
  }

  int _defaultTriggerPriceTicks() {
    final instrument = widget.state.selectedInstrument;
    final latestPrice = widget.state.latestPriceFor(instrument);
    if (latestPrice != null && latestPrice > 0) {
      return instrument.ticksFromPrice(latestPrice);
    }
    final book = widget.state.orderBook;
    if (book.symbol == instrument.symbol && book.bids.isNotEmpty) {
      return book.bids.first.priceTicks;
    }
    return 0;
  }

  List<TriggerOrderDraft> _drafts() {
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    return levels
        .map((level) {
          final triggerPriceTicks = int.tryParse(level.triggerPriceTicks) ?? 0;
          final activationPriceTicks = int.tryParse(level.activationPriceTicks);
          final callbackRatePpm = int.tryParse(level.callbackRatePpm);
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
          );
        })
        .where(_validDraft)
        .toList();
  }

  bool _validDraft(TriggerOrderDraft draft) {
    if (draft.quantitySteps <= 0) return false;
    if (draft.triggerType == 'TRAILING_STOP') {
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
    if (drafts.isEmpty || submitting) return;
    setState(() => submitting = true);
    await widget.state.placeTriggerOrders(drafts);
    if (mounted) setState(() => submitting = false);
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
                child: Text(
                  '条件单',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.filledTonal(
                tooltip: '新增止盈',
                onPressed: () => addLevel('TAKE_PROFIT'),
                icon: const Icon(Icons.add_chart, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '新增止损',
                onPressed: () => addLevel('STOP_LOSS'),
                icon: const Icon(Icons.add_alert, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '新增追踪止损',
                onPressed: () => addLevel('TRAILING_STOP'),
                icon: const Icon(Icons.timeline, size: 18),
              ),
            ],
          ),
          if (levels.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '暂无待提交档位',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final level in levels) _levelRow(level),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(38),
              ),
              onPressed: validCount == 0 || submitting ? null : submit,
              icon: Icon(
                submitting ? Icons.hourglass_top : Icons.notifications,
              ),
              label: Text(submitting ? '提交中' : '提交 $validCount 档'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelRow(_TriggerLevelInput level) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
        color: _panelSoft,
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
                  onChanged: (value) => setState(() {
                    level.triggerType = value;
                    if (value == 'TRAILING_STOP') {
                      level.triggerPriceTicks = '0';
                      if (level.activationPriceTicks.isEmpty) {
                        level.activationPriceTicks = _defaultTriggerPriceTicks()
                            .toString();
                      }
                      if (level.callbackRatePpm.isEmpty) {
                        level.callbackRatePpm = '1000';
                      }
                    } else {
                      if (level.triggerPriceTicks == '0') {
                        level.triggerPriceTicks = _defaultTriggerPriceTicks()
                            .toString();
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
                  onChanged: (value) =>
                      setState(() => level.closeTarget = value),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '删除',
                onPressed: () => setState(() => levels.remove(level)),
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  key: ValueKey('${level.id}-price'),
                  initialValue: level.triggerPriceTicks,
                  label: '触发价 ticks',
                  onChanged: (value) => level.triggerPriceTicks = value,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  key: ValueKey('${level.id}-quantity'),
                  initialValue: level.quantitySteps,
                  label: '平仓数量 steps',
                  onChanged: (value) => level.quantitySteps = value,
                ),
              ),
            ],
          ),
          if (level.triggerType == 'TRAILING_STOP') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: ValueKey('${level.id}-activation'),
                    initialValue: level.activationPriceTicks,
                    label: '激活价 ticks',
                    onChanged: (value) => level.activationPriceTicks = value,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AppTextField(
                    key: ValueKey('${level.id}-callback'),
                    initialValue: level.callbackRatePpm,
                    label: '回调 ppm',
                    onChanged: (value) => level.callbackRatePpm = value,
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
  String activationPriceTicks;
  String callbackRatePpm;
  String quantitySteps;
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
    final asks = orderBook.asks.take(5).toList().reversed.toList();
    final bids = orderBook.bids.take(5).toList();
    final askTotal = asks.fold<int>(
      0,
      (sum, level) => sum + level.quantitySteps.abs(),
    );
    final bidTotal = bids.fold<int>(
      0,
      (sum, level) => sum + level.quantitySteps.abs(),
    );
    final buyRatio = bidTotal + askTotal == 0
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
          const Row(
            children: [
              Expanded(
                child: Text(
                  '价格',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ),
              Text('数量', style: TextStyle(color: _muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 3),
          for (final level in asks)
            BookLine(
              level: level,
              instrument: instrument,
              color: _red,
              onTap: onPrice,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              displayPrice == null
                  ? '--'
                  : money(displayPrice, digits: instrument.pricePrecision),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
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
          OrderBookRatioBar(buyRatio: buyRatio),
          const SizedBox(height: 6),
          const OrderBookToolbar(),
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
          '${(buy * 100).toStringAsFixed(2)}%',
          style: const TextStyle(
            color: _mint,
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
                    decoration: const BoxDecoration(
                      color: _mint,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(999),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, color: _paper),
                Expanded(
                  flex: math.max(1, (sell * 1000).round()),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _red,
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
          '${(sell * 100).toStringAsFixed(2)}%',
          style: const TextStyle(
            color: _red,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class OrderBookToolbar extends StatelessWidget {
  const OrderBookToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _panelSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _line),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    '0.01',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: _muted, size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        const OrderBookLayoutIcon(),
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
    final colors = [_red, _muted, _mint, _muted];
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

class PrivateTradingPanel extends StatelessWidget {
  const PrivateTradingPanel({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final botCount =
        state.openAlgoOrders.length + state.openTriggerOrders.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoggedIn && state.accountRisk != null)
          Panel(
            padding: const EdgeInsets.all(10),
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
        TradingPanelTabs(
          positionCount: state.positions.length,
          orderCount: state.openOrders.length,
          botCount: botCount,
        ),
        if (state.positions.isEmpty)
          const TradingEmptyState(text: '暂无仓位')
        else
          ...state.positions.map(
            (position) => PositionRow(position: position, state: state),
          ),
        if (state.openOrders.isNotEmpty) ...[
          const SectionTitle(title: '当前委托'),
          ...state.openOrders.map(
            (order) => OrderRow(
              order: order,
              instrument: state.selectedInstrument,
              onCancel: () => state.cancelOrder(order),
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
                label: Text(
                  state.loadingMoreOpenOrders ? '加载中...' : '加载更多委托',
                ),
              ),
            ),
        ],
        if (state.openAlgoOrders.isNotEmpty) ...[
          const SectionTitle(title: '交易机器人'),
          ...state.openAlgoOrders.map(
            (order) => AlgoOrderRow(
              order: order,
              state: state,
              onCancel: () => state.cancelAlgoOrder(order),
            ),
          ),
        ],
        if (state.openTriggerOrders.isNotEmpty) ...[
          const SectionTitle(title: '止盈止损'),
          ...state.openTriggerOrders.map(
            (order) => TriggerOrderRow(
              order: order,
              state: state,
              onCancel: () => state.cancelTriggerOrder(order),
            ),
          ),
        ],
        if (state.liquidationOrders.isNotEmpty) ...[
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
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
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
                      color: index == 0 ? _ink : _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: index == 0 ? 24 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _amber,
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
              foregroundColor: _ink,
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
            color: _muted.withValues(alpha: .62),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

class ExchangeSearchBox extends StatelessWidget {
  const ExchangeSearchBox({required this.hint, super.key});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, color: _muted, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarketPrimaryTabs extends StatelessWidget {
  const MarketPrimaryTabs({required this.selectedIndex, super.key});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    const tabs = ['自选', '加密货币', '传统金融', 'Alpha', '金融增长'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                tabs[index],
                style: TextStyle(
                  color: selected ? _ink : _muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: selected ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProductPageSelector extends StatelessWidget {
  const ProductPageSelector({
    required this.value,
    required this.title,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final ProductMode value;
  final String title;
  final ValueChanged<ProductMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openProductPagePicker(context),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 42 : 50),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: _panelSoft,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _pink.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.open_in_new, color: _pink, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.label,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProductPagePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<ProductMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return ProductPagePickerSheet(current: value);
      },
    );
    if (selected != null && selected != value) {
      onChanged(selected);
    }
  }
}

class ProductPagePickerSheet extends StatelessWidget {
  const ProductPagePickerSheet({required this.current, super.key});

  final ProductMode current;

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: 'U本位永续', detail: 'USDT 保证金永续合约', mode: ProductMode.linear),
      (label: '币本位永续', detail: '币本位保证金永续合约', mode: ProductMode.inverse),
      (label: 'U本位交割', detail: '到期现金交割合约', mode: ProductMode.linearDelivery),
      (label: '币本位交割', detail: '币本位到期交割合约', mode: ProductMode.inverseDelivery),
      (label: '期权', detail: '欧式现金行权期权', mode: ProductMode.option),
      (label: '现货', detail: '资产和资产直接兑换', mode: ProductMode.spot),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '打开产品页',
            style: TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: item.mode == current ? _pink : _line),
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: item.mode == current
                    ? _pink.withValues(alpha: .14)
                    : _panelSoft,
                title: Text(
                  item.label,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  item.detail,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                trailing: item.mode == current
                    ? const Icon(Icons.check_circle, color: _pink)
                    : const Icon(Icons.chevron_right, color: _muted),
                onTap: () => Navigator.of(context).pop(item.mode),
              ),
            ),
        ],
      ),
    );
  }
}

class CategoryStrip extends StatelessWidget {
  const CategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const values = ['全部', '新币', 'DeFi', '元宇宙', '支付', 'PoW'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: values.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == values.length) {
            return const Center(
              child: Icon(Icons.format_list_bulleted, color: _ink, size: 20),
            );
          }
          final selected = index == 0;
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _panelSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                values[index],
                style: TextStyle(
                  color: selected ? _ink : _muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MarketSortHeader extends StatelessWidget {
  const MarketSortHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Text(
              '名称↕ / 成交额↕',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '最新价格↕',
              textAlign: TextAlign.right,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          SizedBox(width: 7),
          SizedBox(
            width: 78,
            child: Text(
              '24 小时涨跌↕',
              textAlign: TextAlign.right,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class MarketTickerRow extends StatelessWidget {
  const MarketTickerRow({
    required this.instrument,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final latestPrice = state.latestPriceFor(instrument);
    final change = syntheticChange(instrument);
    final quote = instrument.quoteAsset.isEmpty
        ? instrument.settleAsset
        : instrument.quoteAsset;
    final priceText = latestPrice == null
        ? '--'
        : money(latestPrice, digits: instrument.pricePrecision);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        color: selected
            ? _panelSoft.withValues(alpha: .28)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Row(
                children: [
                  CryptoAvatar(symbol: instrument.baseAsset, size: 28),
                  const SizedBox(width: 8),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (instrument.isDerivative) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: _line),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  instrument.contractLabel,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${assetDisplayName(instrument.baseAsset)} | ${volumeText(instrument)} $quote',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    priceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    latestPrice == null
                        ? '--'
                        : '¥${money(latestPrice * 7.18, digits: 2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Container(
              width: 78,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: change >= 0 ? _mint : _red,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TradeSymbolHeader extends StatelessWidget {
  const TradeSymbolHeader({
    required this.instrument,
    required this.latestPrice,
    required this.onRefresh,
    super.key,
  });

  final Instrument instrument;
  final double? latestPrice;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final change = syntheticChange(instrument);
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
                        border: Border.all(color: _line),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        instrument.contractLabel,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Icon(Icons.arrow_drop_down, color: _ink),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: change >= 0 ? _mint : _red,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'K线',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: _ink,
          ),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.candlestick_chart_outlined, size: 20),
        ),
        IconButton(
          tooltip: '更多',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: _ink,
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
    final underlying = _underlyingInstrument();
    final underlyingPrice = underlying == null
        ? null
        : state.latestPriceFor(underlying);
    final strike = instrument.strikePrice;
    final intrinsic = _intrinsicValue(instrument, underlyingPrice, strike);
    final chain = _optionChainRows(instrument, state.instruments);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOption ? Icons.auto_graph : Icons.event_available_outlined,
                size: 18,
                color: _amber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isOption ? '期权链路' : '交割合约生命周期',
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
                style: const TextStyle(
                  color: _muted,
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
              LifecycleChip(label: '状态', value: instrument.status),
              LifecycleChip(
                label: '到期',
                value: shortDateTime(instrument.expiryTime),
              ),
              LifecycleChip(
                label: isOption ? '行权' : '交割',
                value: shortDateTime(instrument.deliveryTime),
              ),
              LifecycleChip(
                label: '剩余',
                value: timeLeft(
                  instrument.deliveryTime ?? instrument.expiryTime,
                ),
              ),
              LifecycleChip(
                label: '结算',
                value: instrument.settlementMethod ?? '--',
              ),
              LifecycleChip(label: '账户', value: instrument.mode.accountType),
            ],
          ),
          if (isOption) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MetricPill(
                  label: '底层',
                  value: underlyingPrice == null
                      ? instrument.underlyingSymbol ?? '--'
                      : money(
                          underlyingPrice,
                          digits: underlying?.pricePrecision ?? 2,
                        ),
                  color: _violet,
                ),
                MetricPill(
                  label: '行权价',
                  value: strike == null
                      ? '--'
                      : money(strike, digits: instrument.pricePrecision),
                  color: _amber,
                ),
                MetricPill(
                  label: '权利金',
                  value: latestPrice == null
                      ? '--'
                      : money(latestPrice!, digits: instrument.pricePrecision),
                  color: _mint,
                ),
                MetricPill(
                  label: '内在价值',
                  value: intrinsic == null
                      ? '--'
                      : money(intrinsic, digits: instrument.pricePrecision),
                  color: intrinsic != null && intrinsic > 0 ? _mint : _muted,
                ),
                MetricPill(
                  label: 'Delta估算',
                  value: estimatedDelta(instrument, underlyingPrice, strike),
                  color: _violet,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (chain.isEmpty)
              const Text(
                '暂无同到期期权链',
                style: TextStyle(color: _muted, fontSize: 12),
              )
            else
              Column(
                children: [
                  const InfoLine(label: '期权链', value: '到期 / 行权价 / CALL / PUT'),
                  ...chain
                      .take(6)
                      .map(
                        (row) => InfoLine(
                          label:
                              '${row.expiry} ${money(row.strike, digits: instrument.pricePrecision)}',
                          value: '${row.call ?? '-'} / ${row.put ?? '-'}',
                        ),
                      ),
                ],
              ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '方向',
                    value: instrument.mode == ProductMode.inverseDelivery
                        ? '币本位反向'
                        : 'U本位正向',
                    color: _violet,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: '结算资产',
                    value: instrument.settleAsset,
                    color: _amber,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: '最大杠杆',
                    value: '${(instrument.maxLeveragePpm / 1000000).round()}x',
                    color: _mint,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Instrument? _underlyingInstrument() {
    final target = instrument.underlyingSymbol;
    if (target == null || target.isEmpty) return null;
    for (final item in state.instruments) {
      if (item.symbol == target) return item;
    }
    return null;
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
        color: _panelSoft,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 9)),
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
    required this.positionMode,
    required this.onMarginMode,
    required this.onPositionMode,
    super.key,
  });

  final String marginMode;
  final String leverage;
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
        Expanded(
          child: TradeSettingButton(label: leverage, onTap: () {}),
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
        const Expanded(
          flex: 4,
          child: Text(
            '资金费率 (8时)/倒计时\n-0.00010%/02:27:38',
            textAlign: TextAlign.right,
            style: TextStyle(color: _muted, fontSize: 9.5, height: 1.12),
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
          color: _panelSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AssetPortfolioCard extends StatelessWidget {
  const AssetPortfolioCard({
    required this.icon,
    required this.title,
    required this.amount,
    super.key,
  });

  final IconData icon;
  final String title;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _ink, size: 16),
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class AssetSparkline extends StatelessWidget {
  const AssetSparkline({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AssetSparklinePainter());
  }
}

class _AssetSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(0, size.height * .62),
      Offset(size.width * .10, size.height * .48),
      Offset(size.width * .20, size.height * .54),
      Offset(size.width * .32, size.height * .40),
      Offset(size.width * .45, size.height * .45),
      Offset(size.width * .57, size.height * .30),
      Offset(size.width * .70, size.height * .50),
      Offset(size.width * .82, size.height * .42),
      Offset(size.width, size.height * .78),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_red.withValues(alpha: .35), _red.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final dotPaint = Paint()
      ..color = _red.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    for (var x = 4.0; x < size.width; x += 8) {
      for (var y = size.height * .42; y < size.height; y += 8) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    final linePaint = Paint()
      ..color = _red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

double walletPortfolioCny(WalletPortfolio portfolio) {
  return portfolio.assets.fold<double>(
    0,
    (sum, asset) => sum + walletAssetCny(asset),
  );
}

double walletAssetCny(WalletAssetSummary asset) {
  return asset.totalBalance * walletAssetCnyPrice(asset.symbol);
}

double walletAssetCnyPrice(String symbol) {
  return switch (symbol.toUpperCase()) {
    'SPEX' => 7.18,
    'BTC' => 417887.8,
    'ETH' => 11814.59,
    'SOL' => 540.8,
    'USDT' || 'USDC' || 'USDG' => 7.18,
    'XAUT' || 'XAU' => 28202.46,
    _ => 7.18,
  };
}

String walletGainLabel(WalletAssetSummary asset, double value) {
  return switch (asset.symbol.toUpperCase()) {
    'SPEX' => '+¥39,491.57 (+122.31%)',
    'BTC' => '+¥1,968.86 (+31.75%)',
    _ => '+¥${money(value * .315, digits: 2)} (+31.50%)',
  };
}

class WalletTokenRow extends StatelessWidget {
  const WalletTokenRow({required this.asset, super.key});

  final WalletAssetSummary asset;

  @override
  Widget build(BuildContext context) {
    final value = walletAssetCny(asset);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          CryptoAvatar(symbol: asset.symbol, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        asset.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _mint.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '年化可达 5%',
                        style: TextStyle(
                          color: _mint,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  money(asset.totalBalance, digits: 8),
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${money(value, digits: 2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                walletGainLabel(asset, value),
                style: const TextStyle(
                  color: _mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line.withValues(alpha: .82)),
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
        gradient: LinearGradient(
          colors: [_panel, _panelSoft, _violet.withValues(alpha: .22)],
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
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _pink.withValues(alpha: .20)
              : _panelSoft,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _ink : _muted,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected) ? _pink : _line,
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
              ? _violet.withValues(alpha: .18)
              : _panelSoft,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _ink : _muted,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected) ? _violet : _line,
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
            selectedColor: _pink.withValues(alpha: .20),
            backgroundColor: _panelSoft,
            side: BorderSide(color: item.symbol == selected ? _pink : _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            labelStyle: TextStyle(
              color: item.symbol == selected ? _ink : _muted,
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
              minimumSize: const Size.fromHeight(36),
              backgroundColor: value == 'BUY'
                  ? _mint
                  : _panelSoft.withValues(alpha: .86),
              foregroundColor: value == 'BUY' ? Colors.white : _mint,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
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
              minimumSize: const Size.fromHeight(36),
              backgroundColor: value == 'SELL'
                  ? _red
                  : _panelSoft.withValues(alpha: .86),
              foregroundColor: value == 'SELL' ? Colors.white : _red,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
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
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(
          color: _ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: _muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: _panelSoft,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 6,
          ),
          prefixIcon: IconButton(
            tooltip: '减少',
            onPressed: enabled ? onMinus : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(Icons.remove, size: 16),
          ),
          suffixIcon: SizedBox(
            width: suffixLabel == null ? 28 : 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suffixLabel != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text(
                        suffixLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '增加',
                  onPressed: enabled ? onPlus : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 28,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _pink),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _line.withValues(alpha: .55)),
          ),
        ),
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
        width: 58,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? _panelSoft : _panelSoft.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
        ),
        child: Text(
          enabled ? '最优价' : '市价',
          style: TextStyle(
            color: enabled ? _ink : _muted,
            fontSize: 12,
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
            style: const TextStyle(
              color: _muted,
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
              style: const TextStyle(
                color: _ink,
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
            child: Container(height: 3, color: _line),
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
                    color: index == 0 ? _panel : _paper,
                    border: Border.all(
                      color: index == 0 ? _ink : _line,
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

class SmallDropdown extends StatelessWidget {
  const SmallDropdown({
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelBuilder,
    super.key,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String Function(String value)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _line),
        color: _panelSoft,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: _panel,
          iconEnabledColor: _muted,
          style: const TextStyle(
            fontSize: 10.5,
            color: _ink,
            fontWeight: FontWeight.w500,
          ),
          items: values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelBuilder == null ? item : labelBuilder!(item),
                    overflow: TextOverflow.ellipsis,
                  ),
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
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: _ink,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        filled: true,
        fillColor: _panelSoft,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _pink),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: _line.withValues(alpha: .55)),
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
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 10.5, color: enabled ? _ink : _muted),
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
    final depth = math.min(
      .86,
      math.max(.18, math.log(level.quantitySteps.abs() + 1) / 8),
    );
    return InkWell(
      onTap: () => onTap(price),
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
                  compactInt(level.quantitySteps),
                  style: const TextStyle(fontSize: 11, color: _ink),
                ),
              ],
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
              backgroundColor: selected ? _pink : _panelSoft,
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
        color: _panelSoft,
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
  const _QrImage({required this.dataUrl, this.size = 96});

  final String dataUrl;
  final double size;

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
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrPlaceholderPainter(),
      ),
    );
  }
}

class _QrPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, background);

    final module = size.width / 29;
    final black = Paint()..color = Colors.black;
    final quiet = module * 1.2;

    void drawModule(int x, int y) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            quiet + x * module,
            quiet + y * module,
            module * .72,
            module * .72,
          ),
          Radius.circular(module * .36),
        ),
        black,
      );
    }

    void finder(int x, int y) {
      final left = quiet + x * module;
      final top = quiet + y * module;
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 3,
        black,
      );
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 2,
        background,
      );
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 1.2,
        black,
      );
    }

    finder(1, 1);
    finder(21, 1);
    finder(1, 21);

    for (var y = 0; y < 27; y++) {
      for (var x = 0; x < 27; x++) {
        final inTopLeft = x < 8 && y < 8;
        final inTopRight = x > 18 && y < 8;
        final inBottomLeft = x < 8 && y > 18;
        if (inTopLeft || inTopRight || inBottomLeft) continue;
        final seed = (x * 17 + y * 31 + x * y * 7) % 11;
        if (seed == 0 || seed == 3 || seed == 7) drawModule(x, y);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                money(asset.totalBalance, digits: 8),
                style: const TextStyle(fontWeight: FontWeight.w700),
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
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
                  fontWeight: FontWeight.w700,
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
                    fontWeight: FontWeight.w700,
                    color: order.side == 'BUY' ? _mint : _red,
                  ),
                ),
                Text(
                  '${order.orderType}/${order.timeInForce} · ${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.status}',
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

class AlgoOrderRow extends StatelessWidget {
  const AlgoOrderRow({
    required this.order,
    required this.state,
    required this.onCancel,
    super.key,
  });

  final AlgoOrderModel order;
  final AppState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final instrument = state.instruments.firstWhere(
      (item) => item.symbol == order.symbol,
      orElse: () => state.selectedInstrument,
    );
    final priceText = order.priceTicks > 0
        ? money(
            instrument.priceFromTicks(order.priceTicks),
            digits: instrument.pricePrecision,
          )
        : 'MARKET';
    final progress = order.executedQuantitySteps + order.activeQuantitySteps;
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${algoTypeLabel(order.algoType)} ${order.side} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: order.side == 'BUY' ? _mint : _red,
                  ),
                ),
                Text(
                  '${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.timeInForce} · ${order.status}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  '价 $priceText · 进度 $progress/${order.quantitySteps} · 切片 ${order.childQuantitySteps}/${order.intervalSeconds}s',
                  style: const TextStyle(fontSize: 12),
                ),
                if (order.rejectReason != null &&
                    order.rejectReason!.isNotEmpty)
                  Text(
                    order.rejectReason!,
                    style: const TextStyle(color: _red, fontSize: 11),
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
      (item) => item.symbol == order.symbol,
      orElse: () => state.selectedInstrument,
    );
    final isTakeProfit = order.triggerType == 'TAKE_PROFIT';
    final triggerText = order.triggerType == 'TRAILING_STOP'
        ? '激活 ${order.activationPriceTicks == null ? '立即' : money(instrument.priceFromTicks(order.activationPriceTicks!), digits: instrument.pricePrecision)} / 回调 ${((order.callbackRatePpm ?? 0) / 10000).toStringAsFixed(2)}%'
        : '触发 ${money(instrument.priceFromTicks(order.triggerPriceTicks), digits: instrument.pricePrecision)}';
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${triggerTypeLabel(order.triggerType)} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isTakeProfit ? _mint : _red,
                  ),
                ),
                Text(
                  '${triggerCloseLabel(order.side, order.positionSide)} · ${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.status}',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                Text(
                  '$triggerText · 量 ${order.quantitySteps}',
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
      (item) =>
          item.symbol == position.symbol &&
          item.positionSide == position.positionSide,
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
                '${position.symbol} ${positionSideLabel(position.positionSide)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: long ? _mint : _red,
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  '${position.marginMode} ${positionSideLabel(position.positionSide)}',
                ),
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

class CryptoAvatar extends StatelessWidget {
  const CryptoAvatar({required this.symbol, required this.size, super.key});

  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final upper = symbol.toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CryptoAvatarPainter(upper)),
    );
  }
}

class _CryptoAvatarPainter extends CustomPainter {
  const _CryptoAvatarPainter(this.symbol);

  final String symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final background = Paint()..color = assetColor(symbol);
    canvas.drawCircle(center, size.width / 2, background);

    switch (symbol) {
      case 'BTC':
        _drawText(canvas, size, 'B', Colors.white, .58, FontWeight.w900);
        _drawStroke(canvas, size, Colors.white.withValues(alpha: .9));
      case 'ETH':
        _drawEth(canvas, size);
      case 'USDT':
        _drawStable(canvas, size, 'T');
      case 'USDC':
        _drawStable(canvas, size, r'$');
      case 'USDG':
        _drawText(canvas, size, 'G', Colors.white, .58, FontWeight.w900);
      case 'SPEX':
      case 'SURPRISING CHAIN':
        _drawPlatformTokenMark(canvas, size);
      case 'SOL':
        _drawSol(canvas, size);
      case 'TRX':
        _drawTriangleMark(canvas, size, Colors.white);
      case 'XAU':
      case 'XAUT':
        _drawGold(canvas, size);
      case 'APT':
      case 'APTOS':
        _drawAptos(canvas, size);
      case 'ARB':
      case 'ARBITRUM':
        _drawHex(canvas, size);
      case 'AVAX':
      case 'AVALANCHE':
        _drawAvax(canvas, size);
      case 'BERA':
      case 'BERACHAIN':
        _drawText(
          canvas,
          size,
          'B',
          const Color(0xFF111111),
          .54,
          FontWeight.w900,
        );
      default:
        final label = symbol.isEmpty ? '?' : symbol.substring(0, 1);
        _drawText(canvas, size, label, _ink, .52, FontWeight.w800);
    }
  }

  void _drawText(
    Canvas canvas,
    Size size,
    String text,
    Color color,
    double scale,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size.width * scale,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  void _drawStroke(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .035
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * .38, size.height * .24),
      Offset(size.width * .38, size.height * .76),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .58, size.height * .24),
      Offset(size.width * .58, size.height * .76),
      paint,
    );
  }

  void _drawEth(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final faint = Paint()..color = Colors.white.withValues(alpha: .65);
    final top = Path()
      ..moveTo(size.width * .50, size.height * .16)
      ..lineTo(size.width * .28, size.height * .52)
      ..lineTo(size.width * .50, size.height * .43)
      ..lineTo(size.width * .72, size.height * .52)
      ..close();
    final bottom = Path()
      ..moveTo(size.width * .50, size.height * .48)
      ..lineTo(size.width * .28, size.height * .57)
      ..lineTo(size.width * .50, size.height * .84)
      ..lineTo(size.width * .72, size.height * .57)
      ..close();
    canvas.drawPath(top, white);
    canvas.drawPath(bottom, faint);
  }

  void _drawStable(Canvas canvas, Size size, String label) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .06;
    canvas.drawCircle(size.center(Offset.zero), size.width * .30, white);
    _drawText(canvas, size, label, Colors.white, .46, FontWeight.w900);
  }

  void _drawPlatformTokenMark(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final unit = size.width * .18;
    final start = Offset(size.width * .22, size.height * .22);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(
            start.dx + col * unit,
            start.dy + row * unit,
            unit * .82,
            unit * .82,
          ),
          paint,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .56,
        size.height * .56,
        unit * .82,
        unit * .82,
      ),
      paint,
    );
  }

  void _drawSol(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF14F195),
      const Color(0xFF80ECFF),
      const Color(0xFFDC1FFF),
    ];
    for (var i = 0; i < 3; i++) {
      final paint = Paint()..color = colors[i];
      final top = size.height * (.28 + i * .18);
      final path = Path()
        ..moveTo(size.width * .24, top)
        ..lineTo(size.width * .76, top)
        ..lineTo(size.width * .66, top + size.height * .10)
        ..lineTo(size.width * .14, top + size.height * .10)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawTriangleMark(Canvas canvas, Size size, Color color) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * .06
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .28, size.height * .20)
      ..lineTo(size.width * .76, size.height * .38)
      ..lineTo(size.width * .42, size.height * .78)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _drawGold(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .055
      ..style = PaintingStyle.stroke;
    for (final center in [
      Offset(size.width * .36, size.height * .40),
      Offset(size.width * .58, size.height * .40),
      Offset(size.width * .47, size.height * .62),
    ]) {
      canvas.drawCircle(center, size.width * .095, stroke);
    }
  }

  void _drawAptos(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .07
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.32 + i * .12);
      canvas.drawLine(
        Offset(size.width * .22, y),
        Offset(size.width * .78, y),
        paint,
      );
    }
  }

  void _drawHex(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF8CC8FF)
      ..strokeWidth = size.width * .07
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point =
          size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * size.width * .32;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  void _drawAvax(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .22)
      ..lineTo(size.width * .75, size.height * .72)
      ..lineTo(size.width * .25, size.height * .72)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .66),
      1.8,
      Paint()..color = const Color(0xFFE84142),
    );
  }

  @override
  bool shouldRepaint(covariant _CryptoAvatarPainter oldDelegate) {
    return oldDelegate.symbol != symbol;
  }
}

Color assetColor(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => const Color(0xFFF7931A),
    'ETH' => const Color(0xFF627EEA),
    'SPEX' || 'SURPRISING CHAIN' => const Color(0xFF050505),
    'USDT' => const Color(0xFF26A17B),
    'USDC' => const Color(0xFF2775CA),
    'USDG' => const Color(0xFF8DC63F),
    'SOL' => const Color(0xFF111827),
    'TRX' => const Color(0xFFFF0013),
    'APT' || 'APTOS' => const Color(0xFF111111),
    'ARB' || 'ARBITRUM' => const Color(0xFF2D374B),
    'AVAX' || 'AVALANCHE' => const Color(0xFFE84142),
    'BERA' || 'BERACHAIN' => const Color(0xFFFFFFFF),
    'XAU' || 'XAUT' => const Color(0xFFB79525),
    _ => const Color(0xFF2B3139),
  };
}

String assetDisplayName(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => 'Bitcoin',
    'ETH' => 'Ethereum',
    'SPEX' => 'Surprising EX',
    'SOL' => 'Solana',
    'USDT' => 'Tether',
    'USDC' => 'USD Coin',
    'TRX' => 'TRON',
    'XAU' || 'XAUT' => 'Tether Gold',
    _ => symbol,
  };
}

String volumeText(Instrument instrument) {
  final seed = instrument.symbol.codeUnits.fold<int>(
    0,
    (sum, code) => sum + code,
  );
  final amount = 6 + (seed % 130);
  return '$amount.${seed % 100}亿';
}

String shortDateTime(DateTime? value) {
  if (value == null) return '--';
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String timeLeft(DateTime? value) {
  if (value == null) return '--';
  final seconds = value.difference(DateTime.now()).inSeconds;
  if (seconds <= 0) return '已到期';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '$days天$hours小时';
  return '$hours小时$minutes分';
}

double? _intrinsicValue(
  Instrument instrument,
  double? underlyingPrice,
  double? strike,
) {
  if (underlyingPrice == null || strike == null) return null;
  if (instrument.optionType == 'PUT') {
    return math.max(0, strike - underlyingPrice);
  }
  return math.max(0, underlyingPrice - strike);
}

String estimatedDelta(
  Instrument instrument,
  double? underlyingPrice,
  double? strike,
) {
  if (underlyingPrice == null || strike == null || strike <= 0) return '--';
  final ratio = underlyingPrice / strike;
  final call = instrument.optionType != 'PUT';
  if (call) {
    if (ratio >= 1.03) return '0.7500';
    if (ratio <= 0.97) return '0.2500';
    return '0.5000';
  }
  if (ratio <= 0.97) return '-0.7500';
  if (ratio >= 1.03) return '-0.2500';
  return '-0.5000';
}

List<OptionChainRow> _optionChainRows(
  Instrument selected,
  List<Instrument> instruments,
) {
  final targetExpiry = _dateKey(selected.expiryTime ?? selected.deliveryTime);
  final targetUnderlying = selected.underlyingSymbol ?? selected.baseAsset;
  final rows = <String, OptionChainRow>{};
  for (final item in instruments) {
    if (!item.isOption) continue;
    if ((item.underlyingSymbol ?? item.baseAsset) != targetUnderlying) continue;
    final expiry = _dateKey(item.expiryTime ?? item.deliveryTime);
    if (targetExpiry.isNotEmpty && expiry != targetExpiry) continue;
    final strike = item.strikePrice;
    if (strike == null) continue;
    final key = '$expiry:$strike';
    final current = rows[key] ?? OptionChainRow(expiry: expiry, strike: strike);
    rows[key] = item.optionType == 'PUT'
        ? current.copyWith(put: item.symbol)
        : current.copyWith(call: item.symbol);
  }
  final sorted = rows.values.toList()
    ..sort((left, right) => left.strike.compareTo(right.strike));
  return sorted;
}

String _dateKey(DateTime? value) {
  if (value == null) return '';
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

class OptionChainRow {
  const OptionChainRow({
    required this.expiry,
    required this.strike,
    this.call,
    this.put,
  });

  final String expiry;
  final double strike;
  final String? call;
  final String? put;

  OptionChainRow copyWith({String? call, String? put}) {
    return OptionChainRow(
      expiry: expiry,
      strike: strike,
      call: call ?? this.call,
      put: put ?? this.put,
    );
  }
}

double syntheticChange(Instrument instrument) {
  if (instrument.isSpot) {
    return 0.6 + (instrument.symbol.length % 5) * .21;
  }
  final seed = instrument.symbol.codeUnits.fold<int>(
    0,
    (sum, code) => sum + code,
  );
  return -0.7 - (seed % 430) / 100;
}

String networkDisplayName(String chain, String symbol) {
  final upper = chain.toUpperCase();
  return switch (upper) {
    'TRON' || 'TRX' => 'Tron (TRC20)',
    'ETH' || 'ETHEREUM' => 'Ethereum (ERC20)',
    'BTC' => 'Bitcoin',
    'SURPRISING CHAIN' => 'Surprising Chain ($symbol)',
    'ARB' || 'ARBITRUM' => 'Arbitrum One ($symbol)',
    'AVAX' || 'AVALANCHE' => 'Avalanche C-Chain',
    'APT' || 'APTOS' => 'Aptos',
    'BERA' || 'BERACHAIN' => 'Berachain (${symbol}0)',
    _ => chain,
  };
}

String networkEta(String chain) {
  final upper = chain.toUpperCase();
  if (upper.contains('ETH')) return '约 7 分钟';
  if (upper.contains('ARB')) return '约 18 分钟';
  return '约 1 分钟';
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
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: _lime,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black, size: 25),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: _muted)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
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
        minimumSize: const Size.fromHeight(40),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
