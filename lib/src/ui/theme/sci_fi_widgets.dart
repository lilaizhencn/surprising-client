import 'package:material_ui/material_ui.dart';
import 'tokens.dart';

/// Deep-space radial aurora backdrop; automatically degrades to static bgVoid
/// when reduced-motion / high-contrast is enabled.
class SurprisingAuroraBackdrop extends StatelessWidget {
  const SurprisingAuroraBackdrop({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context);
    if (reduced) {
      return ColoredBox(color: t.bgVoid, child: child);
    }
    return CustomPaint(
      painter: _AuroraPainter(t),
      child: child,
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.tokens);
  final SurprisingTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = tokens.bgVoid);

    final cyanPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.75, -0.9),
        radius: 0.9,
        colors: [
          tokens.auroraCyan.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, cyanPaint);

    final magentaPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.85, -0.8),
        radius: 0.85,
        colors: [
          tokens.auroraMagenta.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, magentaPaint);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}

/// 5-cell ADL energy indicator matching Web's AdlEnergyBar.
class SurprisingAdlEnergyBar extends StatelessWidget {
  const SurprisingAdlEnergyBar({required this.level, this.max = 5, super.key});
  final int level;
  final int max;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final clamped = level.clamp(0, max);
    final activeColor = clamped <= 2
        ? t.upBase
        : clamped <= 3
        ? t.warning
        : t.danger;
    return Semantics(
      label: 'ADL risk level $clamped of $max',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Container(
              width: 4,
              height: 12,
              margin: EdgeInsets.only(right: i == max - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < clamped ? activeColor : t.bgElevated3,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
