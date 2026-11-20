import 'package:PiliPlus/pages/setting/models/play_settings.dart';
import 'package:PiliPlus/pages/setting/widgets/mixed_playback_volume_dialog.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;
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
      expect(settings.data[SettingBoxKey.mixWithOthersVolume], 200);
      await tester.tap(find.text('恢复 100%'));
      await tester.pumpAndSettle();
      expect(settings.data[SettingBoxKey.mixWithOthersVolume], 100);
    },
  );

  testWidgets('the slider reaches 0% and 200% and restores 100%', (
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
    expect(writes.last, 200);
    await tester.tap(find.text('恢复 100%'));
    await tester.pumpAndSettle();
    expect(writes.last, 100);
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
