import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

const exchangeAccent = Color(0xFFB7FF26);

String groupedMoney(double amount, {int digits = 2}) {
  final parts = money(amount, digits: digits).split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'\d(?=(\d{3})+$)'),
    (match) => '${match[0]},',
  );
  return parts.join('.');
}

String assetQuantity(double amount) {
  if (!amount.isFinite) return '—';
  if (amount == 0) return '0';
  if (amount != 0 && amount.abs() < .00000001) {
    return amount > 0 ? '<0.00000001' : '>-0.00000001';
  }
  return groupedMoney(
    amount,
    digits: 8,
  ).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

Color exchangeBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.black
    : Colors.white;

ButtonStyle exchangeIconStyle(BuildContext context) => IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: Theme.of(context).colorScheme.onSurface,
  side: BorderSide.none,
  shape: const CircleBorder(),
);

class ExchangeSearchField extends StatelessWidget {
  const ExchangeSearchField({
    required this.onChanged,
    this.onScan,
    this.hintText = '搜索交易对',
    super.key,
  });
  final ValueChanged<String> onChanged;
  final VoidCallback? onScan;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF222222) : const Color(0xFFF3F3F3);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('exchange-search-input'),
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search, size: 23),
              filled: true,
              fillColor: fill,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
        if (onScan != null) ...[
          const SizedBox(width: 9),
          IconButton.filledTonal(
            onPressed: onScan,
            tooltip: '扫一扫',
            style: IconButton.styleFrom(
              backgroundColor: fill,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size.square(48),
              shape: const CircleBorder(),
              side: BorderSide.none,
            ),
            icon: const Icon(Icons.qr_code_scanner, size: 24),
          ),
        ],
      ],
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon(this.symbol, {this.size = 32, super.key});
  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = symbol.toUpperCase();
    final color = switch (asset) {
      'BTC' => const Color(0xFFF7931A),
      'ETH' => const Color(0xFF627EEA),
      'USDT' => const Color(0xFF009B97),
      'USDC' => const Color(0xFF2775CA),
      'SOL' => const Color(0xFF6D5CDD),
      _ => const Color(0xFF505761),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: asset == 'ETH'
          ? CustomPaint(
              size: Size(size * .48, size * .7),
              painter: const _EtherGlyph(),
            )
          : Text(
              switch (asset) {
                'BTC' => '₿',
                'USDT' => '₮',
                'USDC' => '\$',
                'SOL' => '≋',
                _ => asset.isEmpty ? '·' : asset[0],
              },
              style: TextStyle(
                color: Colors.white,
                fontSize: size * .68,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
    );
  }
}

class _EtherGlyph extends CustomPainter {
  const _EtherGlyph();
  @override
  void paint(Canvas canvas, Size size) {
    final top = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height * .58)
      ..lineTo(size.width / 2, size.height * .73)
      ..lineTo(0, size.height * .58)
      ..close();
    final bottom = Path()
      ..moveTo(0, size.height * .66)
      ..lineTo(size.width / 2, size.height * .82)
      ..lineTo(size.width, size.height * .66)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(top, Paint()..color = Colors.white);
    canvas.drawPath(bottom, Paint()..color = const Color(0xFFCCD7FF));
  }

  @override
  bool shouldRepaint(_EtherGlyph oldDelegate) => false;
}

class AccountValueHeader extends StatefulWidget {
  const AccountValueHeader({
    required this.state,
    this.onTap,
    this.dailyPnl,
    this.dailyPnlPercent,
    super.key,
  });
  final AppState state;
  final VoidCallback? onTap;
  final double? dailyPnl, dailyPnlPercent;
  @override
  State<AccountValueHeader> createState() => _AccountValueHeaderState();
}

class _AccountValueHeaderState extends State<AccountValueHeader> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final funding = state.walletReady
        ? state.walletPortfolioUsdt(state.walletPortfolio)
        : null;
    // The funding API and SPOT private view describe the same cash balances.
    final trading = state.productBalancesUsdt(includeSpot: false);
    final total = funding == null || trading == null
        ? null
        : state.valuationAmount(funding + trading);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pnl = state.valuationAmount(widget.dailyPnl);
    String shown(double? amount) => hidden
        ? '••••••'
        : amount == null
        ? '—'
        : groupedMoney(amount, digits: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('总资产估值', style: TextStyle(color: muted, fontSize: 14)),
            IconButton(
              onPressed: () => setState(() => hidden = !hidden),
              tooltip: hidden ? '显示资产' : '隐藏资产',
              icon: Icon(
                hidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
                shape: const CircleBorder(),
              ),
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
                  shown(total),
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
                  for (final currency in ValuationCurrency.values)
                    DropdownMenuItem(
                      value: currency,
                      child: Text(
                        currency.code,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) state.selectValuationCurrency(value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        InkWell(
          onTap: widget.onTap,
          child: Row(
            children: [
              Text('今日收益 ', style: TextStyle(color: muted, fontSize: 14)),
              Flexible(
                child: Text(
                  '${pnl != null && pnl > 0 && !hidden ? '+' : ''}${shown(pnl)}${widget.dailyPnlPercent == null || hidden ? '' : ' (${widget.dailyPnlPercent! >= 0 ? '+' : ''}${widget.dailyPnlPercent!.toStringAsFixed(2)}%)'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: pnl == null
                        ? muted
                        : pnl >= 0
                        ? const Color(0xFF20A255)
                        : const Color(0xFFC83E65),
                  ),
                ),
              ),
              if (widget.onTap != null)
                Icon(Icons.chevron_right, size: 18, color: muted),
            ],
          ),
        ),
      ],
    );
  }
}
