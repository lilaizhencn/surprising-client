import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';

const exchangeAccent = Color(0xFFB7FF26);
const exchangeNumberFeatures = [FontFeature.tabularFigures()];

Color exchangePanel(BuildContext context) =>
    Theme.of(context).colorScheme.surfaceContainerHighest;

Color exchangeIncomeColor(BuildContext context, double? amount) =>
    amount == null
    ? Theme.of(context).colorScheme.onSurfaceVariant
    : amount >= 0
    ? Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF38C979)
          : const Color(0xFF15803D)
    : const Color(0xFFC83E65);

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
    Theme.of(context).colorScheme.surfaceDim;

ButtonStyle exchangeIconStyle(BuildContext context) => IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  foregroundColor: Theme.of(context).colorScheme.onSurface,
  side: BorderSide.none,
  shape: const CircleBorder(),
);

class ExchangeSearchField extends StatefulWidget {
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
  State<ExchangeSearchField> createState() => _ExchangeSearchFieldState();
}

class _ExchangeSearchFieldState extends State<ExchangeSearchField> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('exchange-search-input'),
            controller: controller,
            onChanged: (value) {
              setState(() {});
              widget.onChanged(value);
            },
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search, size: 23),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      style: exchangeIconStyle(context),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        setState(controller.clear);
                        widget.onChanged('');
                      },
                    ),
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
        if (widget.onScan != null) ...[
          const SizedBox(width: 9),
          IconButton.filledTonal(
            onPressed: widget.onScan,
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

class ExchangeValueRow extends StatelessWidget {
  const ExchangeValueRow({
    required this.state,
    required this.value,
    this.valueKey,
    super.key,
  });
  final AppState state;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            key: valueKey,
            style: const TextStyle(
              fontSize: 40,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.8,
              fontFeatures: exchangeNumberFeatures,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      DropdownButtonHideUnderline(
        child: DropdownButton<ValuationCurrency>(
          value: state.valuationCurrency,
          borderRadius: BorderRadius.circular(16),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: [
            for (final currency in ValuationCurrency.values)
              DropdownMenuItem(value: currency, child: Text(currency.code)),
          ],
          onChanged: (value) {
            if (value != null) state.selectValuationCurrency(value);
          },
        ),
      ),
    ],
  );
}

class ExchangeIncomeLine extends StatelessWidget {
  const ExchangeIncomeLine({
    required this.amount,
    required this.percent,
    required this.hidden,
    this.onTap,
    super.key,
  });
  final double? amount, percent;
  final bool hidden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final value = hidden
        ? '••••••'
        : amount == null
        ? '—'
        : '${amount! > 0 ? '+' : ''}${groupedMoney(amount!)}';
    final rate = hidden || percent == null
        ? ''
        : ' (${percent! >= 0 ? '+' : ''}${percent!.toStringAsFixed(2)}%)';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Flexible(
            child: Text.rich(
              TextSpan(
                text: '今日收益 ',
                children: [
                  TextSpan(
                    text: '$value$rate',
                    style: TextStyle(
                      color: exchangeIncomeColor(
                        context,
                        hidden ? null : amount,
                      ),
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 14,
                color: muted,
                fontFeatures: exchangeNumberFeatures,
              ),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, size: 18, color: muted),
        ],
      ),
    );
  }
}

class AccountValueHeader extends StatefulWidget {
  const AccountValueHeader({required this.state, this.onTap, super.key});
  final AppState state;
  final VoidCallback? onTap;
  @override
  State<AccountValueHeader> createState() => _AccountValueHeaderState();
}

class _AccountValueHeaderState extends State<AccountValueHeader> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final income = state.portfolioIncome();
    final total = state.valuationAmount(income?.equityValue);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final pnl = state.valuationAmount(income?.amountValue);
    final pnlPercent = income?.percentValue;
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
        ExchangeValueRow(state: state, value: shown(total)),
        const SizedBox(height: 10),
        ExchangeIncomeLine(
          amount: pnl,
          percent: pnlPercent,
          hidden: hidden,
          onTap: widget.onTap,
        ),
      ],
    );
  }
}
