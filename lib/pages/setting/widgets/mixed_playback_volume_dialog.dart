import 'package:PiliPlus/utils/player_volume.dart';
import 'package:material_ui/material_ui.dart';

class MixedPlaybackVolumeDialog extends StatefulWidget {
  const MixedPlaybackVolumeDialog({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<MixedPlaybackVolumeDialog> createState() =>
      _MixedPlaybackVolumeDialogState();
}

class _MixedPlaybackVolumeDialogState extends State<MixedPlaybackVolumeDialog> {
  late double _value = widget.value.clamp(
    PlayerVolume.minPercent,
    PlayerVolume.maxPercent,
  );

  void _change(double value) {
    setState(() => _value = value.roundToDouble());
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PiliPlus 相对音量'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_value.round()}%',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Slider(
                min: 0,
                max: PlayerVolume.maxPercent,
                divisions: 300,
                value: _value,
                label: '${_value.round()}%',
                semanticFormatterCallback: (value) =>
                    'PiliPlus 相对音量 ${value.round()}%',
                onChanged: _change,
              ),
              const Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('0%'),
                  Text('100%'),
                  Text('200%'),
                  Text('300%'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('只调整 PiliPlus 的声音，立即生效。视频右侧滑动和设备音量键始终调节系统音量。'),
              const SizedBox(height: 8),
              const Text('与设置、视频、直播及音频菜单中的“播放器音量”同步。'),
              const SizedBox(height: 8),
              const Text('100% 为原始音量；100% 以上可增强小音量内容，音量过高时可能失真，请按片源调整。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _change(100), child: const Text('恢复 100%')),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('完成'),
        ),
      ],
    );
  }
}
