import 'package:PiliPlus/utils/player_volume.dart';

/// Keeps system-volume gestures separate from player gain in every audio mode.
/// Values use 1.0 for 100%.
class MobilePlaybackVolume {
  MobilePlaybackVolume({
    required double playerVolume,
    required this._setPlayerVolume,
    required this._setSystemVolume,
    required this._onDisplayChanged,
  }) : _playerVolume = playerVolume.clamp(0.0, PlayerVolume.maxPercent / 100);

  double _playerVolume;
  double _systemVolume = 1.0;
  final Future<void> Function(double) _setPlayerVolume;
  final Future<void> Function(double) _setSystemVolume;
  final void Function(double) _onDisplayChanged;

  double get displayedVolume => _systemVolume;
  double get playerVolume => _playerVolume;

  void observeSystemVolume(double value) {
    _systemVolume = value.clamp(0.0, 1.0);
    _onDisplayChanged(displayedVolume);
  }

  Future<void> configure({
    required double playerVolume,
  }) async {
    final gain = playerVolume.clamp(0.0, PlayerVolume.maxPercent / 100);
    if (_playerVolume == gain) return;
    _playerVolume = gain;
    await _setPlayerVolume(gain);
  }

  Future<void> setVolume(double value) async {
    _systemVolume = value.clamp(0.0, 1.0);
    _onDisplayChanged(_systemVolume);
    await _setSystemVolume(_systemVolume);
  }
}
