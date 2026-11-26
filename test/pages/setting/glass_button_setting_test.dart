import 'dart:io';

import 'package:PiliPlus/pages/setting/widgets/glass_clarity_setting.dart';
import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory storage;
  var barClarity = .6, barBlur = .5, buttonClarity = .9, buttonBlur = .5;
  final barChanges = <double>[];
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp(
      'piliplus-button-material-',
    );
    Hive.init(storage.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() async {
    await GStorage.setting.clear();
    barClarity = .6;
    barBlur = .5;
    buttonClarity = .9;
    buttonBlur = .5;
    barChanges.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await storage.delete(recursive: true);
  });

  Future<void> showSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                GlassClaritySetting(
                  key: const ValueKey('bar'),
                  value: barClarity,
                  blurValue: barBlur,
                  onChanged: barChanges.add,
                  onSaved: (v) => barClarity = v,
                  onBlurChanged: barChanges.add,
                  onBlurSaved: (v) => barBlur = v,
                ),
                GlassClaritySetting(
                  key: const ValueKey('button'),
                  isButton: true,
                  value: buttonClarity,
                  blurValue: buttonBlur,
                  onChanged: (_) {},
                  onSaved: (v) => buttonClarity = v,
                  onBlurChanged: (_) {},
                  onBlurSaved: (v) => buttonBlur = v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('new button preferences preserve existing bar values and independent defaults', () async {
    await GStorage.setting.put(SettingBoxKey.androidGlassClarity, .24);
    await GStorage.setting.put(SettingBoxKey.androidGlassBlur, .73);
    expect(Pref.androidGlassButtonClarity, .9);
    expect(Pref.androidGlassButtonBlur, .5);
    expect(
      GlassAppearance.nativeButtonBlurRadius(Pref.androidGlassButtonBlur),
      16,
    );
    expect(Pref.androidGlassClarity, .24);
    expect(Pref.androidGlassBlur, .73);
    await GStorage.setting.put(SettingBoxKey.androidGlassButtonClarity, .1);
    await GStorage.setting.put(SettingBoxKey.androidGlassButtonBlur, .8);
    expect(Pref.androidGlassButtonClarity, .1);
    expect(Pref.androidGlassButtonBlur, .8);
    expect(Pref.androidGlassClarity, .24);
    expect(Pref.androidGlassBlur, .73);
    for (final bad in [null, 'bad', double.nan, double.infinity]) {
      expect(GlassAppearance.normalizeButtonClarity(bad), .9);
    }
    expect(GlassAppearance.buttonSurfaceOpacity(1), 0);
    expect(GlassAppearance.nativeButtonBlurRadius(0), 0);
    expect(GlassAppearance.nativeButtonBlurRadius(1), 32);
  });

  testWidgets(
    'four named sliders save/reset the button without changing the bar',
    (tester) async {
      await showSettings(tester);
      for (final title in ['底栏通透程度', '底栏模糊程度', '按钮通透程度', '按钮模糊程度']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(Slider), findsNWidgets(4));
      final slider = find.byKey(const ValueKey('glass-button-clarity-slider'));
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.left + 30, rect.center.dy));
      await tester.pump();
      final value = tester.widget<Slider>(slider).value;
      expect(buttonClarity, .9);
      expect(barChanges, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(buttonClarity, value);
      expect(barClarity, .6);
      expect(barBlur, .5);
      expect(buttonBlur, .5);
      await tester.ensureVisible(find.byTooltip('恢复默认按钮通透程度'));
      await tester.tap(find.byTooltip('恢复默认按钮通透程度'));
      await tester.pumpAndSettle();
      expect(buttonClarity, .9);
      expect(barChanges, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await showSettings(tester);
      expect(tester.widget<Slider>(slider).value, .9);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'button blur is saved on route disposal without touching other values',
    (tester) async {
      await showSettings(tester);
      final slider = find.byKey(const ValueKey('glass-button-blur-slider'));
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.right - 25, rect.center.dy));
      await tester.pump();
      final value = tester.widget<Slider>(slider).value;
      expect(buttonBlur, .5);
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(buttonBlur, value);
      expect(buttonClarity, .9);
      expect(barClarity, .6);
      expect(barBlur, .5);
      expect(barChanges, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
