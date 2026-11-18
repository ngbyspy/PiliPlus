import 'package:path/path.dart' as path;

/// Release builds share the upstream profile. Only development is isolated.
String desktopSupportPath(String upstreamPath, {required bool development}) =>
    development ? path.join(upstreamPath, 'spy-dev') : upstreamPath;

String desktopImageCacheName({required bool development}) =>
    development ? 'PiliPlus-SPY-dev' : 'PiliPlus';
