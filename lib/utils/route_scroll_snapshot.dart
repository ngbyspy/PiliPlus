import 'package:flutter/widgets.dart';

/// Captured only when another route covers a page; no scroll listener is added.
class RouteScrollSnapshot {
  RouteScrollSnapshot.capture(Iterable<ScrollController?> controllers)
    : _offsets = [
        for (final controller in controllers)
          if (controller != null && controller.hasClients)
            (controller, controller.offset),
      ];

  final List<(ScrollController, double)> _offsets;

  void restore() {
    for (final (controller, offset) in _offsets) {
      if (!controller.hasClients) continue;
      final position = controller.position;
      controller.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
  }
}
