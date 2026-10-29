import 'dart:convert';
import 'package:flutter/material.dart';
import '../models.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import '../ui/crypto_avatar.dart';

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
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).colorScheme.onSurface,
          size: 30,
        ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.tertiary.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '3.5% 年化收益',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
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
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
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
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
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
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurface,
              size: 16,
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        colors: [
          ClientColors.negative.withValues(alpha: .35),
          ClientColors.negative.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final dotPaint = Paint()
      ..color = ClientColors.negative.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    for (var x = 4.0; x < size.width; x += 8) {
      for (var y = size.height * .42; y < size.height; y += 8) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    final linePaint = Paint()
      ..color = ClientColors.negative
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String formatValuation(double? value, ValuationCurrency currency) {
  if (value == null || !value.isFinite) return '—';
  return '${currency.symbol}${money(value, digits: 2)}';
}

class WalletTokenRow extends StatelessWidget {
  const WalletTokenRow({
    required this.asset,
    required this.priceUsdt,
    required this.currency,
    required this.valuationRate,
    super.key,
  });

  final WalletAssetSummary asset;
  final double? priceUsdt;
  final ValuationCurrency currency;
  final double? valuationRate;

  @override
  Widget build(BuildContext context) {
    final value = priceUsdt == null || valuationRate == null
        ? null
        : asset.totalBalance * priceUsdt! * valuationRate!;
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  money(asset.totalBalance, digits: 8),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatValuation(value, currency),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value == null ? '暂无实时估值' : '现货账户余额',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            value: scaledAmount(
              BigInt.from(balance.equityUnits),
              balance.scaleUnits,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '可用',
                  value: scaledAmount(
                    BigInt.from(balance.availableUnits),
                    balance.scaleUnits,
                  ),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: scaledAmount(
                    BigInt.from(balance.lockedUnits),
                    balance.scaleUnits,
                  ),
                  color: ClientColors.warningFor(context),
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DepositQrImage(dataUrl: address.qrCodeDataUrl),
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
                  style: TextStyle(
                    color: ClientColors.warningFor(context),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class DepositQrImage extends StatelessWidget {
  const DepositQrImage({required this.dataUrl, this.size = 96, super.key});

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
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: money(asset.lockedBalance, digits: 8),
                  color: ClientColors.warningFor(context),
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
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.12)
                : Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.12),
            child: Icon(
              isOut ? Icons.call_made : Icons.call_received,
              color: isOut
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
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
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.errorMessage.isNotEmpty)
                  Text(
                    record.errorMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
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
                  color: isOut
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.tertiary,
                ),
              ),
              if (record.fee > 0)
                Text(
                  'fee ${money(record.fee, digits: 8)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
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
              decoration: BoxDecoration(
                color: ClientColors.warningFor(context),
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
