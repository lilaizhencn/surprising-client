import 'dart:async';
import 'package:flutter/material.dart';
import '../account/profile_page.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../deposit_page.dart';
import '../exchange_widgets.dart';
import '../models.dart';
import '../notifications_page.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import '../ui/client_navigation.dart';
import '../ui/crypto_avatar.dart';
import '../user_scanner_page.dart';
import 'market_chart.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  void authenticated(AppState state, VoidCallback open) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    open();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final items = state.instruments
        .where(
          (item) =>
              item.mode == state.mode &&
              item.symbol.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Material(
      color: exchangeBackground(context),
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            state.refreshInstruments(),
            state.refreshAnnouncements(),
            if (state.isLoggedIn) state.refreshPrivateData(),
            state.refreshValuation(),
          ]);
        },
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '交易所',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '通知',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.notifications_none_outlined),
                  onPressed: () => authenticated(
                    state,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => NotificationsPage(state: state),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '个人设置',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: BorderSide.none,
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(Icons.account_circle_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('个人设置')),
                        body: const SafeArea(child: ProfilePage()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExchangeSearchField(
              onChanged: (value) => setState(() => query = value),
              onScan: () => authenticated(
                state,
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => UserScannerPage(state: state),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: state.isLoggedIn ? null : () => showAuthSheet(context),
              child: AccountValueHeader(state: state),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 48),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () => authenticated(
                      state,
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MobileDepositPage(state: state),
                        ),
                      ),
                    ),
                    child: const Text('链上充币'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 48),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        ClientNavigation.maybeOf(context)?.openBuyCrypto(),
                    child: const Text('C2C 买币'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () =>
                  ClientNavigation.maybeOf(context)?.openAnnouncements(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.campaign_outlined,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        asString(
                          state.announcementBanners.firstOrNull?['title'],
                          fallback: asString(
                            state.announcements.firstOrNull?['title'],
                            fallback: '公告',
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            const MarketProductStrip(),
            const SizedBox(height: 12),
            const MarketListHeading(),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: Text('暂无行情')),
              ),
            for (final instrument in items.take(20))
              PublicMarketRow(instrument: instrument),
          ],
        ),
      ),
    );
  }
}

class MarketProductStrip extends StatelessWidget {
  const MarketProductStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return SingleChildScrollView(
      key: const ValueKey('market-product-tabs'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final product in ProductMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                key: ValueKey('market-product-${product.name}'),
                label: Text(product.label),
                selected: state.mode == product,
                selectedColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF262626)
                    : const Color(0xFFECECEC),
                backgroundColor: Colors.transparent,
                labelStyle: TextStyle(
                  color: state.mode == product
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: state.mode == product
                      ? FontWeight.w700
                      : FontWeight.w500,
                  fontSize: 13,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                showCheckmark: false,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onSelected: (_) => unawaited(state.selectMode(product)),
              ),
            ),
        ],
      ),
    );
  }
}

class MarketListHeading extends StatelessWidget {
  const MarketListHeading({this.sortByChange, this.onSort, super.key});
  final bool? sortByChange;
  final VoidCallback? onSort;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 4,
        child: Text(
          '币对 / 交易量',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 3,
        child: Text(
          '最新价格',
          textAlign: TextAlign.end,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 76,
        child: InkWell(
          onTap: onSort,
          child: Text(
            '涨跌幅${sortByChange == true ? ' ↓' : ''}',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ),
      ),
    ],
  );
}

class MarketsPage extends StatefulWidget {
  const MarketsPage({super.key});
  @override
  State<MarketsPage> createState() => _MarketsPageState();
}

class _MarketsPageState extends State<MarketsPage> {
  String query = '';
  bool sortByChange = false;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.instruments
        .where(
          (i) =>
              i.mode == state.mode &&
              i.symbol.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    if (sortByChange) {
      items.sort(
        (a, b) => (b.change24h ?? double.negativeInfinity).compareTo(
          a.change24h ?? double.negativeInfinity,
        ),
      );
    }
    return Material(
      color: exchangeBackground(context),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: MarketProductStrip(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ExchangeSearchField(
              key: const ValueKey('market-search'),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: MarketListHeading(
              sortByChange: sortByChange,
              onSort: () => setState(() => sortByChange = !sortByChange),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: state.refreshInstruments,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('暂无匹配的交易对')),
                    ),
                  for (final instrument in items)
                    PublicMarketRow(instrument: instrument),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PublicMarketRow extends StatelessWidget {
  const PublicMarketRow({required this.instrument, super.key});
  final Instrument instrument;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final price = state.latestPriceFor(instrument) ?? instrument.lastPrice;
    final change = instrument.change24h;
    final colors = Theme.of(context).colorScheme;
    final fiatCurrency = state.valuationCurrency == ValuationCurrency.usdt
        ? ValuationCurrency.cny
        : state.valuationCurrency;
    final usdRate = state.valuationRates[ValuationCurrency.usd];
    final quoteRate = switch (instrument.quoteAsset.toUpperCase()) {
      'USDT' => 1.0,
      'USD' =>
        usdRate != null && usdRate.isFinite && usdRate > 0 ? 1 / usdRate : null,
      final asset => state.walletAssetPricesUsdt[asset],
    };
    final fiatRate = state.valuationRates[fiatCurrency];
    final fiat = price == null || quoteRate == null || fiatRate == null
        ? null
        : price * quoteRate * fiatRate;
    String volume(double? value) => value == null
        ? '—'
        : value >= 100000000
        ? '${(value / 100000000).toStringAsFixed(2)}亿'
        : value >= 10000
        ? '${(value / 10000).toStringAsFixed(2)}万'
        : money(value, digits: 2);
    return InkWell(
      onTap: () async {
        await state.selectInstrument(instrument);
        if (!context.mounted ||
            state.selectedInstrument.instrumentId != instrument.instrumentId ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const MarketChartPage()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CoinIcon(instrument.baseAsset, size: 30),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          instrument.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          volume(instrument.volume24h),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price == null
                        ? '—'
                        : groupedMoney(
                            price,
                            digits: instrument.pricePrecision,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFeatures: exchangeNumberFeatures,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    fiat == null
                        ? '—'
                        : '${fiatCurrency.code} ${groupedMoney(fiat, digits: 2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 76,
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: change == null
                    ? exchangePanel(context)
                    : change >= 0
                    ? const Color(0xFF15803D)
                    : const Color(0xFFC83E65),
                borderRadius: BorderRadius.circular(5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    change == null
                        ? '—'
                        : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                    style: TextStyle(
                      color: change == null
                          ? colors.onSurfaceVariant
                          : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFeatures: exchangeNumberFeatures,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: selected ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: ClientColors.warning,
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
            return Center(
              child: Icon(
                Icons.format_list_bulleted,
                color: Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
            );
          }
          final selected = index == 0;
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                values[index],
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
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
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Text(
              '名称↕ / 成交额↕',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '最新价格↕',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(width: 7),
          SizedBox(
            width: 78,
            child: Text(
              '24 小时涨跌↕',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
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
    final change = instrument.change24h;
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
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .28)
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
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  instrument.contractLabel,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
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
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                        : '${instrument.quoteAsset} ${money(latestPrice, digits: 2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
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
                color: change == null
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : change >= 0
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: change == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : change >= 0
                      ? Theme.of(context).colorScheme.onTertiary
                      : Theme.of(context).colorScheme.onError,
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
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                instrument.baseAsset.isEmpty
                    ? '?'
                    : instrument.baseAsset.substring(0, 1),
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary,
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
                    '${instrument.mode.label} · ${instrument.status}${instrument.isOption ? '' : ' · ${(instrument.maxLeveragePpm / 1000000).round()}X'}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            MetricPill(
              label: '最新',
              value: latestPrice == null
                  ? '--'
                  : money(latestPrice, digits: instrument.pricePrecision),
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

String volumeText(Instrument instrument) => instrument.volume24h == null
    ? '--'
    : money(instrument.volume24h!, digits: 2);
