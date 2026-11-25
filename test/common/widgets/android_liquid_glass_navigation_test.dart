import 'package:PiliPlus/common/widgets/android_liquid_glass_navigation.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('software renderer retains original navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AndroidLiquidGlassNavigationBar(
          destinations: const [
            AndroidGlassDestination(
              id: 'home',
              label: '首页',
              icon: Icon(Icons.home),
              selectedIcon: Icon(Icons.home),
            ),
            AndroidGlassDestination(
              id: 'mine',
              label: '我的',
              icon: Icon(Icons.person),
              selectedIcon: Icon(Icons.person),
            ),
          ],
          selectedIndex: 0,
          onSelected: (_) => fail('fallback must own its input'),
          fallback: const Text('original navigation'),
        ),
      ),
    );
    expect(find.text('original navigation'), findsOneWidget);
    expect(find.byType(GlassSegmentedControl<String>), findsNothing);
  });

  Future<void> control(
    WidgetTester tester,
    List<String> selected, {
    int index = 0,
    bool reduceTransparency = true,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          child: ReducedTransparencyScope(
            reduceTransparency: reduceTransparency,
            child: GlassSegmentedControl<String>(
              height: 64,
              segments: const [
                GlassSegment(value: 'mine', label: '我的'),
                GlassSegment(value: 'home', label: '首页'),
              ],
              selected: index == 0 ? 'mine' : 'home',
              onChanged: selected.add,
              onReselected: selected.add,
              itemBuilder: (_, segment, active) =>
                  Text('${segment.label}:${active ? "on" : "off"}'),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('ordered destinations preserve taps and repeated selection', (
    tester,
  ) async {
    final selected = <String>[];
    await control(tester, selected);
    await tester.tap(find.text('我的:on'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页:off'));
    await tester.pumpAndSettle();
    expect(selected, ['mine', 'home']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag selects on release; cancellation does not navigate', (
    tester,
  ) async {
    final selected = <String>[];
    await control(tester, selected);
    final start = tester.getCenter(find.text('我的:on'));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(180, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(selected, isEmpty);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(selected, isEmpty);
    await tester.dragFrom(start, const Offset(180, 0));
    await tester.pumpAndSettle();
    expect(selected, ['home']);
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
    'assistive navigation does not turn an opted-in glass thumb opaque',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: ReducedTransparencyScope(
              reduceTransparency: false,
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: GlassSegmentedControl<String>(
                    height: 64,
                    selected: 'home',
                    segments: const [
                      GlassSegment(value: 'home', label: '首页'),
                      GlassSegment(value: 'mine', label: '我的'),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Software tests use the documented blur fallback. An opaque accessibility
      // branch removes the track filter and obscures the selected label.
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.bySemanticsLabel('首页'), findsOneWidget);
      expect(find.bySemanticsLabel('我的'), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets(
    'idle thumb avoids backdrop work and press restores real filter',
    (tester) async {
      final selected = <String>[];
      await control(tester, selected, reduceTransparency: false);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('我的:on')),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(BackdropFilter), findsNWidgets(2));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(selected, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
}
