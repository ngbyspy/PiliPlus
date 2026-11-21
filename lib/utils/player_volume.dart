import 'package:PiliPlus/utils/storage_key.dart';
import 'package:hive_ce/hive.dart';

/// One player gain shared by settings, player menus and mixed-mode gestures.
abstract final class PlayerVolume {
  static const minPercent = 0.0;
  static const maxPercent = 300.0;
  static const defaultPercent = 100.0;

  static double read(Box<dynamic> settings) => (settings.get(
    SettingBoxKey.playerVolume,
    defaultValue: defaultPercent,
  ) as num).toDouble().clamp(minPercent, maxPercent);

  /// Keep the gain that was active before the two controls were unified.
  static Future<void> migrate(Box<dynamic> settings) async {
    final legacy = settings.get(SettingBoxKey.mixWithOthersVolume);
    if (legacy == null) return;
    final mixing =
        settings.get(SettingBoxKey.mixWithOthers, defaultValue: false) as bool;
    final value = mixing
        ? (legacy as num).toDouble().clamp(minPercent, maxPercent)
        : read(settings);
    await settings.put(SettingBoxKey.playerVolume, value);
    await settings.delete(SettingBoxKey.mixWithOthersVolume);
  }
}
