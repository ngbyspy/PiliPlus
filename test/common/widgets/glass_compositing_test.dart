import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_liquid_glasses/src/glass_backdrop_layer.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe(this.onPaint, this.onFilter, {required super.child});
  final VoidCallback onPaint;
  final ValueChanged<Rect> onFilter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbe(onPaint, onFilter);
}

class _RenderProbe extends RenderProxyBox {
  _RenderProbe(this.onPaint, this.onFilter);
  final VoidCallback onPaint;
  final ValueChanged<Rect> onFilter;

  @override
  bool get alwaysNeedsCompositing => true;

  ui.ImageFilter _resolve() {
    onFilter(
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size),
    );
    return ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    final backdrop =
        (layer ??= GlassBackdropFilterLayer(_resolve))
            as GlassBackdropFilterLayer;
    context.pushLayer(backdrop, super.paint, offset);
  }
}

void main() {
  for (final animated in [false, true]) {
    testWidgets(
      'cached glass follows hide and tab-return transforms, animated=$animated',
      (tester) async {
        final hidden = ValueNotifier(0.0);
        var paints = 0;
        final filteredBounds = <Rect>[];
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: hidden,
                child: RepaintBoundary(
                  child: _Probe(
                    () => paints++,
                    filteredBounds.add,
                    child: const SizedBox(
                      width: 320,
                      height: 64,
                      child: ColoredBox(color: Color(0x11000000)),
                    ),
                  ),
                ),
                builder: (context, value, child) =>
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: value, end: value),
                      duration: animated
                          ? const Duration(milliseconds: 180)
                          : Duration.zero,
                      child: child,
                      builder: (_, position, child) => FractionalTranslation(
                        translation: Offset(0, position),
                        child: child,
                      ),
                    ),
              ),
            ),
          ),
        );
        final origin = filteredBounds.last;
        final originalPaints = paints;
        for (final offset in [.55, 1.2, 0.0, .35, 0.0]) {
          hidden.value = offset;
          await tester.pump();
          await tester.pumpAndSettle();
          expect(
            filteredBounds.last.top,
            closeTo(origin.top + offset * 64, .001),
          );
          expect(filteredBounds.last.size, origin.size);
          // Exercise retained compositing, not a widget rebuild/child repaint.
          expect(paints, originalPaints);
        }
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        hidden.dispose();
      },
    );
  }
}
