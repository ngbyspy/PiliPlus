import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:material_ui/material_ui.dart';

/// Shared hysteresis for scroll-linked controls. Positive deltas move down.
class ScrollVisibility {
  static const hideDistance = 24.0;
  static const showDistance = 48.0;
  static const duration = Duration(milliseconds: 180);
  static const curve = Curves.easeInOut;

  double _distance = 0;
  ScrollDirection? _accepted;
  bool _userScrolling = false;

  void reset() {
    _distance = 0;
    _accepted = null;
    _userScrolling = false;
  }

  ScrollDirection? updateDelta(double delta) {
    if (delta == 0) return null;
    if (_distance.sign != delta.sign) {
      _distance = 0;
      _accepted = null;
    }
    _distance += delta;
    if (_distance >= hideDistance) _accepted = .reverse;
    if (_distance <= -showDistance) _accepted = .forward;
    return _accepted;
  }

  ScrollDirection? update(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return null;
    if (notification.metrics.extentBefore == 0 &&
        (notification is OverscrollNotification &&
                notification.dragDetails != null &&
                notification.overscroll < 0 ||
            notification is ScrollUpdateNotification &&
                notification.dragDetails != null &&
                notification.scrollDelta! < 0)) {
      _distance = -showDistance;
      return _accepted = ScrollDirection.forward;
    }
    if (notification is ScrollStartNotification) {
      reset();
      _userScrolling = notification.dragDetails != null;
    } else if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != .idle;
    } else if (notification is ScrollUpdateNotification &&
        (notification.dragDetails != null || _userScrolling)) {
      return updateDelta(notification.scrollDelta!);
    } else if (notification is ScrollEndNotification) {
      final direction = notification.metrics.extentBefore == 0
          ? ScrollDirection.forward
          : _accepted;
      reset();
      return direction;
    }
    return null;
  }
}
