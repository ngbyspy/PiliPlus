import 'dart:ui' as ui;

import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:material_ui/material_ui.dart';

@immutable
class AndroidGlassDestination {
  const AndroidGlassDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String id;
  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// Only the navigation material is experimental. Selection, badges, route
/// changes and scroll hiding continue to use MainController's existing paths.
class AndroidLiquidGlassNavigationBar extends StatelessWidget {
  const AndroidLiquidGlassNavigationBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.fallback,
    this.clarity = GlassAppearance.defaultClarity,
    this.blur = GlassAppearance.defaultBlur,
  });

  final List<AndroidGlassDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget fallback;
  final double clarity;
  final double blur;

  @override
  Widget build(BuildContext context) {
    // A frosted fallback would conceal a failed refraction experiment.
    if (!ui.ImageFilter.isShaderFilterSupported ||
        MediaQuery.highContrastOf(context) ||
        destinations.length < 2) {
      return fallback;
    }
    final colors = ColorScheme.of(context);
    final current = selectedIndex.clamp(0, destinations.length - 1);
    void select(String id) {
      final index = destinations.indexWhere((item) => item.id == id);
      if (index >= 0) onSelected(index);
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SizedBox(
          width: double.infinity,
          // accessibleNavigation describes assistive input, not a request for
          // opaque surfaces. High contrast already uses the original bar above.
          child: ReducedTransparencyScope(
            reduceTransparency: false,
            child: GlassTheme(
              data: GlassThemeData(
                menuSurface: colors.surface,
                fallbackSurface: colors.surface,
              ),
              child: GlassSegmentedControl<String>(
                height: 64,
                inset: 4,
                blurSigma: GlassAppearance.flutterBlurSigma(blur),
                surfaceOpacity: GlassAppearance.surfaceOpacity(clarity),
                segments: destinations
                    .map(
                      (item) => GlassSegment(value: item.id, label: item.label),
                    )
                    .toList(),
                selected: destinations[current].id,
                onChanged: select,
                onReselected: select,
                itemBuilder: (context, segment, active) {
                  final item = destinations.firstWhere(
                    (item) => item.id == segment.value,
                  );
                  final color = active ? colors.primary : colors.onSurface;
                  return IconTheme(
                    data: IconThemeData(color: color, size: 23),
                    child: Column(
                      key: ValueKey('glass-nav-${item.id}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        active ? item.selectedIcon : item.icon,
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
