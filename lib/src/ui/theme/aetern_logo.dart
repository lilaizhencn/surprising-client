import 'package:material_ui/material_ui.dart';
import 'tokens.dart';

class AeternLogoMark extends StatelessWidget {
  const AeternLogoMark({this.size = 28, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      label: 'AETERN',
      child: CustomPaint(
        size: Size.square(size),
        painter: _AeternMarkPainter(t),
      ),
    );
  }
}

class AeternBrandLockup extends StatelessWidget {
  const AeternBrandLockup({this.markSize = 28, this.fontSize = 18, super.key});
  final double markSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AeternLogoMark(size: markSize),
        const SizedBox(width: 10),
        Text(
          'AETERN',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: fontSize * 0.12,
          ),
        ),
      ],
    );
  }
}

class _AeternMarkPainter extends CustomPainter {
  const _AeternMarkPainter(this.tokens);
  final SurprisingTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1.5 * s, 1.5 * s, 29 * s, 29 * s),
      Radius.circular(8 * s),
    );

    canvas.drawRRect(rect, Paint()..color = tokens.bgVoid);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25 * s
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.auroraCyan.withValues(alpha: 0.72),
            tokens.auroraViolet.withValues(alpha: 0.45),
            tokens.auroraMagenta.withValues(alpha: 0.72),
          ],
        ).createShader(rect.outerRect),
    );

    final apex = Path()
      ..moveTo(16 * s, 6.2 * s)
      ..lineTo(24.4 * s, 24.4 * s)
      ..lineTo(20.8 * s, 24.4 * s)
      ..lineTo(16 * s, 13.6 * s)
      ..lineTo(11.2 * s, 24.4 * s)
      ..lineTo(7.6 * s, 24.4 * s)
      ..close();
    canvas.drawPath(apex, Paint()..color = tokens.textPrimary);

    final infinity = Path()
      ..moveTo(9.4 * s, 18.4 * s)
      ..cubicTo(9.4 * s, 16.2 * s, 12.9 * s, 16.2 * s, 16 * s, 18.4 * s)
      ..cubicTo(19.1 * s, 20.6 * s, 22.6 * s, 20.6 * s, 22.6 * s, 18.4 * s)
      ..cubicTo(22.6 * s, 16.2 * s, 19.1 * s, 16.2 * s, 16 * s, 18.4 * s)
      ..cubicTo(12.9 * s, 20.6 * s, 9.4 * s, 20.6 * s, 9.4 * s, 18.4 * s)
      ..close();
    canvas.drawPath(
      infinity,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1 * s
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = tokens.auroraPrimaryGradient.createShader(
          Rect.fromLTWH(4 * s, 4 * s, 24 * s, 24 * s),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _AeternMarkPainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}
