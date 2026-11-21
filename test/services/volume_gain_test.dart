import 'package:PiliPlus/models/common/audio_normalization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

class _Player extends Fake implements Player {
  final volumes = <double>[];
  final filters = <String>[];
  final properties = <(String, String)>[];

  @override
  void setProperty(String property, String value) {
    properties.add((property, value));
    if (property == 'af') filters.add(value);
  }

  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) async {
    volumes.add(volume);
  }
}

class _Volume with AudioNormalizationMixin {}

class _IosVolume extends _Volume {
  @override
  bool get supportsVolumeLimiter => false;
}

void main() {
  test('0–100% includes actual silence without a boost filter', () async {
    final volume = _Volume();
    final player = _Player();
    await volume.setVolumeCapped(player, 0);
    await volume.setVolumeCapped(player, 0.5);
    await volume.setVolumeCapped(player, 1);
    expect(player.volumes, [0, 50, 100]);
    expect(player.filters, isEmpty);
  });

  test(
    '300% boosts through a limiter without overdriving mpv volume',
    () async {
      final player = _Player();
      await _Volume().setVolumeCapped(player, 3);
      expect(player.volumes, [100]);
      final filter = player.filters.single;
      expect(filter, contains('alimiter='));
      expect(filter, contains(':limit=1:level=0'));
      final gain = double.parse(
        RegExp(r'level_in=([0-9.]+)').firstMatch(filter)![1]!,
      );
      expect(gain, greaterThan(1));
    },
  );

  test('returning from boost to silence removes the boost filter', () async {
    final player = _Player();
    final volume = _Volume();
    await volume.setVolumeCapped(player, 2);
    await volume.setVolumeCapped(player, 0);
    expect(player.filters.last, '');
    expect(player.volumes.last, 0);
  });

  test('a replacement player receives its own boost configuration', () async {
    final volume = _Volume();
    final first = _Player();
    final replacement = _Player();
    await volume.setVolumeCapped(first, 2);
    await volume.setVolumeCapped(replacement, 2);
    expect(replacement.filters, first.filters);
    expect(replacement.volumes, [100]);
  });

  test(
    'the minimal iOS library boosts without requesting a missing filter',
    () async {
      final player = _Player();
      final volume = _IosVolume();
      await volume.setVolumeCapped(player, 2);
      expect(player.volumes, [200]);
      expect(player.properties, [('volume-max', '200')]);
      expect(player.filters, isEmpty);
      await volume.setVolumeCapped(player, 3);
      expect(player.volumes.last, 300);
      expect(player.properties.last, ('volume-max', '300'));
      await volume.setVolumeCapped(player, 0);
      expect(player.volumes.last, 0);
    },
  );
}
