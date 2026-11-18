// Cache inspection intentionally uses asynchronous I/O so scanning does not
// block the UI isolate on slow or externally mounted storage.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:PiliPlus/private/cache_exporter/domain.dart';

final class PiliCacheScanner {
  const PiliCacheScanner();

  Future<CacheScanResult> scanEntry(String entryDirectory) async {
    final diagnostics = <CacheDiagnostic>[];
    final entryDir = Directory(entryDirectory);
    if (!await entryDir.exists()) {
      return const CacheScanResult(
        diagnostics: [
          CacheDiagnostic(
            'entry_missing',
            'Cache entry directory does not exist.',
          ),
        ],
      );
    }

    final entryFile = File(path.join(entryDirectory, 'entry.json'));
    final entryJson = await _readJson(entryFile, diagnostics, 'entry');
    if (entryJson == null) return CacheScanResult(diagnostics: diagnostics);
    if (entryJson['is_completed'] != true) {
      diagnostics.add(
        const CacheDiagnostic(
          'cache_incomplete',
          'The cache entry is not marked complete.',
        ),
      );
    }

    final typeTag = entryJson['type_tag']?.toString();
    if (typeTag == null ||
        typeTag.isEmpty ||
        path.basename(typeTag) != typeTag) {
      diagnostics.add(
        const CacheDiagnostic(
          'quality_invalid',
          'entry.json has an invalid type_tag.',
        ),
      );
      return CacheScanResult(diagnostics: diagnostics);
    }
    final qualityDirectory = path.join(entryDirectory, typeTag);
    final qualityDir = Directory(qualityDirectory);
    if (!await qualityDir.exists()) {
      diagnostics.add(
        CacheDiagnostic(
          'quality_missing',
          'Quality directory is missing: $typeTag',
        ),
      );
      return CacheScanResult(diagnostics: diagnostics);
    }

    final indexFile = File(path.join(qualityDirectory, 'index.json'));
    final indexJson = await _readJson(indexFile, diagnostics, 'index');
    if (indexJson == null) return CacheScanResult(diagnostics: diagnostics);
    if (_containsDrm(indexJson)) {
      diagnostics.add(
        const CacheDiagnostic(
          'drm_detected',
          'Cache metadata indicates encrypted or DRM-protected media.',
        ),
      );
    }

    final progressive = File(path.join(qualityDirectory, '0.mp4'));
    final dashVideo = File(path.join(qualityDirectory, 'video.m4s'));
    final dashAudio = File(path.join(qualityDirectory, 'audio.m4s'));
    late final CachedMediaLayout layout;
    late final File video;
    File? audio;
    final progressiveReady = await _isNonEmpty(progressive);
    final dashVideoReady = await _isNonEmpty(dashVideo);
    final dashAudioReady = await _isNonEmpty(dashAudio);
    if (progressiveReady && !dashVideoReady && !dashAudioReady) {
      layout = CachedMediaLayout.progressiveMp4;
      video = progressive;
    } else if (!progressiveReady && dashVideoReady && dashAudioReady) {
      layout = CachedMediaLayout.dashTracks;
      video = dashVideo;
      audio = dashAudio;
    } else if (!progressiveReady && !dashVideoReady && !dashAudioReady) {
      diagnostics.add(
        const CacheDiagnostic(
          'media_missing',
          'No complete 0.mp4 or video.m4s + audio.m4s media set was found.',
        ),
      );
      return CacheScanResult(diagnostics: diagnostics);
    } else {
      diagnostics.add(
        const CacheDiagnostic(
          'media_ambiguous',
          'Cache contains an ambiguous or partial mixture of progressive and DASH media files.',
        ),
      );
      return CacheScanResult(diagnostics: diagnostics);
    }

    final aid = _asInt(entryJson['avid']);
    final bvid = entryJson['bvid']?.toString();
    final cid =
        _asInt((entryJson['source'] as Map?)?['cid']) ??
        _asInt((entryJson['page_data'] as Map?)?['cid']);
    final epId = _asInt((entryJson['ep'] as Map?)?['episode_id']);
    if (aid == null || cid == null || bvid == null || bvid.isEmpty) {
      diagnostics.add(
        const CacheDiagnostic(
          'identity_missing',
          'entry.json is missing aid, bvid, or cid required by the stable export DTO.',
        ),
      );
      return CacheScanResult(diagnostics: diagnostics);
    }

    final cover = File(path.join(entryDirectory, 'cover.jpg'));
    final danmaku = File(path.join(entryDirectory, 'danmaku.pb'));
    return CacheScanResult(
      source: CacheExportSource(
        entryDirectory: entryDirectory,
        qualityDirectory: qualityDirectory,
        indexFile: indexFile.path,
        layout: layout,
        videoFile: video.path,
        audioFile: audio?.path,
        coverFile: await _isNonEmpty(cover) ? cover.path : null,
        danmakuFile: await _isNonEmpty(danmaku) ? danmaku.path : null,
        title: _displayTitle(entryJson),
        aid: aid,
        bvid: bvid,
        cid: cid,
        epId: epId,
      ),
      diagnostics: diagnostics,
    );
  }

  Future<Map<String, dynamic>?> _readJson(
    File file,
    List<CacheDiagnostic> diagnostics,
    String kind,
  ) async {
    if (!await file.exists()) {
      diagnostics.add(
        CacheDiagnostic(
          '${kind}_missing',
          '${path.basename(file.path)} is missing.',
        ),
      );
      return null;
    }
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected an object');
      }
      return value;
    } catch (error) {
      diagnostics.add(
        CacheDiagnostic(
          '${kind}_corrupt',
          '${path.basename(file.path)} is invalid: $error',
        ),
      );
      return null;
    }
  }

  static Future<bool> _isNonEmpty(File file) async =>
      await file.exists() && await file.length() > 0;

  static int? _asInt(Object? value) => switch (value) {
    int value => value,
    String value => int.tryParse(value),
    _ => null,
  };

  static String _displayTitle(Map<String, dynamic> json) {
    final page = json['page_data'] as Map?;
    final episode = json['ep'] as Map?;
    final candidates = [
      page?['part'],
      episode?['show_title'],
      if (episode != null)
        '${episode['index'] ?? ''} ${episode['index_title'] ?? ''}'.trim(),
      json['title'],
    ];
    return candidates
        .map((item) => item?.toString().trim())
        .firstWhere(
          (item) => item != null && item.isNotEmpty,
          orElse: () => 'PiliPlus export',
        )!;
  }

  static bool _containsDrm(Object? value, [String? parentKey]) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        final child = entry.value;
        if ((key.contains('widevine') ||
                key == 'drm' ||
                key.contains('encryption')) &&
            child != null &&
            child != false &&
            child != 0 &&
            child != '') {
          return true;
        }
        if (_containsDrm(child, key)) return true;
      }
    } else if (value is List) {
      return value.any((item) => _containsDrm(item, parentKey));
    }
    return false;
  }
}
