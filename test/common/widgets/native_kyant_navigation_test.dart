import 'package:PiliPlus/common/widgets/native_kyant_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel(NativeKyantNavigationBar.channelName);
  final calls = <MethodCall>[];
  final selections = <int>[];
  var supported = true;
  var blur = .5;
  var clarity = .6;
  var buttonClarity = .9;
  var buttonBlur = .5;
  setUp(() {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    supported = true;
    blur = .5;
    clarity = .6;
    buttonClarity = .9;
    buttonBlur = .5;
    calls.clear();
    selections.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported' ? supported : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget bar() => NativeKyantNavigationBar(
    items: const [
      KyantDestination(id: 'mine', label: '我的'),
      KyantDestination(id: 'home', label: '首页', badge: '3'),
    ],
    selectedIndex: 0,
    onSelected: selections.add,
    fallback: const Text('original navigation'),
    clarity: clarity,
    blur: blur,
    buttonClarity: buttonClarity,
    buttonBlur: buttonBlur,
  );
  Widget host(Widget child) => MaterialApp(
    navigatorObservers: [KyantNavigationRoutes.instance],
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );
  Future<void> emit(
    Map<String, Object?> args, [
    String method = 'selected',
  ]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('unsupported native host keeps the existing bar', (tester) async {
    supported = false;
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    expect(find.text('original navigation'), findsOneWidget);
    expect(calls.where((c) => c.method == 'update'), isEmpty);
    await close(tester);
  });

  testWidgets(
    'native configuration preserves order, badge, clarity and events',
    (tester) async {
      await tester.pumpWidget(host(bar()));
      await tester.pumpAndSettle();
      final config =
          calls.lastWhere((c) => c.method == 'update').arguments as Map;
      expect((config['items'] as List).map((e) => e['id']), ['mine', 'home']);
      expect((config['items'] as List)[1]['badge'], '3');
      expect(config['opacity'], closeTo(.4, .0001));
      expect(config['blurRadius'], 8);
      expect(config['buttonOpacity'], closeTo(.1, .0001));
      expect(config['buttonBlurRadius'], 16);
      expect(find.text('original navigation'), findsNothing);
      await emit({'owner': -1, 'id': 'home'});
      expect(selections, isEmpty);
      await emit({'owner': config['owner'], 'id': 'home'});
      await emit({'owner': config['owner'], 'id': 'home'});
      expect(selections, [1, 1]);
      expect(tester.binding.transientCallbackCount, 0);
      await close(tester);
      expect(calls.any((c) => c.method == 'hide'), isTrue);
    },
  );

  testWidgets('retained child geometry follows a partial scroll translation', (
    tester,
  ) async {
    final offset = ValueNotifier(0.0);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<double>(
          valueListenable: offset,
          child: RepaintBoundary(child: bar()),
          builder: (_, value, child) =>
              Transform.translate(offset: Offset(0, value), child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start =
        (calls.lastWhere((c) => c.method == 'update').arguments as Map)['top']
            as double;
    offset.value = 17;
    await tester.pumpAndSettle();
    final end =
        (calls.lastWhere((c) => c.method == 'update').arguments as Map)['top']
            as double;
    expect(end, closeTo(start + 17, .001));
    expect(tester.binding.transientCallbackCount, 0);
    await close(tester);
    offset.dispose();
  });

  testWidgets('native blur can be disabled and raised without changing tint', (
    tester,
  ) async {
    blur = 0;
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    Map config() =>
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    expect(config()['blurRadius'], 0);
    expect(config()['opacity'], closeTo(.4, .0001));
    blur = 1;
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    expect(config()['blurRadius'], 16);
    expect(config()['opacity'], closeTo(.4, .0001));
    expect(selections, isEmpty);
    await close(tester);
  });

  testWidgets('popup routes hide the native sibling then restore it', (
    tester,
  ) async {
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NativeKyantNavigationBar));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(calls.last.method, 'hide');
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.method == 'update').method, 'update');
    await close(tester);
  });

  testWidgets('bar and button material values cross the bridge independently', (
    tester,
  ) async {
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    Map config() =>
        calls.lastWhere((c) => c.method == 'update').arguments as Map;
    clarity = .1;
    blur = .2;
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    expect(config()['opacity'], closeTo(.9, .0001));
    expect(config()['blurRadius'], closeTo(3.2, .0001));
    expect(config()['buttonOpacity'], closeTo(.1, .0001));
    expect(config()['buttonBlurRadius'], 16);
    buttonClarity = .2;
    buttonBlur = 1;
    await tester.pumpWidget(host(bar()));
    await tester.pumpAndSettle();
    expect(config()['buttonOpacity'], closeTo(.8, .0001));
    expect(config()['buttonBlurRadius'], 32);
    expect(config()['opacity'], closeTo(.9, .0001));
    expect(config()['blurRadius'], closeTo(3.2, .0001));
    expect(selections, isEmpty);
    await close(tester);
  });

  testWidgets(
    'waiting uses a temporary fallback and acknowledges a clean scene',
    (tester) async {
      await tester.pumpWidget(host(bar()));
      await tester.pumpAndSettle();
      Map config() =>
          calls.lastWhere((c) => c.method == 'update').arguments as Map;
      final owner = config()['owner'];
      await emit({'owner': owner, 'ready': false}, 'availability');
      await tester.pumpAndSettle();
      expect(find.text('original navigation'), findsOneWidget);
      expect(config()['fallback'], true);
      expect(config()['owner'], owner);
      await emit({'owner': -1, 'ready': true, 'epoch': 8}, 'availability');
      await tester.pumpAndSettle();
      expect(find.text('original navigation'), findsOneWidget);
      await emit({'owner': owner, 'ready': true, 'epoch': 9}, 'availability');
      await tester.pumpAndSettle();
      expect(find.text('original navigation'), findsNothing);
      expect(config()['fallback'], false);
      expect(config()['readyEpoch'], 9);
      expect(selections, isEmpty);
      await close(tester);
    },
  );

  testWidgets(
    'inactive scenes cannot restart capture and stale failure is ignored',
    (tester) async {
      final offset = ValueNotifier(0.0);
      await tester.pumpWidget(
        host(
          ValueListenableBuilder<double>(
            valueListenable: offset,
            child: RepaintBoundary(child: bar()),
            builder: (_, value, child) => Transform.translate(
              offset: Offset(0, value),
              child: child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner =
          (calls.lastWhere((c) => c.method == 'update').arguments
              as Map)['owner'];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final updates = calls.where((c) => c.method == 'update').length;
      offset.value = 2;
      await tester.pump();
      expect(calls.where((c) => c.method == 'update').length, updates);
      await emit({'owner': owner, 'reason': 'old surface'}, 'failed');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('original navigation'), findsNothing);
      expect(
        calls.where((c) => c.method == 'update').length,
        greaterThan(updates),
      );
      await close(tester);
      offset.dispose();
    },
  );
}
