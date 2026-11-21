import 'dart:async';

import 'package:PiliPlus/services/playback_audio_session.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Session extends Fake implements AudioSession {
  final events = <String>[];
  final configurations = <AudioSessionConfiguration>[];
  final deactivationOptions = <AVAudioSessionSetActiveOptions?>[];
  Completer<void>? configureGate;
  bool failNextConfigure = false;
  bool allowActivation = true;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    events.add('configure');
    await configureGate?.future;
    if (failNextConfigure) {
      failNextConfigure = false;
      throw StateError('native configuration failed');
    }
    configurations.add(configuration);
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    events.add('active:$active');
    if (!active) deactivationOptions.add(avAudioSessionSetActiveOptions);
    return !active || allowActivation;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Session session;

  PlaybackAudioSession create(TargetPlatform platform, {bool mixing = false}) =>
      PlaybackAudioSession(
        session: session,
        platform: platform,
        mixWithOthers: mixing,
      );

  setUp(() {
    session = _Session();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.piliplus/audio_mix'),
          (call) async {
            expect(call.method, 'setMixWithOthers');
            session.events.add('iosMix:${call.arguments}');
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.example.piliplus/audio_mix'),
          null,
        );
  });

  test('Android mixed playback never requests even ducking focus', () async {
    final policy = create(TargetPlatform.android, mixing: true);
    await policy.configure();
    expect(await policy.setActive(true), isTrue);
    await policy.setActive(false);
    expect(await policy.setActive(true), isTrue);
    expect(session.events.where((event) => event == 'active:true'), isEmpty);
    expect(session.events, contains('active:false'));
  });

  test('normal Android playback respects a denied focus request', () async {
    final policy = create(TargetPlatform.android);
    session.allowActivation = false;
    expect(await policy.setActive(true), isFalse);
    expect(session.events, ['configure', 'active:true']);
    expect(
      session.configurations.single.androidAudioFocusGainType,
      AndroidAudioFocusGainType.gain,
    );
  });

  test('enabling Android mixing releases focus without reacquiring', () async {
    final policy = create(TargetPlatform.android);
    await policy.setActive(true);
    session.events.clear();
    await policy.setMixWithOthers(true, isPlaying: true);
    expect(session.events, ['active:false', 'configure']);
    session.events.clear();
    await policy.setMixWithOthers(false, isPlaying: true);
    expect(session.events, ['active:false', 'configure', 'active:true']);
  });

  test('changing the setting while paused cannot steal focus', () async {
    final policy = create(TargetPlatform.android, mixing: true);
    await policy.setMixWithOthers(false, isPlaying: false);
    expect(session.events, ['active:false', 'configure']);
  });

  test(
    'iOS protects legacy plugins before configuring and activating',
    () async {
      final policy = create(TargetPlatform.iOS, mixing: true);
      await policy.setActive(true);
      expect(session.events, ['iosMix:true', 'configure', 'active:true']);
      final config = session.configurations.single;
      expect(config.avAudioSessionCategory, AVAudioSessionCategory.playback);
      expect(
        config.avAudioSessionCategoryOptions,
        AVAudioSessionCategoryOptions.mixWithOthers,
      );
      expect(
        config.avAudioSessionCategoryOptions!.contains(
          AVAudioSessionCategoryOptions.duckOthers,
        ),
        isFalse,
      );
    },
  );

  test('iOS toggles a live session without deactivating playback', () async {
    final policy = create(TargetPlatform.iOS);
    await policy.setMixWithOthers(true, isPlaying: true);
    expect(session.events, ['iosMix:true', 'configure', 'active:true']);
    session.events.clear();
    await policy.setMixWithOthers(false, isPlaying: true);
    expect(session.events, ['iosMix:false', 'configure', 'active:true']);
    expect(
      session.configurations.last.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.none,
    );
    await policy.setActive(false);
    expect(
      session.deactivationOptions.single,
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  });

  test('a play request waits for an in-flight setting change', () async {
    final policy = create(TargetPlatform.android);
    session.configureGate = Completer<void>();
    final change = policy.setMixWithOthers(true, isPlaying: true);
    final play = policy.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(session.events, ['active:false', 'configure']);
    session.configureGate!.complete();
    await change;
    expect(await play, isTrue);
    expect(session.events, ['active:false', 'configure', 'configure']);
  });

  test('a native failure does not poison later playback requests', () async {
    final policy = create(TargetPlatform.android);
    session.failNextConfigure = true;
    await expectLater(policy.setActive(true), throwsStateError);
    expect(await policy.setActive(true), isTrue);
    expect(session.events, ['configure', 'configure', 'active:true']);
  });
}
