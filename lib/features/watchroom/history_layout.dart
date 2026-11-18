import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// History rows reserve space for two title/subtitle lines and both metadata
/// lines. The thumbnail remains 100px high when accessibility text grows.
double historyRowExtent(BuildContext context) {
  final theme = Theme.of(context), scaler = MediaQuery.textScalerOf(context);
  final base = theme.textTheme.bodyMedium!;
  double line(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: '记录中文Ag', style: style),
      textDirection: TextDirection.ltr,
      locale: Localizations.maybeLocaleOf(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final title = line(
    base.copyWith(
      height: 1.42,
      letterSpacing: .3,
    ),
  );
  final subtitle = line(base.copyWith(fontSize: 13));
  final metadata = line(
    base.copyWith(fontSize: theme.textTheme.labelMedium!.fontSize),
  );
  return math.max(
    110,
    (title * 2 + subtitle * 2 + metadata * 2 + 18).ceilToDouble(),
  );
}
