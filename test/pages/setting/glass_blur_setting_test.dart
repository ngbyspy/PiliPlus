import 'dart:io';

import 'package:PiliPlus/pages/setting/widgets/glass_clarity_setting.dart';
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
  var savedBlur = .5;
  final changes = <double>[];
  final clarityChanges = <double>[];
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('piliplus-glass-blur-');
    Hive.init(storage.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() async {
    await GStorage.setting.clear();
    savedBlur = .5;
    changes.clear();
    clarityChanges.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await storage.delete(recursive: true);
  });

  Future<void> showSetting(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: GlassClaritySetting(
              value: .6,
              blurValue: savedBlur,
              onChanged: clarityChanges.add,
              onSaved: (_) {},
              onBlurChanged: changes.add,
              onBlurSaved: (value) {
                savedBlur = value;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'blur preferences retain accepted defaults and handle invalid values',
    () async {
      expect(Pref.androidGlassBlur, .5);
      expect(GlassAppearance.nativeBlurRadius(Pref.androidGlassBlur), 8);
      expect(GlassAppearance.flutterBlurSigma(Pref.androidGlassBlur), 2);
      await GStorage.setting.put(SettingBoxKey.androidGlassBlur, 0.0);
      expect(Pref.androidGlassBlur, 0);
      await GStorage.setting.put(SettingBoxKey.androidGlassBlur, .8);
      expect(Pref.androidGlassBlur, .8);
      for (final bad in [null, 'bad', double.nan, double.infinity]) {
        expect(GlassAppearance.normalizeBlur(bad), .5);
      }
      await GStorage.setting.put(SettingBoxKey.androidGlassBlur, 'invalid');
      expect(Pref.androidGlassBlur, .5);
      expect(GlassAppearance.nativeBlurRadius(-1), 0);
      expect(GlassAppearance.nativeBlurRadius(2), 16);
    },
  );

  testWidgets(
    'blur updates preview independently and persists only on release',
    (tester) async {
      await showSetting(tester);
      final slider = find.byKey(const ValueKey('glass-blur-slider'));
      await tester.ensureVisible(slider);
      final before = tester.widget<GlassSurface>(
        find.byType(GlassSurface).first,
      );
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.left + 24, rect.center.dy));
      await tester.pump();
      final value = tester.widget<Slider>(slider).value;
      expect(value, lessThan(.5));
      expect(changes.last, value);
      expect(savedBlur, .5);
      expect(Pref.androidGlassBlur, .5);
      final after = tester.widget<GlassSurface>(
        find.byType(GlassSurface).first,
      );
      expect(after.blurSigma, GlassAppearance.flutterBlurSigma(value));
      expect(after.params, before.params);
      expect(clarityChanges, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(savedBlur, value);
      await tester.tap(find.byTooltip('恢复默认模糊程度'));
      await tester.pumpAndSettle();
      expect(savedBlur, .5);
      expect(clarityChanges, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await showSetting(tester);
      expect(tester.widget<Slider>(slider).value, .5);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'closing a blur drag saves its live value without changing clarity',
    (tester) async {
      await showSetting(tester);
      final slider = find.byKey(const ValueKey('glass-blur-slider'));
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.right - 25, rect.center.dy));
      await tester.pump();
      final value = changes.last;
      await tester.pumpWidget(const SizedBox.shrink());
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(savedBlur, value);
      expect(clarityChanges, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
