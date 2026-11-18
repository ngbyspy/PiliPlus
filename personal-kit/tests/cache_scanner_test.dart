// Fixtures use asynchronous I/O to mirror the production scanner contract.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/private/cache_exporter/cache_scanner.dart';
import 'package:PiliPlus/private/cache_exporter/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'piliplus-cache-scanner-',
    );
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('accepts a complete progressive cache', () async {
    await _fixture(temporary, progressive: true);
    final result = await const PiliCacheScanner().scanEntry(temporary.path);
    expect(result.isCompatible, isTrue);
    expect(result.source!.layout, CachedMediaLayout.progressiveMp4);
    expect(result.source!.cid, 456);
  });

  test('accepts complete DASH tracks', () async {
    await _fixture(temporary, dash: true);
    final result = await const PiliCacheScanner().scanEntry(temporary.path);
    expect(result.isCompatible, isTrue);
    expect(result.source!.layout, CachedMediaLayout.dashTracks);
    expect(result.source!.audioFile, endsWith('audio.m4s'));
  });

  test('rejects incomplete and partial caches', () async {
    await _fixture(temporary, dashVideoOnly: true, completed: false);
    final result = await const PiliCacheScanner().scanEntry(temporary.path);
    expect(result.isCompatible, isFalse);
    expect(
      result.diagnostics.map((item) => item.code),
      containsAll(['cache_incomplete', 'media_ambiguous']),
    );
  });

  test('rejects traversal in type_tag', () async {
    await _fixture(temporary, progressive: true, typeTag: '..\\outside');
    final result = await const PiliCacheScanner().scanEntry(temporary.path);
    expect(result.isCompatible, isFalse);
    expect(result.diagnostics.single.code, 'quality_invalid');
  });
}

Future<void> _fixture(
  Directory root, {
  bool progressive = false,
  bool dash = false,
  bool dashVideoOnly = false,
  bool completed = true,
  String typeTag = '80',
}) async {
  final entry = <String, Object?>{
    'is_completed': completed,
    'type_tag': typeTag,
    'title': 'Example',
    'avid': 123,
    'bvid': 'BV1example',
    'page_data': {'cid': 456, 'part': 'Part 1'},
  };
  await File(
    path.join(root.path, 'entry.json'),
  ).writeAsString(jsonEncode(entry));
  final quality = Directory(path.join(root.path, typeTag));
  await quality.create(recursive: true);
  await File(path.join(quality.path, 'index.json')).writeAsString('{}');
  if (progressive) {
    await File(path.join(quality.path, '0.mp4')).writeAsBytes([1]);
  }
  if (dash || dashVideoOnly) {
    await File(path.join(quality.path, 'video.m4s')).writeAsBytes([1]);
  }
  if (dash) await File(path.join(quality.path, 'audio.m4s')).writeAsBytes([1]);
}
