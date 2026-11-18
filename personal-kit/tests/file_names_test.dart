import 'dart:io';

import 'package:PiliPlus/private/cache_exporter/atomic_io.dart';
import 'package:PiliPlus/private/cache_exporter/file_names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('sanitizes Windows names and allocates without overwrite', () async {
    final directory = await Directory.systemTemp.createTemp('piliplus-names-');
    addTearDown(() => directory.delete(recursive: true));
    expect(ExportFileNames.sanitize('CON'), '_CON');
    expect(ExportFileNames.sanitize('bad<>:"/\\|?*.'), 'bad_________');
    await File(
      path.join(directory.path, 'Title.mp4'),
    ).writeAsString('existing');
    expect(
      ExportFileNames.chooseAvailableBase(directory.path, 'Title'),
      endsWith('Title (1)'),
    );
  });

  test('atomic text output refuses overwrite', () async {
    final directory = await Directory.systemTemp.createTemp('piliplus-atomic-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = path.join(directory.path, 'result.txt');
    await AtomicIo.writeText(destination, 'first');
    expect(
      () => AtomicIo.writeText(destination, 'second'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(destination).readAsString(), 'first');
  });
}
