import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/pages/setting/widgets/glass_clarity_setting.dart';
import 'package:PiliPlus/utils/android/glass_appearance.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late Directory storage;
  var saved = GlassAppearance.defaultClarity;
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('piliplus-glass-clarity-');
    Hive.init(storage.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() async {
    await GStorage.setting.clear();
    saved = GlassAppearance.defaultClarity;
  });
  tearDownAll(() async {
    await Hive.close();
    await storage.delete(recursive: true);
  });

  Future<void> showSetting(
    WidgetTester tester,
    List<double> changes, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: brightness,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: RepaintBoundary(
                key: const ValueKey('setting-preview'),
                child: GlassClaritySetting(
                  value: saved,
                  onChanged: changes.add,
                  onSaved: (value) => saved = value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'missing, malformed and nonfinite preferences keep the accepted tint',
    () async {
      expect(Pref.androidGlassClarity, GlassAppearance.defaultClarity);
      expect(GlassAppearance.surfaceOpacity(Pref.androidGlassClarity), .4);
      for (final bad in [
        'bad',
        null,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(GlassAppearance.normalize(bad), .6);
      }
      await GStorage.setting.put(SettingBoxKey.androidGlassClarity, 'invalid');
      expect(Pref.androidGlassClarity, .6);
      expect(GlassAppearance.normalize(-1), 0);
      expect(GlassAppearance.normalize(2), 1);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'live material adjustment retains optics and saves on release: $brightness',
      (tester) async {
        final changes = <double>[];
        await showSetting(tester, changes, brightness: brightness);
        final before = tester.widget<GlassSurface>(
          find.byType(GlassSurface).first,
        );
        expect(before.params.surfaceColor.last, .4);
        expect(find.text('60%'), findsOneWidget);
        expect(changes, isEmpty);
        final filters = find.byType(BackdropFilter).evaluate().length;
        final slider = tester.getRect(find.byType(Slider));
        final gesture = await tester.startGesture(slider.center);
        await gesture.moveTo(
          Offset(slider.left + slider.width * .82, slider.center.dy),
        );
        await tester.pump();
        final value = tester.widget<Slider>(find.byType(Slider)).value;
        expect(value, greaterThan(.6));
        expect(changes.last, value);
        expect(saved, .6);
        final after = tester.widget<GlassSurface>(
          find.byType(GlassSurface).first,
        );
        expect(after.params.surfaceColor.last, closeTo(1 - value, .00001));
        expect(
          after.params.copyWith(surfaceColor: before.params.surfaceColor),
          before.params,
        );
        expect(after.blurSigma, before.blurSigma);
        expect(find.byType(BackdropFilter).evaluate().length, filters);
        expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(saved, value);

        final captureDir = Platform.environment['GLASS_SETTINGS_CAPTURE_DIR'];
        if (captureDir != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('setting-preview')),
            );
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$captureDir/glass-setting-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'reset restores current appearance and persists across route reopen',
    (tester) async {
      saved = .2;
      final changes = <double>[];
      await showSetting(tester, changes);
      expect(find.text('20%'), findsOneWidget);
      await tester.tap(find.byTooltip('恢复默认'));
      await tester.pumpAndSettle();
      expect(changes.last, .6);
      expect(saved, .6);
      expect(
        tester
            .widget<GlassSurface>(find.byType(GlassSurface).first)
            .params
            .surfaceColor
            .last,
        .4,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await showSetting(tester, changes);
      expect(find.text('60%'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .6);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('closing settings during a drag does not lose the live value', (
    tester,
  ) async {
    final changes = <double>[];
    await showSetting(tester, changes);
    final slider = tester.getRect(find.byType(Slider));
    final gesture = await tester.startGesture(slider.center);
    await gesture.moveTo(Offset(slider.right - 30, slider.center.dy));
    await tester.pump();
    final value = changes.last;
    await tester.pumpWidget(const SizedBox.shrink());
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(saved, value);
    expect(tester.takeException(), isNull);
  });
}
