import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

/// Account selection filters the already subscribed private views, not the
/// trading screen's active instrument or subscriptions.
class AssetOverview extends StatefulWidget {
  const AssetOverview({
    required this.state,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onTools,
    super.key,
  });
  final AppState state;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;
  final VoidCallback onTools;

  @override
  State<AssetOverview> createState() => _AssetOverviewState();
}

class _AssetOverviewState extends State<AssetOverview> {
  String account = 'overview';
  bool hidden = false;
  bool hideZero = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final product = ProductMode.values
        .where((p) => p.accountType == account)
        .firstOrNull;
    final showFunding = account == 'overview' || account == 'funding';
    final fundingReady = state.isLoggedIn && state.walletReady;
    final products = product == null ? ProductMode.values : [product];
    final showTrading = account != 'funding';
    final tradingTotal = state.productBalancesUsdt(product: product);
    final fundingTotal = fundingReady
        ? state.walletPortfolioUsdt(state.walletPortfolio)
        : null;
    final ready =
        state.isLoggedIn &&
        (!showFunding || fundingReady) &&
        (!showTrading ||
            (product == null
                ? state.assetsReady
                : state.valuedProducts.contains(product) &&
                      state.privateViews[product]?.ready == true));
    final usdt =
        (!showFunding || fundingTotal != null) &&
            (!showTrading || tradingTotal != null)
        ? (showFunding ? fundingTotal! : 0.0) +
              (showTrading ? tradingTotal! : 0.0)
        : null;
    final total = ready ? state.valuationAmount(usdt) : null;
    String amount(double? value, {int digits = 4}) => hidden
        ? '••••••'
        : value == null
        ? '—'
        : value.toStringAsFixed(digits);
    Widget row(
      String label,
      String asset,
      double equity,
      double available,
      double locked,
    ) {
      final price = asset.toUpperCase() == 'USDT'
          ? 1.0
          : state.walletAssetPricesUsdt[asset.toUpperCase()];
      final value = equity == 0
          ? 0.0
          : price == null
          ? null
          : state.valuationAmount(equity * price);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label · $asset',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('权益 ${amount(equity)}'),
                  Text('可用 ${amount(available)}'),
                  Text('冻结 ${amount(locked)}'),
                  Text(
                    '估值 ${amount(value, digits: 2)} ${state.valuationCurrency.code}',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '资产估值',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: hidden ? '显示资产' : '隐藏资产',
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            DropdownButton<ValuationCurrency>(
              value: state.valuationCurrency,
              items: ValuationCurrency.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.code)))
                  .toList(),
              onChanged: (c) {
                if (c != null) state.selectValuationCurrency(c);
              },
            ),
          ],
        ),
        Text(
          !state.isLoggedIn ? '登录后查看' : amount(total, digits: 2),
          key: const ValueKey('asset-total'),
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
        ),
        if (state.isLoggedIn && total == null)
          Text(
            !ready
                ? (state.walletError != null && showFunding
                      ? state.walletError!
                      : '资产同步中')
                : '估值暂不可用',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onDeposit,
              icon: const Icon(Icons.south_west),
              label: const Text('充币'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onWithdraw,
              icon: const Icon(Icons.north_east),
              label: const Text('提币'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onTools,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('划转 / 资金记录'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in <String, String>{
                'overview': '总览',
                'funding': '资金账户',
                for (final p in ProductMode.values) p.accountType: p.label,
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: account == entry.key,
                    onSelected: (_) => setState(() => account = entry.key),
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('隐藏零余额'),
          value: hideZero,
          onChanged: (value) => setState(() => hideZero = value),
        ),
        if (state.isLoggedIn && showFunding) ...[
          if (!fundingReady)
            Text(state.walletError ?? '资金账户同步中')
          else if (state.walletPortfolio.assets.isEmpty)
            const Text('资金账户暂无资产')
          else
            for (final a in state.walletPortfolio.assets)
              if (!hideZero ||
                  a.totalBalance != 0 ||
                  a.availableBalance != 0 ||
                  a.lockedBalance != 0)
                row(
                  '资金账户',
                  a.symbol,
                  a.totalBalance,
                  a.availableBalance,
                  a.lockedBalance,
                ),
        ],
        if (state.isLoggedIn && showTrading)
          for (final p in products)
            if (!state.valuedProducts.contains(p) ||
                state.privateViews[p]?.ready != true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('${p.label} · 资产同步中'),
              )
            else if ((state.productBalances[p] ?? []).isEmpty)
              Text('${p.label} · 暂无资产')
            else
              for (final b in state.productBalances[p]!)
                if (!hideZero ||
                    b.equityUnits != 0 ||
                    b.availableUnits != 0 ||
                    b.lockedUnits != 0)
                  row(p.label, b.asset, b.equity, b.available, b.locked),
      ],
    );
  }
}
