import 'package:flutter/material.dart';
import '../app_scope.dart';
import 'client_components.dart';
import 'client_glass.dart';

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

List<_ExchangeNavItem> _exchangeItems(BuildContext context) {
  final language = AppScope.of(context).language;
  return [
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
    const _ExchangeNavItem(Icons.handshake_outlined, Icons.handshake, 'C2C'),
    _ExchangeNavItem(
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
      clientText(language, '资产', 'Assets'),
    ),
  ];
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
    final items = _exchangeItems(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ClientGlassSurface(
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _ExchangeNavButton(
                        item: items[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExchangeSideNav extends StatelessWidget {
  const ExchangeSideNav({
    required this.selectedIndex,
    required this.onSelected,
    this.extended = false,
    super.key,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;
  @override
  Widget build(BuildContext context) {
    final items = _exchangeItems(context);
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: ClientGlassSurface(
          radius: 24,
          child: SizedBox(
            width: extended ? 152 : 88,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Icon(
                    Icons.auto_awesome,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < items.length; i++)
                    SizedBox(
                      height: 76,
                      child: _ExchangeNavButton(
                        item: items[i],
                        selected: selectedIndex == i,
                        onTap: () => onSelected(i),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExchangeNavItem {
  const _ExchangeNavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon, selectedIcon;
  final String label;
}

class _ExchangeNavButton extends StatelessWidget {
  const _ExchangeNavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final _ExchangeNavItem item;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? colors.primary : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    color: selected ? colors.primary : colors.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
