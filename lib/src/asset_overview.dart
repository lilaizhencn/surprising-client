import 'package:flutter/material.dart';
import 'app_state.dart';
import 'exchange_widgets.dart';
import 'models.dart';

class AssetOverview extends StatefulWidget {
  const AssetOverview({
    required this.state,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onTools,
    this.onRecords,
    this.onSecurity,
    super.key,
  });
  final AppState state;
  final VoidCallback onDeposit, onWithdraw, onTools;
  final VoidCallback? onRecords, onSecurity;
  @override
  State<AssetOverview> createState() => _AssetOverviewState();
}

class _AssetOverviewState extends State<AssetOverview> {
  String account = 'overview';
  bool hidden = false, hideZero = false;

  Map<String, String> get labels => {
    'overview': '总览',
    'funding': '资金账户',
    'trading': '交易账户',
    for (final p in ProductMode.values.where((p) => !p.isSpot))
      p.accountType: p.label,
  };

  void filters() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, updateSheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in labels.entries)
                ListTile(
                  title: Text(entry.value),
                  selected: account == entry.key,
                  trailing: account == entry.key
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    setState(() => account = entry.key);
                    Navigator.pop(sheet);
                  },
                ),
              CheckboxListTile(
                title: const Text('隐藏零余额'),
                value: hideZero,
                onChanged: (value) {
                  setState(() => hideZero = value ?? false);
                  updateSheet(() {});
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurfaceVariant;
    final fill = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF111111)
        : const Color(0xFFF4F4F4);
    final product = ProductMode.values
        .where((p) => p.accountType == account)
        .firstOrNull;
    final funding = state.isLoggedIn && state.walletReady
        ? state.walletPortfolioUsdt(state.walletPortfolio)
        : null;
    final trading = state.productBalancesUsdt(includeSpot: false);
    final total = switch (account) {
      'overview' =>
        funding == null || trading == null ? null : funding + trading,
      'funding' => funding,
      'trading' => trading,
      _ => state.productBalancesUsdt(product: product),
    };
    String shown(double? value, {int digits = 2}) => hidden
        ? '••••••'
        : value == null
        ? '—'
        : groupedMoney(value, digits: digits);

    final rows =
        <
          String,
          List<
            ({String account, double equity, double available, double locked})
          >
        >{};
    void add(
      String asset,
      String name,
      double equity,
      double available,
      double locked,
    ) {
      rows.putIfAbsent(asset.toUpperCase(), () => []).add((
        account: name,
        equity: equity,
        available: available,
        locked: locked,
      ));
    }

    if (state.isLoggedIn) {
      if ((account == 'overview' || account == 'funding') &&
          state.walletReady) {
        for (final a in state.walletPortfolio.assets) {
          add(
            a.symbol,
            '资金账户',
            a.totalBalance,
            a.availableBalance,
            a.lockedBalance,
          );
        }
      }
      for (final p in ProductMode.values.where((p) => !p.isSpot)) {
        if (account != 'overview' && account != 'trading' && product != p) {
          continue;
        }
        if (!state.productAssetsReady(p)) continue;
        for (final b in state.productBalances[p] ?? <ProductBalance>[]) {
          final equity = b.equity, available = b.available, locked = b.locked;
          if (equity == null || available == null || locked == null) continue;
          add(b.asset, p.label, equity, available, locked);
        }
      }
    }
    final assets =
        rows.keys
            .where(
              (asset) =>
                  !hideZero ||
                  rows[asset]!.any(
                    (row) =>
                        row.equity != 0 ||
                        row.available != 0 ||
                        row.locked != 0,
                  ),
            )
            .toList()
          ..sort();

    Widget action(String label, IconData icon, VoidCallback onTap) => Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            IconButton.filled(
              onPressed: onTap,
              tooltip: label,
              icon: Icon(icon, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: exchangeAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size.square(54),
                shape: const CircleBorder(),
                side: BorderSide.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    Widget card(String key, double? value, IconData icon) => Expanded(
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('asset-account-$key'),
          onTap: () =>
              setState(() => account = account == key ? 'overview' : key),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: account == key ? colors.primary : muted,
                ),
                const SizedBox(height: 10),
                Text(
                  labels[key]!,
                  style: TextStyle(color: muted, fontSize: 15),
                ),
                const SizedBox(height: 18),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${shown(state.valuationAmount(value))} ${state.valuationCurrency.code}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              account == 'overview' ? '总资产估值' : labels[account]!,
              style: TextStyle(color: muted, fontSize: 14),
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
                shape: const CircleBorder(),
              ),
            ),
            const Spacer(),
            if (widget.onSecurity != null)
              IconButton(
                onPressed: widget.onSecurity,
                style: exchangeIconStyle(context),
                tooltip: '资产安全',
                icon: const Icon(Icons.shield_outlined),
              ),
            if (widget.onRecords != null)
              IconButton(
                onPressed: widget.onRecords,
                style: exchangeIconStyle(context),
                tooltip: '资金记录',
                icon: const Icon(Icons.history),
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  shown(state.valuationAmount(total)),
                  key: const ValueKey('asset-total'),
                  style: const TextStyle(
                    fontSize: 40,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButtonHideUnderline(
              child: DropdownButton<ValuationCurrency>(
                value: state.valuationCurrency,
                isDense: true,
                items: [
                  for (final c in ValuationCurrency.values)
                    DropdownMenuItem(
                      value: c,
                      child: Text(c.code, style: const TextStyle(fontSize: 16)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) state.selectValuationCurrency(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '今日收益 ${hidden ? '••••••' : '—'}',
          style: TextStyle(color: muted, fontSize: 14),
        ),
        const SizedBox(height: 30),
        Row(
          key: const ValueKey('asset-actions'),
          children: [
            action('充值', Icons.south, widget.onDeposit),
            action('提币', Icons.north, widget.onWithdraw),
            action('划转', Icons.swap_horiz, widget.onTools),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Expanded(
              child: Text(
                '资产组合',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: filters,
              style: exchangeIconStyle(context),
              tooltip: '资产筛选',
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            card('funding', funding, Icons.account_balance_wallet_outlined),
            const SizedBox(width: 8),
            card('trading', trading, Icons.swap_horiz),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                '代币',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            if (account != 'overview')
              TextButton(
                onPressed: () => setState(() => account = 'overview'),
                child: const Text('总览'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('名称/数量', style: TextStyle(color: muted)),
            Text('价值', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        if (state.isLoggedIn && total == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              account == 'funding' ? state.walletError ?? '资金账户同步中' : '部分账户同步中',
              style: TextStyle(color: muted),
            ),
          ),
        if (state.isLoggedIn && total != null && assets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('暂无资产')),
          ),
        for (final asset in assets)
          Builder(
            builder: (context) {
              final parts = rows[asset]!;
              final equity = parts.fold(0.0, (sum, row) => sum + row.equity);
              final price = asset == 'USDT'
                  ? 1.0
                  : state.walletAssetPricesUsdt[asset];
              final value = equity == 0
                  ? 0.0
                  : price == null
                  ? null
                  : state.valuationAmount(equity * price);
              return ExpansionTile(
                key: ValueKey('asset-coin-$asset'),
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: CoinIcon(asset, size: 34),
                title: Text(
                  asset,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  hidden ? '••••••' : assetQuantity(equity),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                trailing: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .42,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${shown(value)} ${state.valuationCurrency.code}',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),
                children: [
                  for (final row in parts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              row.account,
                              style: TextStyle(color: muted),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '可用 ${hidden ? '••••••' : assetQuantity(row.available)}',
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  '冻结 ${hidden ? '••••••' : assetQuantity(row.locked)}',
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
