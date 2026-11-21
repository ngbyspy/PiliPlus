import 'dart:async';

import 'package:PiliPlus/services/mobile_playback_volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<double> player;
  late List<double> system;
  late double display;

  MobilePlaybackVolume create({
    double gain = 1.5,
    Future<void> Function(double)? setSystem,
  }) => MobilePlaybackVolume(
    playerVolume: gain,
    setPlayerVolume: (value) async => player.add(value),
    setSystemVolume: setSystem ?? (value) async => system.add(value),
    onDisplayChanged: (value) => display = value,
  );

  setUp(() {
    player = [];
    system = [];
    display = -1;
  });

  test(
    'gestures only change system volume and preserve the player gain',
    () async {
      final volume = create();
      await volume.setVolume(0.5);
      await volume.setVolume(0);
      await volume.setVolume(1);
      expect(system, [0.5, 0, 1]);
      expect(player, isEmpty);
      expect(volume.playerVolume, 1.5);
      expect(display, 1);
    },
  );

  test('gesture values stay inside the system 0–100% range', () async {
    final volume = create();
    await volume.setVolume(3);
    await volume.setVolume(-1);
    expect(system, [1, 0]);
    expect(player, isEmpty);
    expect(volume.playerVolume, 1.5);
  });

  test('device buttons update the HUD without overwriting player gain', () {
    final volume = create(gain: 1.75)..observeSystemVolume(0.2);
    expect(volume.displayedVolume, 0.2);
    expect(display, 0.2);
    expect(volume.playerVolume, 1.75);
    expect(system, isEmpty);
    expect(player, isEmpty);
  });

  test(
    'settings cover mute through 300% without changing system volume',
    () async {
      final volume = create()..observeSystemVolume(0.4);
      await volume.configure(playerVolume: 0);
      await volume.configure(playerVolume: 1.5);
      await volume.configure(playerVolume: 3);
      expect(player, [0, 1.5, 3]);
      expect(volume.playerVolume, 3);
      expect(volume.displayedVolume, 0.4);
      expect(display, 0.4);
      expect(system, isEmpty);
    },
  );

  test('a pending gesture cannot replace a newer gain setting', () async {
    final pending = Completer<void>();
    final volume = create(
      setSystem: (value) async {
        system.add(value);
        await pending.future;
      },
    );
    final gesture = volume.setVolume(0.6);
    await volume.configure(playerVolume: 2.5);
    pending.complete();
    await gesture;
    expect(system, [0.6]);
    expect(player, [2.5]);
    expect(volume.playerVolume, 2.5);
    expect(display, 0.6);
  });
}
