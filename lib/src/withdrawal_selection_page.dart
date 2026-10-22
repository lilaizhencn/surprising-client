import 'dart:async';
import 'package:flutter/material.dart';
import 'app_scope.dart';
import 'wallet/withdrawal_page.dart' show WithdrawalPage;
import 'exchange_widgets.dart';
import 'funding_records_page.dart';
import 'sensitive_screen.dart';

/// The caller mounts this only after SensitiveScreen has protected the window.
class WithdrawalSelectionPage extends StatefulWidget {
  const WithdrawalSelectionPage({super.key});
  @override
  State<WithdrawalSelectionPage> createState() =>
      _WithdrawalSelectionPageState();
}

class _WithdrawalSelectionPageState extends State<WithdrawalSelectionPage> {
  String query = '';
  String? symbol;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final token = state.session?.accessToken;
    final colors = Theme.of(context).colorScheme;
    final assets = state.walletPortfolio.assets
        .where(
          (asset) =>
              state.withdrawalRules.any(
                (rule) => rule.symbol == asset.symbol && rule.withdrawalEnabled,
              ) &&
              asset.symbol.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final selected = state.walletPortfolio.assets
        .where((asset) => asset.symbol == symbol)
        .firstOrNull;
    final chains = selected == null
        ? null
        : state.withdrawalRules
              .where(
                (rule) =>
                    rule.symbol == selected.symbol && rule.withdrawalEnabled,
              )
              .toList();
    void back() {
      if (symbol == null) {
        Navigator.maybePop(context);
      } else {
        setState(() => symbol = null);
      }
    }

    return PopScope(
      canPop: symbol == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: exchangeBackground(context),
        appBar: AppBar(
          backgroundColor: exchangeBackground(context),
          centerTitle: true,
          leading: IconButton(
            onPressed: back,
            style: exchangeIconStyle(context),
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Text(symbol == null ? '选择资产' : '选择网络'),
          actions: [
            IconButton(
              style: exchangeIconStyle(context),
              onPressed: token == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => SensitiveScreen(
                          child: FundingRecordsPage(
                            state: state,
                            initialCategory: 'withdrawal',
                          ),
                        ),
                      ),
                    ),
              tooltip: '提币记录',
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        body: token == null
            ? const Center(child: Text('登录已失效，请重新登录'))
            : !state.walletReady || !state.withdrawalRulesReady
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.walletError ?? '可提币资产暂不可用'),
                    TextButton(
                      onPressed: () => unawaited(
                        Future.wait([
                          state.refreshWallet(),
                          state.refreshWithdrawalRules(),
                        ]),
                      ),
                      child: const Text('刷新资产'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 30),
                children: [
                  if (symbol == null) ...[
                    ExchangeSearchField(
                      onChanged: (value) => setState(() => query = value),
                      hintText: '搜索数字货币',
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '数字货币',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '可用余额',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final asset in assets)
                      ListTile(
                        key: ValueKey('withdraw-asset-${asset.symbol}'),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        leading: CoinIcon(asset.symbol, size: 34),
                        title: Text(
                          asset.symbol,
                          style: const TextStyle(fontSize: 18),
                        ),
                        trailing: Text(
                          asset.availableAmount ?? '—',
                          style: const TextStyle(fontSize: 16),
                        ),
                        onTap: () {
                          if (token == state.session?.accessToken &&
                              state.walletReady) {
                            setState(() => symbol = asset.symbol);
                          }
                        },
                      ),
                    if (assets.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: Text('暂无可提币资产')),
                      ),
                  ] else ...[
                    Text(
                      '请选择与收款平台一致的网络',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    for (final chain in chains ?? [])
                      ListTile(
                        key: ValueKey('withdraw-network-${chain.chain}'),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        title: Text(
                          chain.network.isEmpty ? chain.chain : chain.network,
                          style: const TextStyle(fontSize: 17),
                        ),
                        subtitle: Text(chain.chain),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (token != state.session?.accessToken ||
                              !state.walletReady) {
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SensitiveScreen(
                                child: WithdrawalPage(
                                  initialSymbol: symbol,
                                  initialChain: chain.chain,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (chains == null || chains.isEmpty)
                      const Center(child: Text('暂无可用提币网络')),
                  ],
                ],
              ),
      ),
    );
  }
}
