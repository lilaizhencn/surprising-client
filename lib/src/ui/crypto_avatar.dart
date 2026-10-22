import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'client_colors.dart';

class CryptoAvatar extends StatelessWidget {
  const CryptoAvatar({required this.symbol, required this.size, super.key});

  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final upper = symbol.toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CryptoAvatarPainter(upper)),
    );
  }
}

class _CryptoAvatarPainter extends CustomPainter {
  const _CryptoAvatarPainter(this.symbol);

  final String symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final background = Paint()..color = assetColor(symbol);
    canvas.drawCircle(center, size.width / 2, background);

    switch (symbol) {
      case 'BTC':
        _drawText(canvas, size, 'B', Colors.white, .58, FontWeight.w900);
        _drawStroke(canvas, size, Colors.white.withValues(alpha: .9));
      case 'ETH':
        _drawEth(canvas, size);
      case 'USDT':
        _drawStable(canvas, size, 'T');
      case 'USDC':
        _drawStable(canvas, size, r'$');
      case 'USDG':
        _drawText(canvas, size, 'G', Colors.white, .58, FontWeight.w900);
      case 'SPEX':
      case 'SURPRISING CHAIN':
        _drawPlatformTokenMark(canvas, size);
      case 'SOL':
        _drawSol(canvas, size);
      case 'TRX':
        _drawTriangleMark(canvas, size, Colors.white);
      case 'XAU':
      case 'XAUT':
        _drawGold(canvas, size);
      case 'APT':
      case 'APTOS':
        _drawAptos(canvas, size);
      case 'ARB':
      case 'ARBITRUM':
        _drawHex(canvas, size);
      case 'AVAX':
      case 'AVALANCHE':
        _drawAvax(canvas, size);
      case 'BERA':
      case 'BERACHAIN':
        _drawText(
          canvas,
          size,
          'B',
          const Color(0xFF111111),
          .54,
          FontWeight.w900,
        );
      default:
        final label = symbol.isEmpty ? '?' : symbol.substring(0, 1);
        _drawText(
          canvas,
          size,
          label,
          ClientColors.foreground,
          .52,
          FontWeight.w800,
        );
    }
  }

  void _drawText(
    Canvas canvas,
    Size size,
    String text,
    Color color,
    double scale,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size.width * scale,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  void _drawStroke(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .035
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * .38, size.height * .24),
      Offset(size.width * .38, size.height * .76),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .58, size.height * .24),
      Offset(size.width * .58, size.height * .76),
      paint,
    );
  }

  void _drawEth(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final faint = Paint()..color = Colors.white.withValues(alpha: .65);
    final top = Path()
      ..moveTo(size.width * .50, size.height * .16)
      ..lineTo(size.width * .28, size.height * .52)
      ..lineTo(size.width * .50, size.height * .43)
      ..lineTo(size.width * .72, size.height * .52)
      ..close();
    final bottom = Path()
      ..moveTo(size.width * .50, size.height * .48)
      ..lineTo(size.width * .28, size.height * .57)
      ..lineTo(size.width * .50, size.height * .84)
      ..lineTo(size.width * .72, size.height * .57)
      ..close();
    canvas.drawPath(top, white);
    canvas.drawPath(bottom, faint);
  }

  void _drawStable(Canvas canvas, Size size, String label) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .06;
    canvas.drawCircle(size.center(Offset.zero), size.width * .30, white);
    _drawText(canvas, size, label, Colors.white, .46, FontWeight.w900);
  }

  void _drawPlatformTokenMark(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final unit = size.width * .18;
    final start = Offset(size.width * .22, size.height * .22);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(
            start.dx + col * unit,
            start.dy + row * unit,
            unit * .82,
            unit * .82,
          ),
          paint,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .56,
        size.height * .56,
        unit * .82,
        unit * .82,
      ),
      paint,
    );
  }

  void _drawSol(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF14F195),
      const Color(0xFF80ECFF),
      const Color(0xFFDC1FFF),
    ];
    for (var i = 0; i < 3; i++) {
      final paint = Paint()..color = colors[i];
      final top = size.height * (.28 + i * .18);
      final path = Path()
        ..moveTo(size.width * .24, top)
        ..lineTo(size.width * .76, top)
        ..lineTo(size.width * .66, top + size.height * .10)
        ..lineTo(size.width * .14, top + size.height * .10)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawTriangleMark(Canvas canvas, Size size, Color color) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * .06
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .28, size.height * .20)
      ..lineTo(size.width * .76, size.height * .38)
      ..lineTo(size.width * .42, size.height * .78)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _drawGold(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .055
      ..style = PaintingStyle.stroke;
    for (final center in [
      Offset(size.width * .36, size.height * .40),
      Offset(size.width * .58, size.height * .40),
      Offset(size.width * .47, size.height * .62),
    ]) {
      canvas.drawCircle(center, size.width * .095, stroke);
    }
  }

  void _drawAptos(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .07
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.32 + i * .12);
      canvas.drawLine(
        Offset(size.width * .22, y),
        Offset(size.width * .78, y),
        paint,
      );
    }
  }

  void _drawHex(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF8CC8FF)
      ..strokeWidth = size.width * .07
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point =
          size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * size.width * .32;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  void _drawAvax(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .22)
      ..lineTo(size.width * .75, size.height * .72)
      ..lineTo(size.width * .25, size.height * .72)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .66),
      1.8,
      Paint()..color = const Color(0xFFE84142),
    );
  }

  @override
  bool shouldRepaint(covariant _CryptoAvatarPainter oldDelegate) {
    return oldDelegate.symbol != symbol;
  }
}

Color assetColor(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => const Color(0xFFF7931A),
    'ETH' => const Color(0xFF627EEA),
    'SPEX' || 'SURPRISING CHAIN' => const Color(0xFF050505),
    'USDT' => const Color(0xFF26A17B),
    'USDC' => const Color(0xFF2775CA),
    'USDG' => const Color(0xFF8DC63F),
    'SOL' => const Color(0xFF111827),
    'TRX' => const Color(0xFFFF0013),
    'APT' || 'APTOS' => const Color(0xFF111111),
    'ARB' || 'ARBITRUM' => const Color(0xFF2D374B),
    'AVAX' || 'AVALANCHE' => const Color(0xFFE84142),
    'BERA' || 'BERACHAIN' => const Color(0xFFFFFFFF),
    'XAU' || 'XAUT' => const Color(0xFFB79525),
    _ => const Color(0xFF2B3139),
  };
}

String assetDisplayName(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => 'Bitcoin',
    'ETH' => 'Ethereum',
    'SPEX' => 'Surprising EX',
    'SOL' => 'Solana',
    'USDT' => 'Tether',
    'USDC' => 'USD Coin',
    'TRX' => 'TRON',
    'XAU' || 'XAUT' => 'Tether Gold',
    _ => symbol,
  };
}
