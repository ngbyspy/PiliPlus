// Export files can be large; asynchronous file-system calls keep the UI isolate
// responsive while copying and finalizing artifacts.
// ignore_for_file: avoid_slow_async_io

import 'dart:convert';
import 'dart:io';
import 'dart:math';

abstract final class AtomicIo {
  static final Random _random = Random.secure();

  static String temporaryPath(String finalPath) =>
      '$finalPath.piliplus-part-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  static Future<void> writeText(String finalPath, String content) async {
    final temporary = temporaryPath(finalPath);
    try {
      await File(temporary).writeAsString(content, encoding: utf8, flush: true);
      await complete(temporary, finalPath);
    } finally {
      await deleteIfPresent(temporary);
    }
  }

  static Future<void> copy(String sourcePath, String finalPath) async {
    final temporary = temporaryPath(finalPath);
    try {
      await File(sourcePath).copy(temporary);
      await complete(temporary, finalPath);
    } finally {
      await deleteIfPresent(temporary);
    }
  }

  static Future<void> complete(String temporaryPath, String finalPath) async {
    if (File(finalPath).existsSync()) {
      throw FileSystemException(
        'Refusing to overwrite an existing file',
        finalPath,
      );
    }
    await File(temporaryPath).rename(finalPath);
  }

  static Future<void> deleteIfPresent(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // A locked diagnostic temp file is deliberately left in place.
      }
    }
  }
}
