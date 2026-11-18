import 'package:PiliPlus/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:PiliPlus/private/cache_exporter/danmaku_converter.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('escapes XML and ASS content', () {
    final items = [
      DanmakuElem(
        id: Int64(1),
        progress: 1250,
        mode: 1,
        fontsize: 25,
        color: 0xff0000,
        midHash: 'hash&',
        content: r'<hello>{world}\',
        ctime: Int64(2),
      ),
    ];
    const converter = DanmakuConverter();
    final xml = converter.toXml(items, cid: 99);
    final ass = converter.toAss(items);
    expect(xml, contains('&lt;hello&gt;'));
    expect(xml, contains('hash&amp;'));
    expect(ass, contains(r'\{world\}'));
    expect(ass, contains(r'\\'));
  });
}
