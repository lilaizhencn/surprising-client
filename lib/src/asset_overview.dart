import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

class AssetOverview extends StatefulWidget {
  const AssetOverview({
    required this.state,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onTools,
    this.onRecords,
    super.key,
  });
  final AppState state;
  final VoidCallback onDeposit, onWithdraw, onTools;
  final VoidCallback? onRecords;
  @override
  State<AssetOverview> createState() => _AssetOverviewState();
}

class _AssetOverviewState extends State<AssetOverview> {
  String account = 'overview';
  bool hidden = false, hideZero = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = Theme.of(context).colorScheme;
    final labels = <String, String>{
      'overview': '总览',
      'funding': '资金账户',
      for (final p in ProductMode.values) p.accountType: p.label,
    };
    final product = ProductMode.values
        .where((p) => p.accountType == account)
        .firstOrNull;
    final showFunding = account == 'funding';
    final showTrading = account != 'funding';
    final fundingReady = state.isLoggedIn && state.walletReady;
    final tradingReady = product == null
        ? state.assetsReady
        : state.productAssetsReady(product);
    final ready =
        state.isLoggedIn &&
        (!showFunding || fundingReady) &&
        (!showTrading || tradingReady);
    final tradingTotal = state.productBalancesUsdt(product: product);
    final fundingTotal = fundingReady
        ? state.walletPortfolioUsdt(state.walletPortfolio)
        : null;
    final usdt =
        ready &&
            (!showFunding || fundingTotal != null) &&
            (!showTrading || tradingTotal != null)
        ? (showFunding ? fundingTotal! : 0.0) +
              (showTrading ? tradingTotal! : 0.0)
        : null;
    final total = state.valuationAmount(usdt);
    String amount(double? value, {int digits = 4}) => hidden
        ? '••••••'
        : value == null
        ? '—'
        : value.toStringAsFixed(digits);

    Widget balanceRow(
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
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Row(
          children: [
            Expanded(
              child: Text(
                asset,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(child: Text(amount(equity), textAlign: TextAlign.end)),
          ],
        ),
        subtitle: Text(
          '≈ ${amount(value, digits: 2)} ${state.valuationCurrency.code}',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('可用 ${amount(available)}'),
              Text('冻结 ${amount(locked)}'),
            ],
          ),
        ],
      );
    }

    Widget accountRow(String key, double? value, bool available) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(key == 'funding' ? '资金账户（含现货）' : labels[key]!),
      subtitle: available
          ? null
          : Text(key == 'funding' ? state.walletError ?? '同步中' : '同步中'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${amount(available ? state.valuationAmount(value) : null, digits: 2)} ${state.valuationCurrency.code}',
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: () => setState(() => account = key),
    );

    Widget action(String label, IconData icon, VoidCallback onTap) => Expanded(
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: account == entry.key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => account = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                account == 'overview' ? '总资产' : labels[account]!,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ValuationCurrency>(
                    value: state.valuationCurrency,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    items: ValuationCurrency.values
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c.code,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (c) {
                      if (c != null) state.selectValuationCurrency(c);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  !state.isLoggedIn ? '登录后查看' : amount(total, digits: 2),
                  key: const ValueKey('asset-total'),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: hidden ? '显示资产' : '隐藏资产',
              onPressed: () => setState(() => hidden = !hidden),
              icon: Icon(
                hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
              ),
            ),
          ],
        ),
        if (state.isLoggedIn && total == null)
          Text(
            !ready
                ? (showFunding && state.walletError != null
                      ? state.walletError!
                      : '资产同步中')
                : '估值暂不可用',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        const SizedBox(height: 20),
        Row(
          key: const ValueKey('asset-actions'),
          children: [
            action('充值', Icons.south_west, widget.onDeposit),
            const SizedBox(width: 8),
            action('提币', Icons.north_east, widget.onWithdraw),
            const SizedBox(width: 8),
            action('划转', Icons.swap_horiz, widget.onTools),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                account == 'overview' ? '账户资产' : '资产明细',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.onRecords != null)
              TextButton.icon(
                onPressed: widget.onRecords,
                icon: const Icon(Icons.history, size: 16),
                label: const Text('记录'),
              ),
          ],
        ),
        if (state.isLoggedIn && account == 'overview') ...[
          accountRow(
            'funding',
            state.productBalancesUsdt(product: ProductMode.spot),
            state.productAssetsReady(ProductMode.spot),
          ),
          for (final p in ProductMode.values.where((p) => !p.isSpot))
            accountRow(
              p.accountType,
              state.productBalancesUsdt(product: p),
              state.productAssetsReady(p),
            ),
        ] else if (state.isLoggedIn) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Checkbox(
                value: hideZero,
                visualDensity: VisualDensity.compact,
                onChanged: (value) => setState(() => hideZero = value ?? false),
              ),
              const Text('隐藏零余额', style: TextStyle(fontSize: 12)),
            ],
          ),
          if (showFunding)
            if (!fundingReady)
              Text(state.walletError ?? '资金账户同步中')
            else if (state.walletPortfolio.assets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无资产', textAlign: TextAlign.center),
              )
            else
              for (final a in state.walletPortfolio.assets)
                if (!hideZero ||
                    a.totalBalance != 0 ||
                    a.availableBalance != 0 ||
                    a.lockedBalance != 0)
                  balanceRow(
                    a.symbol,
                    a.totalBalance,
                    a.availableBalance,
                    a.lockedBalance,
                  ),
          if (product != null)
            if (!state.productAssetsReady(product))
              const Text('资产同步中')
            else if ((state.productBalances[product] ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无资产', textAlign: TextAlign.center),
              )
            else
              for (final b in state.productBalances[product]!)
                if (!hideZero ||
                    b.equityUnits != 0 ||
                    b.availableUnits != 0 ||
                    b.lockedUnits != 0)
                  balanceRow(b.asset, b.equity, b.available, b.locked),
        ],
      ],
    );
  }
}
