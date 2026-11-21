import 'dart:async';

import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/widgets/mixed_playback_volume_dialog.dart';
import 'package:PiliPlus/services/mobile_playback_volume.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};
  final changes = StreamController<BoxEvent>.broadcast();

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
    changes.add(BoxEvent(key, value, false));
  }

  @override
  Stream<BoxEvent> watch({dynamic key}) =>
      changes.stream.where((event) => key == null || event.key == key);
}

Widget app(Widget child, {double textScale = 1}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  tearDownAll(settings.changes.close);
  setUp(settings.data.clear);

  testWidgets(
    'the parent switch opens its relative-volume child after enabling',
    (tester) async {
      await tester.pumpWidget(app(mixedPlaybackSetting.widget));
      await tester.tap(find.text('与其他应用一起播放'));
      await tester.pumpAndSettle();
      expect(find.byType(MixedPlaybackVolumeDialog), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(settings.data[SettingBoxKey.mixWithOthers], isTrue);
      await tester.tap(find.text('与其他应用一起播放'));
      await tester.pumpAndSettle();
      expect(find.byType(MixedPlaybackVolumeDialog), findsOneWidget);
      expect(find.text('PiliPlus 相对音量'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 100);
      await tester.drag(find.byType(Slider), const Offset(1000, 0));
      await tester.pumpAndSettle();
      expect(settings.data[SettingBoxKey.playerVolume], 300);
      await tester.tap(find.text('恢复 100%'));
      await tester.pumpAndSettle();
      expect(settings.data[SettingBoxKey.playerVolume], 100);
    },
  );

  testWidgets('the slider reaches 0% and 300% and restores 100%', (
    tester,
  ) async {
    final writes = <double>[];
    await tester.pumpWidget(
      app(MixedPlaybackVolumeDialog(value: 100, onChanged: writes.add)),
    );
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(writes.last, 0);
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(writes.last, 300);
    await tester.tap(find.text('恢复 100%'));
    await tester.pumpAndSettle();
    expect(writes.last, 100);
  });

  testWidgets('both entries share gain while gestures adjust system volume', (
    tester,
  ) async {
    settings.data[SettingBoxKey.mixWithOthers] = true;
    await tester.pumpWidget(
      app(
        Column(
          children: [mixedPlaybackSetting.widget, playerVolumeSetting.widget],
        ),
      ),
    );
    expect(find.text('当前:「100%」'), findsOneWidget);
    await tester.tap(find.text('与其他应用一起播放'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(150);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('当前:「150%」'), findsOneWidget);

    await tester.tap(find.text('播放器音量'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 150);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(25);
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('当前:「25%」'), findsOneWidget);
    await tester.tap(find.text('与其他应用一起播放'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 25);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    final systemWrites = <double>[];
    final volume = MobilePlaybackVolume(
      playerVolume: 0.25,
      setPlayerVolume: (_) async => fail('gesture must not change player gain'),
      setSystemVolume: (value) async => systemWrites.add(value),
      onDisplayChanged: (_) {},
    );
    await volume.setVolume(0.6);
    await tester.pumpAndSettle();
    expect(systemWrites, [0.6]);
    expect(volume.playerVolume, 0.25);
    expect(settings.data[SettingBoxKey.playerVolume], 25);
    expect(find.text('当前:「25%」'), findsOneWidget);
    expect(
      settings.data.containsKey(SettingBoxKey.mixWithOthersVolume),
      isFalse,
    );
  });

  testWidgets('the original player-volume dialog saves 0% and 300%', (
    tester,
  ) async {
    await tester.pumpWidget(app(playerVolumeSetting.widget));
    await tester.tap(find.text('播放器音量'));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0);
    expect(slider.max, 300);
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(settings.data[SettingBoxKey.playerVolume], 0);
    await tester.tap(find.text('播放器音量'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(settings.data[SettingBoxKey.playerVolume], 300);
  });

  testWidgets(
    'relative-volume controls fit a narrow iPad window with large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          MixedPlaybackVolumeDialog(value: 200, onChanged: (_) {}),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('完成'), findsOneWidget);
    },
  );
}
