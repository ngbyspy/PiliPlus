import 'dart:io';

import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';

final class DanmakuConverter {
  const DanmakuConverter();

  Future<List<DanmakuElem>> read(String filePath) async {
    try {
      return DmSegMobileReply.fromBuffer(
          await File(filePath).readAsBytes(),
        ).elems.toList()
        ..sort((left, right) => left.progress.compareTo(right.progress));
    } catch (error) {
      throw FormatException('danmaku.pb is invalid or incompatible: $error');
    }
  }

  String toXml(List<DanmakuElem> entries, {int cid = 0}) {
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<i>')
      ..writeln('<chatserver>api.bilibili.com</chatserver>')
      ..writeln('<chatid>$cid</chatid>')
      ..writeln('<mission>0</mission>')
      ..writeln('<maxlimit>${entries.length}</maxlimit>')
      ..writeln('<state>0</state>')
      ..writeln('<real_name>0</real_name>')
      ..writeln('<source>k-v</source>');
    for (final item in entries) {
      final seconds = (item.progress / 1000).toStringAsFixed(3);
      buffer.writeln(
        '<d p="$seconds,${item.mode},${item.fontsize},${item.color},${item.ctime},${item.pool},${_xml(item.midHash)},${item.id}">${_xml(item.content)}</d>',
      );
    }
    return (buffer..writeln('</i>')).toString();
  }

  String toAss(
    List<DanmakuElem> entries, {
    int width = 1920,
    int height = 1080,
    int laneHeight = 44,
  }) {
    final buffer = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('ScriptType: v4.00+')
      ..writeln('PlayResX: $width')
      ..writeln('PlayResY: $height')
      ..writeln('WrapStyle: 2')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln()
      ..writeln('[V4+ Styles]')
      ..writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding',
      )
      ..writeln(
        'Style: Danmaku,Microsoft YaHei UI,36,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,7,0,0,0,1',
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
      );
    final laneCount = ((height * 0.8) / laneHeight).floor().clamp(1, 1000);
    var scrollingLane = 0;
    var topLane = 0;
    var bottomLane = 0;
    for (final item in entries) {
      final start = Duration(
        milliseconds: item.progress.clamp(0, 1 << 31).toInt(),
      );
      final end = start + const Duration(seconds: 8);
      final color = _assColor(item.color);
      final text = _ass(item.content);
      late final String position;
      switch (item.mode) {
        case 4:
          final y = height - 50 - (bottomLane++ % laneCount) * laneHeight;
          position =
              r'{\an2\pos('
              '${width ~/ 2},$y)'
              '\\c$color}';
          break;
        case 5:
          final y = 20 + (topLane++ % laneCount) * laneHeight;
          position =
              r'{\an8\pos('
              '${width ~/ 2},$y)'
              '\\c$color}';
          break;
        default:
          final y = 20 + (scrollingLane++ % laneCount) * laneHeight;
          position =
              r'{\move('
              '${width + 20},$y,-20,$y'
              '\\c$color}';
          break;
      }
      buffer.writeln(
        'Dialogue: 0,${_time(start)},${_time(end)},Danmaku,,0,0,0,,$position$text',
      );
    }
    return buffer.toString();
  }

  static String _time(Duration value) {
    final centiseconds = value.inMilliseconds ~/ 10;
    final hours = centiseconds ~/ 360000;
    final minutes = (centiseconds ~/ 6000) % 60;
    final seconds = (centiseconds ~/ 100) % 60;
    final fraction = centiseconds % 100;
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${fraction.toString().padLeft(2, '0')}';
  }

  static String _assColor(int rgb) {
    final red = (rgb >> 16) & 0xff;
    final green = (rgb >> 8) & 0xff;
    final blue = rgb & 0xff;
    return '&H00${blue.toRadixString(16).padLeft(2, '0')}${green.toRadixString(16).padLeft(2, '0')}${red.toRadixString(16).padLeft(2, '0')}&'
        .toUpperCase();
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _ass(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('\r\n', r'\N')
      .replaceAll('\n', r'\N')
      .replaceAll('\r', r'\N');
}
