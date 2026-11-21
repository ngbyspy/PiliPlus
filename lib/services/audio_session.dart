import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/services/playback_audio_session.dart';
import 'package:PiliPlus/services/service_locator.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

class AudioSessionHandler {
  late AudioSession _session;
  late PlaybackAudioSession _playbackSession;
  late final Future<void> ready;
  bool _shouldResume = false;

  Future<bool> setActive(bool active) async {
    await ready;
    return _playbackSession.setActive(active);
  }

  Future<void> setMixWithOthers(bool enabled) async {
    await ready;
    _shouldResume = false;
    await _playbackSession.setMixWithOthers(
      enabled,
      isPlaying:
          videoPlayerServiceHandler?.isPlaying?.call() ??
          PlPlayerController.instance?.playerStatus.isPlaying ??
          false,
    );
  }

  AudioSessionHandler() {
    ready = initSession();
  }

  Future<void> initSession() async {
    _session = await AudioSession.instance;
    _playbackSession = PlaybackAudioSession(
      session: _session,
      platform: defaultTargetPlatform,
      mixWithOthers: Pref.mixWithOthers,
    );
    await _playbackSession.configure();

    _session.interruptionEventStream.listen(_onInterrupted);

    // 耳机拔出暂停
    _session.becomingNoisyEventStream.listen((_) {
      videoPlayerServiceHandler?.onPause?.call() ??
          PlPlayerController.pauseIfExists();
    });
  }

  void _onInterrupted(AudioInterruptionEvent event) {
    // Ignore focus-loss events already queued when we abandoned Android focus.
    // iOS system interruptions (for example calls) retain their normal handling.
    if (defaultTargetPlatform == TargetPlatform.android &&
        _playbackSession.mixWithOthers) {
      return;
    }
    if (event.begin) {
      final player = PlPlayerController.instance;
      switch (event.type) {
        case .duck:
          if (player != null && player.playerStatus.isPlaying) {
            player.setVolume(player.volume.value * 0.5, showIndicator: false);
          }
        case .pause:
        case .unknown:
          final isAudioPlaying = videoPlayerServiceHandler?.isPlaying;
          if (isAudioPlaying != null) {
            if (isAudioPlaying()) {
              _shouldResume = true;
              videoPlayerServiceHandler?.onPause?.call();
            }
          } else if (player != null && player.playerStatus.isPlaying) {
            _shouldResume = true;
            player.pause(isInterrupt: true);
          }
      }
    } else {
      switch (event.type) {
        case .duck:
          final player = PlPlayerController.instance;
          player?.setVolume(player.volume.value * 2, showIndicator: false);
        case .pause:
          if (_shouldResume) {
            _shouldResume = false;
            videoPlayerServiceHandler?.onPlay?.call() ??
                PlPlayerController.instance?.play();
          }
        case .unknown:
      }
    }
  }
}
