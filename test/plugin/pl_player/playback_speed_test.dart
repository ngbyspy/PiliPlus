import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_source.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';

class _Player extends Fake implements Player {
  @override
  final state = PlayerState();
  final rates = <double>[];
  final commands = <List<String>>[];
  Future<void>? commandGate;
  bool failCommand = false;
  Future<void>? gate;
  bool failNext = false;
  Future<void> _pending = Future.value();

  @override
  Future<void> command(List<String> args) async {
    commands.add(List.of(args));
    await commandGate;
    if (failCommand) throw StateError('cache option rejected');
  }

  @override
  Future<void> setRate(double rate, {bool synchronized = true}) {
    rates.add(rate);
    if (failNext) {
      failNext = false;
      return Future.error(StateError('native rate failed'));
    }
    return _pending = _pending.then((_) async {
      await gate;
      state.rate = rate;
    });
  }
}

class _Controller extends PlPlayerController {
  _Controller(this.player) : super.forTesting() {
    playerStatus = PlayerStatus.playing;
    enableAutoLongPressSpeed = false;
    dataSource = NetworkSource(
      videoSource: 'https://example.test/video',
      audioSource: null,
    );
  }
  @override
  double get longPressSpeed => 3;
  Player? player;
  @override
  Player? get videoPlayerController => player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Player player;
  late _Controller controller;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-speed-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.video.clear();
    player = _Player();
    controller = _Controller(player);
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'hold restores the chosen rate and buffer without changing preferences',
    () async {
      await controller.setPlaybackSpeed(1.5);
      await controller.setLongPressStatus(true);
      expect(player.state.rate, 3);
      expect(controller.lastPlaybackSpeed, 1.5);
      await controller.setLongPressStatus(false);
      expect(player.state.rate, 1.5);
      expect(controller.playbackSpeed, 1.5);
      expect(GStorage.setting.isEmpty, isTrue);
      expect(GStorage.video.isEmpty, isTrue);
    },
  );

  test('automatic hold doubles the normal rate without compounding', () async {
    controller.enableAutoLongPressSpeed = true;
    await controller.setPlaybackSpeed(1.25);
    await controller.setLongPressStatus(true);
    await controller.setLongPressStatus(true);
    expect(player.state.rate, 2.5);
    await controller.setLongPressStatus(false);
    expect(player.state.rate, 1.25);
  });

  test('rapid hold release hold coalesces obsolete rate requests', () async {
    await Future.wait([
      controller.setLongPressStatus(true),
      controller.setLongPressStatus(false),
      controller.setLongPressStatus(true),
    ]);
    expect(player.rates, [3.0]);
    expect(controller.lastPlaybackSpeed, 1);
    expect(controller.playbackSpeed, 3);
    await controller.setLongPressStatus(false);
    expect(player.state.rate, 1);
  });

  test(
    'release queues baseline even when native state still reports baseline',
    () async {
      final blocked = Completer<void>();
      player.gate = blocked.future;
      final hold = controller.setLongPressStatus(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.state.rate, 1);
      expect(player.rates, [3]);
      final release = controller.setLongPressStatus(false);
      blocked.complete();
      await Future.wait([hold, release]);
      expect(player.state.rate, 1);
      expect(controller.playbackSpeed, 1);
    },
  );

  test('a replaced player cannot publish a stale speed', () async {
    final blocked = Completer<void>();
    player.gate = blocked.future;
    final change = controller.setPlaybackSpeed(2);
    await Future<void>.delayed(Duration.zero);
    controller.player = null;
    blocked.complete();
    await change;
    expect(controller.playbackSpeed, 1);
  });

  test('native failure does not prevent a later speed request', () async {
    player.failNext = true;
    await expectLater(controller.setPlaybackSpeed(2), throwsStateError);
    await controller.setPlaybackSpeed(1);
    expect(controller.playbackSpeed, 1);
    expect(player.state.rate, 1);
  });

  test('live ignores hold gestures', () async {
    controller.isLive = true;
    await controller.setLongPressStatus(true);
    expect(player.rates, isEmpty);
    expect(controller.longPressStatus.value, isFalse);
  });

  test('first hold restores the saved default speed', () async {
    await GStorage.video.put(VideoBoxKey.playSpeedDefault, 1.5);
    controller = _Controller(player);
    player.state.rate = 1.5;
    await controller.setLongPressStatus(true);
    await controller.setLongPressStatus(false);
    expect(player.state.rate, 1.5);
  });

  test(
    'prefetch seconds follow rate and restore while byte budgets stay fixed',
    () async {
      await GStorage.setting.put(SettingBoxKey.bufferSec, 16.0);
      await GStorage.setting.put(SettingBoxKey.bufferSize, 32.0);
      final bytes = controller.buffer['demuxer-max-bytes'];
      await controller.setPlaybackSpeed(2);
      expect(player.commands, [
        ['set', 'cache-secs', '32.000'],
        ['set', 'demuxer-hysteresis-secs', '21.333'],
      ]);
      expect(controller.buffer['cache-secs'], '32.000');
      expect(controller.buffer['demuxer-max-bytes'], bytes);
      expect(controller.buffer['demuxer-max-back-bytes'], bytes);
      player.commands.clear();
      await controller.setLongPressStatus(true);
      expect(player.commands.first.last, '48.000');
      await controller.setLongPressStatus(false);
      expect(player.commands[player.commands.length - 2].last, '32.000');
    },
  );

  test('live and local files do not receive network buffer updates', () async {
    controller.isLive = true;
    await controller.setPlaybackSpeed(2);
    expect(player.commands, isEmpty);
    controller
      ..isLive = false
      ..dataSource = FileSource(
        dir: 'local',
        isMp4: true,
        hasDashAudio: false,
        typeTag: '1',
      );
    await controller.setPlaybackSpeed(1.5);
    expect(player.commands, isEmpty);
    expect(player.state.rate, 1.5);
  });

  test(
    'a blocked old buffer update cannot overwrite the latest speed',
    () async {
      final gate = Completer<void>();
      player.commandGate = gate.future;
      final old = controller.setPlaybackSpeed(3);
      await Future<void>.delayed(Duration.zero);
      final latest = controller.setPlaybackSpeed(1);
      gate.complete();
      await Future.wait([old, latest]);
      expect(controller.playbackSpeed, 1);
      expect(player.state.rate, 1);
      expect(player.commands.last, [
        'set',
        'demuxer-hysteresis-secs',
        '10.667',
      ]);
    },
  );

  test('rejected cache option does not break speed control', () async {
    player.failCommand = true;
    await controller.setPlaybackSpeed(2);
    expect(controller.playbackSpeed, 2);
    expect(player.state.rate, 2);
  });
}
