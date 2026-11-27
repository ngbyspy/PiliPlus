import 'dart:io';

import 'package:PiliPlus/pages/setting/widgets/glass_clarity_setting.dart';
import 'package:PiliPlus/pages/setting/widgets/glass_bar_width_setting.dart';
import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory storage;
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp(
      'piliplus-native-controls-',
    );
    Hive.init(storage.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() => GStorage.setting.clear());
  tearDownAll(() async {
    await Hive.close();
    await storage.delete(recursive: true);
  });

  test(
    'old shared settings become independent without changing r13 keys',
    () async {
      await GStorage.setting.putAll({
        SettingBoxKey.androidGlassClarity: .83,
        SettingBoxKey.androidGlassBlur: .2,
      });
      await GlassAppearance.initializeNativeControls(GStorage.setting);
      expect(Pref.androidGlassButtonClarity, .83);
      expect(Pref.androidGlassButtonBlur, .2);
      expect(Pref.androidGlassClarity, .83);
      expect(Pref.androidGlassBlur, .2);
      await GStorage.setting.putAll({
        SettingBoxKey.androidGlassClarity: .1,
        SettingBoxKey.androidGlassBlur: 1.0,
        SettingBoxKey.androidGlassBarTint: GlassTint.white.name,
        SettingBoxKey.androidGlassButtonTint: GlassTint.black.name,
      });
      await GlassAppearance.initializeNativeControls(GStorage.setting);
      var reopened = await Hive.openBox('native-controls-restart');
      await reopened.putAll(GStorage.setting.toMap());
      await reopened.close();
      reopened = await Hive.openBox('native-controls-restart');
      await GlassAppearance.initializeNativeControls(reopened);
      expect(reopened.get(SettingBoxKey.androidGlassButtonClarity), .83);
      expect(reopened.get(SettingBoxKey.androidGlassButtonBlur), .2);
      expect(reopened.get(SettingBoxKey.androidGlassBarTint), 'white');
      expect(reopened.get(SettingBoxKey.androidGlassButtonTint), 'black');
      await reopened.close();
      expect(Pref.androidGlassButtonClarity, .83);
      expect(Pref.androidGlassButtonBlur, .2);
      expect(Pref.androidGlassClarity, .1);
      expect(Pref.androidGlassBlur, 1);
      expect(Pref.androidGlassBarTint, GlassTint.white);
      expect(Pref.androidGlassButtonTint, GlassTint.black);
    },
  );

  test(
    'missing or malformed independent preferences keep accepted defaults',
    () async {
      await GlassAppearance.initializeNativeControls(GStorage.setting);
      expect(Pref.androidGlassButtonClarity, .6);
      expect(Pref.androidGlassButtonBlur, .5);
      expect(Pref.androidGlassBarTint, GlassTint.automatic);
      expect(Pref.androidGlassButtonTint, GlassTint.automatic);
      await GStorage.setting.putAll({
        SettingBoxKey.androidGlassButtonClarity: 'invalid',
        SettingBoxKey.androidGlassButtonBlur: 'invalid',
        SettingBoxKey.androidGlassBarTint: 99,
        SettingBoxKey.androidGlassButtonTint: 'invalid',
      });
      expect(Pref.androidGlassButtonClarity, .6);
      expect(Pref.androidGlassButtonBlur, .5);
      expect(Pref.androidGlassBarTint, GlassTint.automatic);
      expect(Pref.androidGlassButtonTint, GlassTint.automatic);
    },
  );

  test(
    'width preference is independent and missing values stay automatic',
    () async {
      expect(Pref.androidGlassBarWidth, 0);
      await GStorage.setting.putAll({
        SettingBoxKey.androidGlassClarity: .8,
        SettingBoxKey.androidGlassButtonBlur: .25,
      });
      await GStorage.setting.put(SettingBoxKey.androidGlassBarWidth, 260.0);
      expect(Pref.androidGlassBarWidth, 260);
      expect(Pref.androidGlassClarity, .8);
      expect(Pref.androidGlassButtonBlur, .25);
      await GStorage.setting.put(SettingBoxKey.androidGlassBarWidth, 0.0);
      expect(Pref.androidGlassBarWidth, 0);
    },
  );

  testWidgets(
    'width saves on release, survives reopening and restores automatic',
    (tester) async {
      var live = Pref.androidGlassBarWidth;
      var savedWidth = live;
      expect(live, 0);
      final materialBefore = Pref.androidGlassClarity;
      Widget host() => MaterialApp(
        home: Scaffold(
          body: GlassBarWidthSetting(
            value: savedWidth,
            onChanged: (value) => live = value,
            onSaved: (value) => savedWidth = value,
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final slider = find.byKey(const ValueKey('glass-bar-width-slider'));
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.left + 70, rect.center.dy));
      await tester.pump();
      expect(live, greaterThanOrEqualTo(200));
      expect(live, lessThan(480));
      expect(savedWidth, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(savedWidth, live);
      expect(Pref.androidGlassClarity, materialBefore);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).value, live);
      await tester.tap(find.byTooltip('恢复自动宽度'));
      await tester.pumpAndSettle();
      expect(savedWidth, 0);
      expect(live, 0);
      final second = await tester.startGesture(tester.getRect(slider).center);
      await second.moveTo(Offset(rect.left + 90, rect.center.dy));
      await tester.pump();
      final inFlight = live;
      await tester.pumpWidget(const SizedBox.shrink());
      await second.cancel();
      await tester.pumpAndSettle();
      expect(savedWidth, inFlight);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('each group adjusts and resets only its own settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(440, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = <String, Object>{};
    final saved = <String, Object>{};
    Widget controls(String name) => GlassClaritySetting(
      key: ValueKey(name),
      title: name == 'bar' ? '底栏' : '选中按钮',
      showPreview: false,
      value: .6,
      blurValue: .5,
      onChanged: (v) => changes['$name-clarity'] = v,
      onSaved: (v) => saved['$name-clarity'] = v,
      onBlurChanged: (v) => changes['$name-blur'] = v,
      onBlurSaved: (v) => saved['$name-blur'] = v,
      onTintChanged: (v) => saved['$name-tint'] = v,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                controls('bar'),
                controls('button'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNWidgets(4));
    expect(find.byType(GlassSurface), findsNothing);
    Finder inside(String group, Finder child) => find.descendant(
      of: find.byKey(ValueKey(group)),
      matching: child,
    );
    for (final name in ['bar', 'button']) {
      for (final kind in ['clarity', 'blur']) {
        final slider = inside(name, find.byKey(ValueKey('glass-$kind-slider')));
        await tester.ensureVisible(slider);
        final before = Map<String, Object>.of(saved);
        final rect = tester.getRect(slider);
        final gesture = await tester.startGesture(rect.center);
        await gesture.moveTo(Offset(rect.right - 26, rect.center.dy));
        await tester.pump();
        expect(changes['$name-$kind'], greaterThan(.6));
        expect(saved, before);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(saved['$name-$kind'], changes['$name-$kind']);
        for (final entry in before.entries) {
          if (entry.key != '$name-$kind') expect(saved[entry.key], entry.value);
        }
      }
    }
    await tester.tap(inside('bar', find.text('白色')));
    await tester.pumpAndSettle();
    await tester.tap(inside('button', find.text('黑色')));
    await tester.pumpAndSettle();
    expect(saved['bar-tint'], GlassTint.white);
    expect(saved['button-tint'], GlassTint.black);
    final buttonBefore = saved['button-blur'];
    await tester.tap(inside('bar', find.byTooltip('恢复默认模糊程度')));
    await tester.pumpAndSettle();
    expect(saved['bar-blur'], .5);
    expect(saved['button-blur'], buttonBefore);
    expect(saved['button-tint'], GlassTint.black);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
