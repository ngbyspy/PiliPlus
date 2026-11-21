import 'package:PiliPlus/utils/player_volume.dart';

/// Routes the player's gesture volume independently from the device volume
/// while mixed playback is enabled. Values use 1.0 for 100%.
class MobilePlaybackVolume {
  MobilePlaybackVolume({
    required this._mixing,
    required this._relativeVolume,
    required this._normalPlayerVolume,
    required this._setPlayerVolume,
    required this._setSystemVolume,
    required this._saveRelativeVolume,
    required this._onDisplayChanged,
  });

  static const maxRelativeVolume = PlayerVolume.maxPercent / 100;
  bool _mixing;
  double _relativeVolume;
  double _normalPlayerVolume;
  double _systemVolume = 1.0;
  int _revision = 0;
  final Future<void> Function(double) _setPlayerVolume;
  final Future<void> Function(double) _setSystemVolume;
  final Future<void> Function(double) _saveRelativeVolume;
  final void Function(double) _onDisplayChanged;

  double get displayedVolume => _mixing ? _relativeVolume : _systemVolume;
  double get playerVolume => _mixing ? _relativeVolume : _normalPlayerVolume;

  void observeSystemVolume(double value) {
    _systemVolume = value.clamp(0.0, 1.0);
    if (!_mixing) _onDisplayChanged(displayedVolume);
  }

  Future<void> configure({
    required bool mixing,
    required double relativeVolume,
    required double normalPlayerVolume,
  }) async {
    final previous = playerVolume;
    final relative = relativeVolume.clamp(0.0, maxRelativeVolume);
    if (_mixing != mixing || _relativeVolume != relative) _revision++;
    _mixing = mixing;
    _relativeVolume = relative;
    _normalPlayerVolume = normalPlayerVolume;
    _onDisplayChanged(displayedVolume);
    if (playerVolume != previous) await _setPlayerVolume(playerVolume);
  }

  Future<void> setVolume(double value) async {
    if (_mixing) {
      final relative = value.clamp(0.0, maxRelativeVolume);
      final revision = ++_revision;
      _relativeVolume = relative;
      _onDisplayChanged(relative);
      await _setPlayerVolume(relative);
      // A setting change or a newer gesture must win over a slow old request.
      if (revision == _revision) await _saveRelativeVolume(relative);
    } else {
      _systemVolume = value.clamp(0.0, 1.0);
      _onDisplayChanged(_systemVolume);
      await _setSystemVolume(_systemVolume);
    }
  }
}
