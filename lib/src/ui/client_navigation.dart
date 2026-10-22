import 'package:flutter/material.dart';
import '../app_scope.dart';
import 'client_components.dart';

class ClientNavigation extends InheritedWidget {
  const ClientNavigation({
    required this.openBuyCrypto,
    required this.openAnnouncements,
    required super.child,
    super.key,
  });

  final VoidCallback openBuyCrypto;
  final VoidCallback openAnnouncements;

  static ClientNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ClientNavigation>();

  @override
  bool updateShouldNotify(ClientNavigation oldWidget) => false;
}

class ExchangeBottomNav extends StatelessWidget {
  const ExchangeBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final language = AppScope.of(context).language;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final exchangeItems = [
      _ExchangeNavItem(
        Icons.grid_view_outlined,
        Icons.grid_view,
        clientText(language, '首页', 'Home'),
      ),
      _ExchangeNavItem(
        Icons.show_chart,
        Icons.show_chart,
        clientText(language, '行情', 'Markets'),
      ),
      _ExchangeNavItem(
        Icons.sync_alt,
        Icons.sync_alt,
        clientText(language, '交易', 'Trade'),
      ),
      _ExchangeNavItem(Icons.handshake_outlined, Icons.handshake, 'C2C'),
      _ExchangeNavItem(
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet,
        clientText(language, '资产', 'Assets'),
      ),
    ];
    return Container(
      height: 56 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: .7,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < exchangeItems.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(i),
                child: _ExchangeNavButton(
                  item: exchangeItems[i],
                  selected: selectedIndex == i,
                  central: i == 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExchangeNavItem {
  const _ExchangeNavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _ExchangeNavButton extends StatelessWidget {
  const _ExchangeNavButton({
    required this.item,
    required this.selected,
    this.central = false,
  });

  final _ExchangeNavItem item;
  final bool selected;
  final bool central;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    if (central) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -13,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.sync_alt,
                  color: Colors.black,
                  size: 31,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Text(
              item.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: selected
                    ? selectedColor
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          selected ? item.selectedIcon : item.icon,
          color: selected
              ? selectedColor
              : Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            color: selected
                ? selectedColor
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: selected ? 14 : 0,
          height: 2,
          decoration: BoxDecoration(
            color: selectedColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class ExchangeNavGlyph extends StatelessWidget {
  const ExchangeNavGlyph({
    required this.label,
    required this.color,
    required this.selected,
    super.key,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(24),
      painter: _ExchangeNavGlyphPainter(
        label: label,
        color: color,
        selected: selected,
      ),
    );
  }
}

class _ExchangeNavGlyphPainter extends CustomPainter {
  const _ExchangeNavGlyphPainter({
    required this.label,
    required this.color,
    required this.selected,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.4 : 2.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (label) {
      case '首页':
        _drawHome(canvas, size, fill);
      case '行情':
        _drawMarket(canvas, size, stroke);
      case '探索':
        _drawExplore(canvas, size, fill);
      case '交易':
        _drawTrade(canvas, size, stroke);
      case '合约':
        _drawContract(canvas, size, stroke, fill);
      case '资产':
        _drawWallet(canvas, size, stroke, fill);
      default:
        canvas.drawCircle(size.center(Offset.zero), size.width * .34, stroke);
    }
  }

  void _drawExplore(Canvas canvas, Size size, Paint fill) {
    final center = size.center(Offset.zero);
    final path = Path()
      ..moveTo(center.dx, size.height * .16)
      ..lineTo(size.width * .72, size.height * .72)
      ..lineTo(center.dx, size.height * .60)
      ..lineTo(size.width * .28, size.height * .72)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _drawHome(Canvas canvas, Size size, Paint fill) {
    final unit = size.width / 5.6;
    final gap = unit * .54;
    final start = Offset(size.width * .18, size.height * .18);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        final rect = Rect.fromLTWH(
          start.dx + col * (unit + gap),
          start.dy + row * (unit + gap),
          unit,
          unit,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(unit * .14)),
          fill,
        );
      }
    }
  }

  void _drawMarket(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .70)
      ..lineTo(size.width * .34, size.height * .52)
      ..lineTo(size.width * .48, size.height * .62)
      ..lineTo(size.width * .75, size.height * .34);
    canvas.drawPath(path, stroke);
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .75, size.height * .52),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .57, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .18, size.height * .82),
      Offset(size.width * .68, size.height * .82),
      stroke,
    );
  }

  void _drawTrade(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * .22, size.height * .34),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .22),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .46),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .78, size.height * .66),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .54),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .78),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
  }

  void _drawContract(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .24,
      size.height * .14,
      size.width * .50,
      size.height * .68,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .06)),
      stroke,
    );
    for (final y in [.32, .48, .64]) {
      canvas.drawLine(
        Offset(size.width * .34, size.height * y),
        Offset(size.width * .64, size.height * y),
        stroke,
      );
    }
    final diamond = Path()
      ..moveTo(size.width * .76, size.height * .70)
      ..lineTo(size.width * .84, size.height * .78)
      ..lineTo(size.width * .76, size.height * .86)
      ..lineTo(size.width * .68, size.height * .78)
      ..close();
    canvas.drawPath(diamond, fill);
  }

  void _drawWallet(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .17,
      size.height * .25,
      size.width * .66,
      size.height * .50,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .08)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .27, size.height * .25),
      Offset(size.width * .43, size.height * .12),
      stroke,
    );
    final pocket = Rect.fromLTWH(
      size.width * .54,
      size.height * .41,
      size.width * .29,
      size.height * .22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pocket, Radius.circular(size.width * .05)),
      stroke,
    );
    canvas.drawCircle(Offset(size.width * .65, size.height * .52), 1.5, fill);
  }

  @override
  bool shouldRepaint(covariant _ExchangeNavGlyphPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}
