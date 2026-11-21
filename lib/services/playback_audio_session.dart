import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

/// Owns the app's audio policy for both video/live and audio-only playback.
class PlaybackAudioSession {
  PlaybackAudioSession({
    required this._session,
    required this._platform,
    required this._mixWithOthers,
  });

  static const _iosChannel = MethodChannel('com.example.piliplus/audio_mix');

  final AudioSession _session;
  final TargetPlatform _platform;
  bool _mixWithOthers;
  bool get mixWithOthers => _mixWithOthers;

  // Keep setting changes and play/pause requests in order, including when a
  // previous native request failed.
  Future<void> _pending = Future.value();
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> configure() => _run(_configure);

  Future<void> _configure() async {
    if (_platform == TargetPlatform.iOS) {
      // mpv 0.39 and the volume listener use the legacy setCategory:error:
      // setter. Protect it before either plugin can activate the session.
      await _iosChannel.invokeMethod<void>('setMixWithOthers', _mixWithOthers);
    }
    await _session.configure(
      const AudioSessionConfiguration.music().copyWith(
        avAudioSessionCategoryOptions: _mixWithOthers
            ? AVAudioSessionCategoryOptions.mixWithOthers
            : AVAudioSessionCategoryOptions.none,
      ),
    );
  }

  Future<bool> setActive(bool active) => _run(() async {
    if (active) {
      await _configure();
      // MAY_DUCK still requests focus and can pause another player. Mixing on
      // Android requires making no focus request at all.
      if (_platform == TargetPlatform.android && _mixWithOthers) return true;
    }
    return _session.setActive(
      active,
      avAudioSessionSetActiveOptions: active
          ? AVAudioSessionSetActiveOptions.none
          : AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
    );
  });

  Future<void> setMixWithOthers(
    bool enabled, {
    required bool isPlaying,
  }) => _run(() async {
    if (_mixWithOthers == enabled) return;
    _mixWithOthers = enabled;
    // Release an existing Android focus request before entering mixed mode.
    // No deactivation on iOS: changing a live session's category is supported.
    if (_platform == TargetPlatform.android) {
      await _session.setActive(false);
    }
    await _configure();
    if (isPlaying && !(_platform == TargetPlatform.android && _mixWithOthers)) {
      await _session.setActive(true);
    }
  });
}
