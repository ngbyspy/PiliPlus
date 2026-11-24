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
  }) => tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 320,
          child: ReducedTransparencyScope(
            reduceTransparency: true,
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
}
