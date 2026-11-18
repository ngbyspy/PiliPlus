import 'package:PiliPlus/utils/runtime_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test('release uses the exact upstream profile and cache names', () {
    final upstream = path.join('profiles', 'com.example', 'piliplus');
    expect(desktopSupportPath(upstream, development: false), upstream);
    expect(desktopImageCacheName(development: false), 'PiliPlus');
  });

  test('development cannot open the release profile', () {
    final upstream = path.join('profiles', 'com.example', 'piliplus');
    expect(
      desktopSupportPath(upstream, development: true),
      path.join(upstream, 'spy-dev'),
    );
    expect(desktopImageCacheName(development: true), isNot('PiliPlus'));
  });
}
