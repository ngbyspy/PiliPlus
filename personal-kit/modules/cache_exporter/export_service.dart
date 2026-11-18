// Destination probing is asynchronous to keep removable/network destinations
// from blocking the UI isolate.
// ignore_for_file: avoid_slow_async_io

import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:PiliPlus/private/cache_exporter/atomic_io.dart';
import 'package:PiliPlus/private/cache_exporter/cache_scanner.dart';
import 'package:PiliPlus/private/cache_exporter/danmaku_converter.dart';
import 'package:PiliPlus/private/cache_exporter/domain.dart';
import 'package:PiliPlus/private/cache_exporter/ffmpeg_backend.dart';
import 'package:PiliPlus/private/cache_exporter/file_names.dart';

final class CacheExportService {
  CacheExportService({
    PiliCacheScanner? scanner,
    FfmpegBackend? ffmpeg,
    DanmakuConverter? danmaku,
    this.subtitles,
  }) : scanner = scanner ?? const PiliCacheScanner(),
       ffmpeg = ffmpeg ?? FfmpegBackend(),
       danmaku = danmaku ?? const DanmakuConverter();

  final PiliCacheScanner scanner;
  final FfmpegBackend ffmpeg;
  final DanmakuConverter danmaku;
  final SubtitleProvider? subtitles;

  Future<ExportResult> export({
    required String entryDirectory,
    required String destinationDirectory,
    required ExportOptions options,
    required CancellationToken cancellation,
    required ExportProgressCallback onProgress,
  }) async {
    onProgress(
      const ExportProgress(
        ExportStage.validating,
        0,
        'Validating completed cache…',
      ),
    );
    final scan = await scanner.scanEntry(entryDirectory);
    if (!scan.isCompatible) {
      throw ExportFailure(
        'cache_incompatible',
        scan.diagnostics.map((item) => item.toString()).join('\n'),
      );
    }
    final source = scan.source!;
    final destination = Directory(destinationDirectory);
    if (!await destination.exists()) {
      throw ExportFailure(
        'destination_missing',
        'The selected output directory does not exist: $destinationDirectory',
      );
    }
    await _assertWritable(destination);
    cancellation.throwIfCancelled();
    final base = ExportFileNames.chooseAvailableBase(
      destination.path,
      source.title,
    );
    final artifacts = <String>[];
    final warnings = scan.diagnostics
        .where((item) => !item.fatal)
        .map((item) => item.message)
        .toList();
    final videoPath = '$base.mp4';
    final muxResult = await ffmpeg.mux(
      source: source,
      finalPath: videoPath,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    artifacts.add(videoPath);

    cancellation.throwIfCancelled();
    if (options.exportCover) {
      onProgress(
        const ExportProgress(ExportStage.cover, null, 'Exporting cover…'),
      );
      if (source.coverFile != null) {
        final coverPath = '$base.cover.jpg';
        await AtomicIo.copy(source.coverFile!, coverPath);
        artifacts.add(coverPath);
      } else {
        warnings.add('No cached cover.jpg was available.');
      }
    }

    cancellation.throwIfCancelled();
    if (options.exportDanmakuXml || options.exportDanmakuAss) {
      onProgress(
        const ExportProgress(
          ExportStage.danmaku,
          null,
          'Converting cached danmaku…',
        ),
      );
      if (source.danmakuFile != null) {
        try {
          final entries = await danmaku.read(source.danmakuFile!);
          if (options.exportDanmakuXml) {
            final xml = '$base.danmaku.xml';
            await AtomicIo.writeText(
              xml,
              danmaku.toXml(entries, cid: source.cid),
            );
            artifacts.add(xml);
          }
          if (options.exportDanmakuAss) {
            final ass = '$base.danmaku.ass';
            await AtomicIo.writeText(ass, danmaku.toAss(entries));
            artifacts.add(ass);
          }
        } catch (error) {
          warnings.add('Danmaku conversion failed: $error');
        }
      } else {
        warnings.add('No cached danmaku.pb was available.');
      }
    }

    cancellation.throwIfCancelled();
    if (options.exportSubtitles) {
      onProgress(
        const ExportProgress(
          ExportStage.subtitles,
          null,
          'Discovering subtitles…',
        ),
      );
      if (options.downloadMissingSubtitles && subtitles != null) {
        try {
          final tracks = await subtitles!.discover(source);
          if (tracks.isEmpty) {
            warnings.add('No subtitles are available for this video.');
          }
          final used = <String>{};
          for (final track in tracks) {
            cancellation.throwIfCancelled();
            var language = ExportFileNames.sanitize(
              track.language,
              maxLength: 30,
            );
            var suffix = 1;
            while (!used.add(language.toLowerCase())) {
              language =
                  '${ExportFileNames.sanitize(track.language, maxLength: 24)}-${suffix++}';
            }
            final vtt = '$base.$language.vtt';
            final srt = '$base.$language.srt';
            await AtomicIo.writeText(vtt, track.vtt);
            await AtomicIo.writeText(srt, track.srt);
            artifacts.addAll([vtt, srt]);
          }
        } on ExportCancelled {
          rethrow;
        } catch (error) {
          warnings.add(
            'Subtitle discovery is unavailable (offline or no permission): $error',
          );
        }
      } else {
        warnings.add(
          'Subtitle discovery was disabled or no provider is available.',
        );
      }
    }

    onProgress(
      const ExportProgress(ExportStage.completed, 1, 'Export completed.'),
    );
    return ExportResult(
      videoPath: videoPath,
      artifacts: artifacts,
      warnings: warnings,
      videoReencoded: muxResult.videoReencoded,
      audioReencoded: muxResult.audioReencoded,
    );
  }

  Future<void> cancel(CancellationToken token) async {
    token.cancel();
    await ffmpeg.cancel();
  }

  static Future<void> _assertWritable(Directory directory) async {
    final probe = File(
      path.join(
        directory.path,
        '.piliplus-write-probe-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probe.writeAsString('probe', flush: true);
      await probe.delete();
    } on FileSystemException catch (error) {
      throw ExportFailure(
        'destination_not_writable',
        'The selected output directory is not writable.',
        cause: error,
      );
    }
  }
}
