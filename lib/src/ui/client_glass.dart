import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'theme/tokens.dart';

/// Glass is confined to static navigation/overlays; financial content uses opaque surfaces.
class ClientGlassSurface extends StatelessWidget {
  const ClientGlassSurface({required this.child, this.radius = 28, super.key});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = context.tokens;
    final opaque =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: opaque
            ? t.borderStrong
            : isDark
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.78),
        width: 0.8,
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: opaque
            ? [t.bgElevated2, t.bgElevated1]
            : isDark
            ? [
                Colors.white.withValues(alpha: 0.12),
                t.bgElevated1.withValues(alpha: 0.38),
              ]
            : [
                Colors.white.withValues(alpha: 0.68),
                Colors.white.withValues(alpha: 0.42),
              ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: opaque
            ? DecoratedBox(decoration: decoration, child: child)
            : BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                child: DecoratedBox(decoration: decoration, child: child),
              ),
      ),
    );
  }
}
