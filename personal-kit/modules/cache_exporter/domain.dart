import 'dart:async';

enum CachedMediaLayout { progressiveMp4, dashTracks }

enum ExportStage {
  validating,
  probing,
  muxing,
  convertingAudio,
  convertingVideo,
  cover,
  subtitles,
  danmaku,
  finalizing,
  completed,
}

final class CacheExportSource {
  const CacheExportSource({
    required this.entryDirectory,
    required this.qualityDirectory,
    required this.indexFile,
    required this.layout,
    required this.videoFile,
    required this.title,
    required this.aid,
    required this.bvid,
    required this.cid,
    this.epId,
    this.audioFile,
    this.coverFile,
    this.danmakuFile,
  });

  final String entryDirectory;
  final String qualityDirectory;
  final String indexFile;
  final CachedMediaLayout layout;
  final String videoFile;
  final String? audioFile;
  final String? coverFile;
  final String? danmakuFile;
  final String title;
  final int aid;
  final String bvid;
  final int cid;
  final int? epId;
}

final class CacheDiagnostic {
  const CacheDiagnostic(this.code, this.message, {this.fatal = true});

  final String code;
  final String message;
  final bool fatal;

  @override
  String toString() => '$code: $message';
}

final class CacheScanResult {
  const CacheScanResult({this.source, this.diagnostics = const []});

  final CacheExportSource? source;
  final List<CacheDiagnostic> diagnostics;

  bool get isCompatible =>
      source != null && diagnostics.every((diagnostic) => !diagnostic.fatal);
}

final class ExportOptions {
  const ExportOptions({
    this.exportCover = true,
    this.exportDanmakuXml = true,
    this.exportDanmakuAss = true,
    this.exportSubtitles = true,
    this.downloadMissingSubtitles = true,
  });

  final bool exportCover;
  final bool exportDanmakuXml;
  final bool exportDanmakuAss;
  final bool exportSubtitles;
  final bool downloadMissingSubtitles;
}

final class ExportProgress {
  const ExportProgress(this.stage, this.fraction, this.message);

  final ExportStage stage;
  final double? fraction;
  final String message;
}

final class SubtitleAsset {
  const SubtitleAsset({
    required this.language,
    required this.label,
    required this.vtt,
    required this.srt,
  });

  final String language;
  final String label;
  final String vtt;
  final String srt;
}

abstract interface class SubtitleProvider {
  Future<List<SubtitleAsset>> discover(CacheExportSource source);
}

final class ExportResult {
  const ExportResult({
    required this.videoPath,
    required this.artifacts,
    required this.warnings,
    required this.videoReencoded,
    required this.audioReencoded,
  });

  final String videoPath;
  final List<String> artifacts;
  final List<String> warnings;
  final bool videoReencoded;
  final bool audioReencoded;
}

final class ExportFailure implements Exception {
  const ExportFailure(this.code, this.message, {this.cause});

  final String code;
  final String message;
  final Object? cause;

  @override
  String toString() => '$code: $message';
}

final class ExportCancelled implements Exception {
  const ExportCancelled();

  @override
  String toString() => 'Export cancelled';
}

final class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const ExportCancelled();
  }
}

typedef ExportProgressCallback = void Function(ExportProgress progress);
