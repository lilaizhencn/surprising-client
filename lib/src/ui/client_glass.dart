import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Glass is confined to navigation; financial content uses opaque surfaces.
class ClientGlassSurface extends StatelessWidget {
  const ClientGlassSurface({required this.child, this.radius = 28, super.key});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final opaque =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final native =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS && !opaque;
    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: colors.outline.withValues(alpha: .75)),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          colors.surface.withValues(alpha: opaque ? 1 : .94),
          Color.alphaBlend(
            colors.primary.withValues(alpha: .12),
            colors.surface,
          ).withValues(alpha: opaque ? 1 : .86),
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
                      'tint': colors.surface.toARGB32(),
                      'accent': colors.primary.toARGB32(),
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
                border: Border.all(color: colors.outline.withValues(alpha: .7)),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: child,
            )
          else if (opaque)
            DecoratedBox(decoration: decoration, child: child)
          else
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(decoration: decoration, child: child),
            ),
        ],
      ),
    );
  }
}
