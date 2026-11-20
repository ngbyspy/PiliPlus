import 'dart:async';

import 'package:PiliPlus/services/mobile_playback_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<double> player;
  late List<double> system;
  late List<double> saved;
  late double display;

  MobilePlaybackVolume create({
    bool mixing = true,
    double relative = 1,
    Future<void> Function(double)? apply,
  }) => MobilePlaybackVolume(
    mixing: mixing,
    relativeVolume: relative,
    normalPlayerVolume: 1.3,
    setPlayerVolume: apply ?? (value) async => player.add(value),
    setSystemVolume: (value) async => system.add(value),
    saveRelativeVolume: (value) async => saved.add(value),
    onDisplayChanged: (value) => display = value,
  );

  setUp(() {
    player = [];
    system = [];
    saved = [];
    display = -1;
  });

  test(
    'mixed gestures cover mute through 200% without changing the device',
    () async {
      final volume = create();
      await volume.setVolume(0.5);
      await volume.setVolume(0);
      await volume.setVolume(2);
      expect(player, [0.5, 0, 2]);
      expect(saved, [0.5, 0, 2]);
      expect(system, isEmpty);
      expect(display, 2);
    },
  );

  test('relative volume remains inside its supported range', () async {
    final volume = create();
    await volume.setVolume(3);
    await volume.setVolume(-1);
    expect(player, [2, 0]);
    expect(saved, [2, 0]);
  });

  test('device buttons cannot overwrite the mixed playback level', () {
    final volume = create(relative: 1.75)..observeSystemVolume(0.2);
    expect(volume.displayedVolume, 1.75);
    expect(volume.playerVolume, 1.75);
    expect(system, isEmpty);
    expect(saved, isEmpty);
  });

  test(
    'turning mixing off restores the latest device slider and normal gain',
    () async {
      final volume = create(relative: 1.75)..observeSystemVolume(0.2);
      await volume.configure(
        mixing: false,
        relativeVolume: 1.75,
        normalPlayerVolume: 1.3,
      );
      expect(display, 0.2);
      expect(player, [1.3]);
      expect(system, isEmpty);
      await volume.setVolume(0.6);
      expect(system, [0.6]);
      expect(saved, isEmpty);
    },
  );

  test(
    'settings apply live and preserve the stored level through a mode change',
    () async {
      final volume = create();
      await volume.configure(
        mixing: true,
        relativeVolume: 0,
        normalPlayerVolume: 1.3,
      );
      await volume.configure(
        mixing: true,
        relativeVolume: 2,
        normalPlayerVolume: 1.3,
      );
      await volume.configure(
        mixing: false,
        relativeVolume: 2,
        normalPlayerVolume: 1.3,
      );
      await volume.configure(
        mixing: true,
        relativeVolume: 2,
        normalPlayerVolume: 1.3,
      );
      expect(player, [0, 2, 1.3, 2]);
      expect(display, 2);
      expect(system, isEmpty);
    },
  );

  test('a slow old gesture cannot replace the newer saved volume', () async {
    final oldRequest = Completer<void>();
    final volume = create(
      apply: (value) async {
        player.add(value);
        if (value == 1.2) await oldRequest.future;
      },
    );
    final old = volume.setVolume(1.2);
    await volume.setVolume(1.8);
    oldRequest.complete();
    await old;
    expect(saved, [1.8]);
    expect(display, 1.8);
  });

  test('a setting change wins over a pending gesture', () async {
    final oldRequest = Completer<void>();
    final volume = create(
      apply: (value) async {
        player.add(value);
        if (value == 1.2) await oldRequest.future;
      },
    );
    final old = volume.setVolume(1.2);
    await volume.configure(
      mixing: true,
      relativeVolume: 1.6,
      normalPlayerVolume: 1.3,
    );
    oldRequest.complete();
    await old;
    expect(saved, isEmpty);
    expect(display, 1.6);
  });
}
