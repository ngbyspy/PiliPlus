import 'dart:io';

import 'package:path/path.dart' as path;

abstract final class ExportFileNames {
  static final RegExp _invalid = RegExp(r'[<>:"/\\|?*\x00-\x1f]');
  static final RegExp _trailing = RegExp(r'[ .]+$');
  static const Set<String> _reserved = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  static String sanitize(String input, {int maxLength = 120}) {
    var value = input
        .replaceAll(_invalid, '_')
        .replaceAll(_trailing, '')
        .trim();
    if (value.isEmpty) value = 'PiliPlus export';
    if (_reserved.contains(value.toUpperCase())) value = '_$value';
    if (value.length > maxLength) {
      value = value.substring(0, maxLength).replaceAll(_trailing, '');
    }
    return value;
  }

  static String chooseAvailableBase(String directory, String title) {
    final safe = sanitize(title);
    for (var index = 0; index < 10000; index++) {
      final suffix = index == 0 ? '' : ' ($index)';
      final candidate = path.join(directory, '$safe$suffix');
      final baseName = path.basename(candidate).toLowerCase();
      final collision = Directory(directory).listSync().whereType<File>().any((
        item,
      ) {
        final name = path.basename(item.path).toLowerCase();
        return name == baseName || name.startsWith('$baseName.');
      });
      if (!collision) return candidate;
    }
    throw const FileSystemException(
      'Unable to allocate a non-conflicting export filename',
    );
  }
}
