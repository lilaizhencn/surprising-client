import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../ui/client_components.dart';
import '../ui/crypto_avatar.dart';
import 'wallet_components.dart';

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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
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
                            color: Theme.of(context).colorScheme.onSurface,
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
            Row(
              children: [
                Text(
                  '网络',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
                ),
                Spacer(),
                Text(
                  '到账时间/最小充币金额',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    DepositQrImage(
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
            Text(
              '地址 〉',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
