import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// The Navigator owns route state; page routes share a hinge-safe region.
class ClientRouteObserver extends NavigatorObserver {
  ClientRouteObserver(this.onPageChanged);
  final VoidCallback onPageChanged;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onPageChanged();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onPageChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) onPageChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute is PageRoute || oldRoute is PageRoute) onPageChanged();
  }
}

/// Window-local usable regions. A flat crease does not obstruct content.
List<Rect> clientDisplayPanes(Size size, List<ui.DisplayFeature> features) {
  var panes = <Rect>[Offset.zero & size];
  for (final feature in features) {
    if (feature.type != ui.DisplayFeatureType.hinge &&
        !(feature.type == ui.DisplayFeatureType.fold &&
            feature.state == ui.DisplayFeatureState.postureHalfOpened)) {
      continue;
    }
    final bounds = feature.bounds;
    final next = <Rect>[];
    for (final pane in panes) {
      if (bounds.height >= pane.height * .8 &&
          bounds.center.dx > pane.left &&
          bounds.center.dx < pane.right) {
        next.add(
          Rect.fromLTRB(
            pane.left,
            pane.top,
            bounds.left.clamp(pane.left, pane.right),
            pane.bottom,
          ),
        );
        next.add(
          Rect.fromLTRB(
            bounds.right.clamp(pane.left, pane.right),
            pane.top,
            pane.right,
            pane.bottom,
          ),
        );
      } else if (bounds.width >= pane.width * .8 &&
          bounds.center.dy > pane.top &&
          bounds.center.dy < pane.bottom) {
        next.add(
          Rect.fromLTRB(
            pane.left,
            pane.top,
            pane.right,
            bounds.top.clamp(pane.top, pane.bottom),
          ),
        );
        next.add(
          Rect.fromLTRB(
            pane.left,
            bounds.bottom.clamp(pane.top, pane.bottom),
            pane.right,
            pane.bottom,
          ),
        );
      } else {
        next.add(pane);
      }
    }
    panes = next.where((pane) => pane.width > 0 && pane.height > 0).toList();
  }
  panes.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  return panes;
}

/// Keeps controls out of hinges and supports book and tabletop postures.
class FoldAwareClientBody extends StatelessWidget {
  const FoldAwareClientBody({required this.primary, this.secondary, super.key});
  final Widget primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final panes = clientDisplayPanes(
        constraints.biggest,
        media.displayFeatures,
      );
      final split =
          secondary != null &&
          panes.length > 1 &&
          panes
              .take(2)
              .every((pane) => pane.width >= 260 && pane.height >= 240);
      final selected = split ? panes.take(2).toList() : [panes.first];
      if (split) {
        selected.sort(
          (a, b) => a.top == b.top
              ? a.left.compareTo(b.left)
              : a.top.compareTo(b.top),
        );
      }
      Widget region(Rect bounds, Widget child) => Positioned.fromRect(
        rect: bounds,
        child: MediaQuery(
          data: media.copyWith(
            size: bounds.size,
            displayFeatures: const [],
            padding: EdgeInsets.fromLTRB(
              bounds.left == 0 ? media.padding.left : 0,
              bounds.top == 0 ? media.padding.top : 0,
              bounds.right == constraints.maxWidth ? media.padding.right : 0,
              bounds.bottom == constraints.maxHeight ? media.padding.bottom : 0,
            ),
            viewInsets: EdgeInsets.only(
              bottom:
                  (media.viewInsets.bottom -
                          (constraints.maxHeight - bounds.bottom))
                      .clamp(0, bounds.height),
            ),
          ),
          child: child,
        ),
      );
      return Stack(
        children: [
          if (split) region(selected.first, secondary!),
          region(selected.last, primary),
        ],
      );
    },
  );
}

/// Readable form width on tablets, landscape phones, and unfolded screens.
class ClientFormWidth extends StatelessWidget {
  const ClientFormWidth({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}
