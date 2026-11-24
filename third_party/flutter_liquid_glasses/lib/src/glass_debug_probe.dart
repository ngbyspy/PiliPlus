import 'package:flutter/foundation.dart';

/// Profile-only inspection of backdrop input and coordinate spaces.
abstract final class GlassDebugProbe {
  static final mode = ValueNotifier<int>(0);
  static int loaded = 0;
  static int failed = 0;
}
