import 'i18n/client_messages.dart';
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
                title: const LText('隐藏零余额'),
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
    final fill = exchangePanel(context);
    final product = ProductMode.values
        .where((p) => p.accountType == account)
        .firstOrNull;
    final detailProducts = account == 'overview' || account == 'trading'
        ? ProductMode.values.where((p) => !p.isSpot)
        : product == null
        ? <ProductMode>[]
        : [product];
    final detailsReady =
        state.isLoggedIn &&
        ((account != 'overview' && account != 'funding') ||
            state.walletReady) &&
        detailProducts.every(
          (p) =>
              state.productAssetsReady(p) &&
              (state.productBalances[p] ?? <ProductBalance>[]).every(
                (b) =>
                    b.equity != null && b.available != null && b.locked != null,
              ),
        );
    final income = state.portfolioIncome(account);
    final funding = state.portfolioIncome('funding')?.equityValue;
    final trading = state.portfolioIncome('trading')?.equityValue;
    final total = income?.equityValue;
    final pnl = state.valuationAmount(income?.amountValue);
    final pnlPercent = income?.percentValue;
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
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size.square(54),
                shape: const CircleBorder(),
                side: BorderSide.none,
              ),
            ),
            const SizedBox(height: 8),
            LText(
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: account == key ? colors.onSurface : Colors.transparent,
          ),
        ),
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
                  color: account == key ? colors.onSurface : muted,
                ),
                const SizedBox(height: 10),
                LText(
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
                      fontFeatures: exchangeNumberFeatures,
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
            LText(
              account == 'overview' ? '总资产估值' : labels[account]!,
              style: TextStyle(color: muted, fontSize: 14),
            ),
            IconButton(
              tooltip: clientLabel(context, hidden ? '显示资产' : '隐藏资产'),
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
                tooltip: clientLabel(context, '资产安全'),
                icon: const Icon(Icons.shield_outlined),
              ),
            if (widget.onRecords != null)
              IconButton(
                onPressed: widget.onRecords,
                style: exchangeIconStyle(context),
                tooltip: clientLabel(context, '资金记录'),
                icon: const Icon(Icons.history),
              ),
          ],
        ),
        ExchangeValueRow(
          state: state,
          value: shown(state.valuationAmount(total)),
          valueKey: const ValueKey('asset-total'),
        ),
        const SizedBox(height: 10),
        ExchangeIncomeLine(amount: pnl, percent: pnlPercent, hidden: hidden),
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
              child: LText(
                '资产组合',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              onPressed: filters,
              style: exchangeIconStyle(context),
              tooltip: clientLabel(context, '资产筛选'),
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
              child: LText(
                '代币',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            if (account != 'overview')
              TextButton(
                onPressed: () => setState(() => account = 'overview'),
                child: const LText('总览'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LText('名称/数量', style: TextStyle(color: muted)),
            LText('价值', style: TextStyle(color: muted)),
          ],
        ),
        const SizedBox(height: 8),
        if (state.isLoggedIn && !detailsReady)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: LText(
              account == 'funding' ? state.walletError ?? '资金账户同步中' : '资产明细同步中',
              style: TextStyle(color: muted),
            ),
          ),
        if (state.isLoggedIn && detailsReady && assets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: LText('暂无资产')),
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
                      style: const TextStyle(
                        fontSize: 15,
                        fontFeatures: exchangeNumberFeatures,
                      ),
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
                            child: LText(
                              row.account,
                              style: TextStyle(color: muted),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: LText(
                                  '可用 ${hidden ? '••••••' : assetQuantity(row.available)}',
                                ),
                              ),
                              Flexible(
                                child: LText(
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
