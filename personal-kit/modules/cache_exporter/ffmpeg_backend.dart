// FFmpeg output is checked asynchronously so validation does not block the UI
// isolate while the file system flushes a large temporary MP4.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:PiliPlus/private/cache_exporter/atomic_io.dart';
import 'package:PiliPlus/private/cache_exporter/domain.dart';

final class MediaProbe {
  const MediaProbe({this.videoCodec, this.audioCodec, this.durationSeconds});

  final String? videoCodec;
  final String? audioCodec;
  final double? durationSeconds;
}

final class FfmpegBackend {
  FfmpegBackend({String? toolsDirectory})
    : toolsDirectory =
          toolsDirectory ??
          path.join(
            File(Platform.resolvedExecutable).parent.path,
            'private_tools',
          );

  final String toolsDirectory;
  Process? _activeProcess;

  String get ffmpegPath => path.join(toolsDirectory, 'ffmpeg.exe');
  String get ffprobePath => path.join(toolsDirectory, 'ffprobe.exe');

  static const Set<String> _mp4VideoCodecs = {
    'h264',
    'hevc',
    'av1',
    'mpeg4',
    'mjpeg',
    'vp9',
  };
  static const Set<String> _mp4AudioCodecs = {
    'aac',
    'mp3',
    'ac3',
    'eac3',
    'alac',
  };

  Future<MediaProbe> probe(CacheExportSource source) async {
    _requireTools();
    final inputs = [
      source.videoFile,
      if (source.audioFile != null) source.audioFile!,
    ];
    String? videoCodec;
    String? audioCodec;
    double? duration;
    for (final input in inputs) {
      final result = await Process.run(ffprobePath, [
        '-v',
        'error',
        '-show_entries',
        'stream=codec_type,codec_name:format=duration',
        '-of',
        'json',
        input,
      ]);
      if (result.exitCode != 0) {
        throw ExportFailure(
          'probe_failed',
          'FFprobe rejected ${path.basename(input)}: ${result.stderr}',
        );
      }
      final decoded =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      for (final stream in (decoded['streams'] as List? ?? const [])) {
        final map = stream as Map;
        final codec = map['codec_name']?.toString().toLowerCase();
        switch (map['codec_type']) {
          case 'video':
            videoCodec ??= codec;
            break;
          case 'audio':
            audioCodec ??= codec;
            break;
        }
      }
      duration ??= double.tryParse(
        (decoded['format'] as Map?)?['duration']?.toString() ?? '',
      );
    }
    if (videoCodec == null) {
      throw const ExportFailure(
        'video_stream_missing',
        'No video stream was found in the completed cache.',
      );
    }
    if (source.audioFile != null && audioCodec == null) {
      throw const ExportFailure(
        'audio_stream_missing',
        'The DASH audio file contains no readable audio stream.',
      );
    }
    return MediaProbe(
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      durationSeconds: duration,
    );
  }

  Future<({bool videoReencoded, bool audioReencoded})> mux({
    required CacheExportSource source,
    required String finalPath,
    required CancellationToken cancellation,
    required ExportProgressCallback onProgress,
  }) async {
    cancellation.throwIfCancelled();
    final probeResult = await probe(source);
    final videoReencoded = !_mp4VideoCodecs.contains(probeResult.videoCodec);
    final audioReencoded =
        probeResult.audioCodec != null &&
        !_mp4AudioCodecs.contains(probeResult.audioCodec);
    final temporary = AtomicIo.temporaryPath(finalPath);
    try {
      final arguments = <String>[
        '-hide_banner',
        '-nostdin',
        '-y',
        '-progress',
        'pipe:1',
        '-nostats',
        '-i',
        source.videoFile,
        if (source.audioFile != null) ...['-i', source.audioFile!],
        '-map',
        '0:v:0',
        if (source.audioFile != null) ...[
          '-map',
          '1:a:0',
        ] else ...[
          '-map',
          '0:a?',
        ],
        '-c:v',
        videoReencoded ? 'libx264' : 'copy',
        if (videoReencoded) ...['-preset', 'medium', '-crf', '18'],
        '-c:a',
        audioReencoded ? 'aac' : 'copy',
        if (audioReencoded) ...['-b:a', '192k'],
        '-movflags',
        '+faststart',
        '-f',
        'mp4',
        temporary,
      ];
      onProgress(
        ExportProgress(
          videoReencoded
              ? ExportStage.convertingVideo
              : audioReencoded
              ? ExportStage.convertingAudio
              : ExportStage.muxing,
          0,
          videoReencoded
              ? 'Video codec ${probeResult.videoCodec} is not MP4-compatible; converting to H.264.'
              : audioReencoded
              ? 'Audio codec ${probeResult.audioCodec} is not MP4-compatible; converting audio to AAC.'
              : 'Losslessly merging cached streams.',
        ),
      );
      await _run(
        arguments,
        durationSeconds: probeResult.durationSeconds,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      if (!await File(temporary).exists() ||
          await File(temporary).length() == 0) {
        throw const ExportFailure(
          'empty_output',
          'FFmpeg completed without a non-empty MP4 output.',
        );
      }
      await _validateOutput(temporary);
      cancellation.throwIfCancelled();
      await AtomicIo.complete(temporary, finalPath);
      return (videoReencoded: videoReencoded, audioReencoded: audioReencoded);
    } finally {
      await AtomicIo.deleteIfPresent(temporary);
    }
  }

  Future<void> cancel() async {
    final process = _activeProcess;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      process.kill(ProcessSignal.sigkill);
    }
  }

  void _requireTools() {
    for (final executable in [ffmpegPath, ffprobePath]) {
      if (!File(executable).existsSync()) {
        throw ExportFailure(
          'ffmpeg_missing',
          'Private build dependency is missing: $executable',
        );
      }
    }
  }

  Future<void> _run(
    List<String> arguments, {
    required double? durationSeconds,
    required CancellationToken cancellation,
    required ExportProgressCallback onProgress,
  }) async {
    _requireTools();
    final process = await Process.start(ffmpegPath, arguments);
    _activeProcess = process;
    final stderr = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write);
    final progressSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('out_time_ms=') ||
              durationSeconds == null ||
              durationSeconds <= 0) {
            return;
          }
          final microseconds = int.tryParse(
            line.substring('out_time_ms='.length),
          );
          if (microseconds == null) return;
          onProgress(
            ExportProgress(
              ExportStage.muxing,
              (microseconds / 1000000 / durationSeconds).clamp(0.0, 0.99),
              'Exporting MP4…',
            ),
          );
        });
    final cancelSubscription = cancellation.whenCancelled.asStream().listen(
      (_) => cancel(),
    );
    try {
      final exitCode = await process.exitCode;
      if (cancellation.isCancelled) throw const ExportCancelled();
      if (exitCode != 0) {
        throw ExportFailure(
          'ffmpeg_failed',
          'FFmpeg exited with $exitCode: ${stderr.toString().trim()}',
        );
      }
    } finally {
      await progressSubscription.cancel();
      await stderrSubscription.cancel();
      await cancelSubscription.cancel();
      _activeProcess = null;
    }
  }

  Future<void> _validateOutput(String outputPath) async {
    final result = await Process.run(ffprobePath, [
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=codec_name',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      outputPath,
    ]);
    if (result.exitCode != 0 || (result.stdout as String).trim().isEmpty) {
      throw ExportFailure(
        'output_invalid',
        'The temporary MP4 failed post-mux validation: ${result.stderr}',
      );
    }
  }
}
