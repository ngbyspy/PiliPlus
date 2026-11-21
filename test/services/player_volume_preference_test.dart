import 'package:PiliPlus/utils/player_volume.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => data[key] = value;

  @override
  Future<void> delete(dynamic key) async => data.remove(key);
}

void main() {
  test('new settings default to 100% and support mute through 300%', () {
    final settings = _Settings();
    expect(PlayerVolume.read(settings), 100);
    for (final value in [0, 50, 150, 300]) {
      settings.data[SettingBoxKey.playerVolume] = value;
      expect(PlayerVolume.read(settings), value);
    }
    settings.data[SettingBoxKey.playerVolume] = 999;
    expect(PlayerVolume.read(settings), 300);
  });

  test(
    'an upgrade keeps the active mixed gain and retires the split value',
    () async {
      final settings = _Settings()
        ..data.addAll({
          SettingBoxKey.mixWithOthers: true,
          SettingBoxKey.mixWithOthersVolume: 150.0,
          SettingBoxKey.playerVolume: 100.0,
        });
      await PlayerVolume.migrate(settings);
      expect(PlayerVolume.read(settings), 150);
      expect(
        settings.data.containsKey(SettingBoxKey.mixWithOthersVolume),
        isFalse,
      );
      await settings.put(SettingBoxKey.playerVolume, 25.0);
      await PlayerVolume.migrate(settings);
      expect(PlayerVolume.read(settings), 25);
    },
  );

  test(
    'an upgrade with mixing off keeps the original active player gain',
    () async {
      final settings = _Settings()
        ..data.addAll({
          SettingBoxKey.mixWithOthersVolume: 150.0,
          SettingBoxKey.playerVolume: 175.0,
        });
      await PlayerVolume.migrate(settings);
      expect(PlayerVolume.read(settings), 175);
    },
  );

  test('migration preserves a muted mixed player', () async {
    final settings = _Settings()
      ..data.addAll({
        SettingBoxKey.mixWithOthers: true,
        SettingBoxKey.mixWithOthersVolume: 0.0,
        SettingBoxKey.playerVolume: 100.0,
      });
    await PlayerVolume.migrate(settings);
    expect(PlayerVolume.read(settings), 0);
  });
}
