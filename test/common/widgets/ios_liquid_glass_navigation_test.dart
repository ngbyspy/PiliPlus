import 'package:PiliPlus/common/widgets/ios_liquid_glass_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void glassTest(String name, WidgetTesterCallback body) => testWidgets(
    name,
    body,
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  const capability = MethodChannel(IosLiquidGlassNavigationBar.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final created = <Map<dynamic, dynamic>>[];
  final updates = <Map<dynamic, dynamic>>[];
  final selections = <int>[];
  var supported = true;
  var failUpdate = false;
  var capabilityCalls = 0;

  const home = IosGlassDestination(
    id: 'home',
    label: '首页',
    symbol: 'house',
    selectedSymbol: 'house.fill',
  );
  const dynamics = IosGlassDestination(
    id: 'dynamics',
    label: '动态',
    symbol: 'play.rectangle',
    selectedSymbol: 'play.rectangle.fill',
    badge: '12',
  );
  const mine = IosGlassDestination(
    id: 'mine',
    label: '我的',
    symbol: 'person',
    selectedSymbol: 'person.fill',
  );

  Widget app({
    List<IosGlassDestination> items = const [home, dynamics, mine],
    int selected = 0,
    Brightness brightness = Brightness.light,
  }) => MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Align(
      alignment: Alignment.bottomCenter,
      child: IosLiquidGlassNavigationBar(
        destinations: items,
        selectedIndex: selected,
        onSelected: selections.add,
        fallback: const Text('original navigation'),
      ),
    ),
  );

  Future<void> event(String method, Map<String, Object> args) async {
    final id = created.last['id'];
    final channel = '${IosLiquidGlassNavigationBar.channelName}/$id';
    await messenger.handlePlatformMessage(
      channel,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  setUp(() {
    created.clear();
    updates.clear();
    selections.clear();
    supported = true;
    failUpdate = false;
    capabilityCalls = 0;
    messenger.setMockMethodCallHandler(capability, (call) async {
      capabilityCalls++;
      expect(call.method, 'isSupported');
      return supported;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<dynamic, dynamic>;
        created.add(args);
        final channel = MethodChannel(
          '${IosLiquidGlassNavigationBar.channelName}/${args['id']}',
        );
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (failUpdate) throw PlatformException(code: 'unavailable');
          expect(call.method, 'update');
          updates.add(call.arguments as Map<dynamic, dynamic>);
          return null;
        });
      }
      return null;
    });
  });

  tearDown(() {
    for (final view in created) {
      messenger.setMockMethodCallHandler(
        MethodChannel(
          '${IosLiquidGlassNavigationBar.channelName}/${view['id']}',
        ),
        null,
      );
    }
    messenger
      ..setMockMethodCallHandler(capability, null)
      ..setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  glassTest('old iOS keeps original bar without creating a platform view', (
    tester,
  ) async {
    supported = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('original navigation'), findsOneWidget);
    expect(created, isEmpty);
    expect(capabilityCalls, 1);
  });

  glassTest('missing native bridge falls back safely', (tester) async {
    messenger.setMockMethodCallHandler(capability, null);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('original navigation'), findsOneWidget);
    expect(created, isEmpty);
  });

  glassTest('native selection preserves order, badges, and repeated taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(items: const [mine, home, dynamics], selected: 1),
    );
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(updates.last['selectedId'], 'home');
    expect((updates.last['items'] as List).last['badge'], '12');
    await event('selected', {'id': 'home'});
    await event('selected', {'id': 'home'});
    await event('selected', {'id': 'dynamics'});
    await event('selected', {'id': 'removed'});
    expect(selections, [1, 1, 2]);
  });

  glassTest('selection and theme update the existing view', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(selected: 2, brightness: Brightness.dark));
    await tester.pumpAndSettle();
    expect(created, hasLength(1));
    expect(updates.last['selectedId'], 'mine');
    expect(updates.last['isDark'], true);
    expect(capabilityCalls, 1);
  });

  glassTest('system metrics resize safely and invalid heights are ignored', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await event('metrics', {'height': 88.0});
    await tester.pump();
    expect(tester.getSize(find.byType(UiKitView)).height, 88);
    await event('metrics', {'height': 900.0});
    await tester.pump();
    expect(tester.getSize(find.byType(UiKitView)).height, 88);
  });

  glassTest(
    'native update failure restores fallback; disposal releases callbacks',
    (tester) async {
      failUpdate = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('original navigation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await event('selected', {'id': 'mine'});
      expect(selections, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
