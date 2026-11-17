import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'theme/tokens.dart';

/// Glass is confined to static navigation/overlays; financial content uses opaque surfaces.
class ClientGlassSurface extends StatelessWidget {
  const ClientGlassSurface({required this.child, this.radius = 28, super.key});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = context.tokens;
    final opaque =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.disableAnimationsOf(context);
    final native =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !opaque;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: opaque ? t.borderStrong : t.borderDefault.withValues(alpha: 0.78),
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          t.bgElevated2.withValues(alpha: opaque ? 1 : SurprisingTokens.glass1Alpha),
          Color.alphaBlend(
            t.auroraCyan.withValues(alpha: 0.08),
            t.bgElevated1,
          ).withValues(alpha: opaque ? 1 : 0.86),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          if (native)
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: UiKitView(
                    key: ValueKey(
                      '${colors.surface.toARGB32()}-${colors.primary.toARGB32()}-$radius',
                    ),
                    viewType: 'surprising/liquid-glass',
                    creationParams: {
                      'tint': t.bgElevated1.toARGB32(),
                      'accent': t.auroraCyan.toARGB32(),
                      'dark': colors.brightness == Brightness.dark,
                      'radius': radius,
                    },
                    creationParamsCodec: const StandardMessageCodec(),
                  ),
                ),
              ),
            ),
          if (native)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: t.borderDefault.withValues(alpha: 0.75)),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: child,
            )
          else if (opaque)
            DecoratedBox(decoration: decoration, child: child)
          else
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: SurprisingTokens.glass1Blur,
                sigmaY: SurprisingTokens.glass1Blur,
              ),
              child: DecoratedBox(decoration: decoration, child: child),
            ),
        ],
      ),
    );
  }
}
