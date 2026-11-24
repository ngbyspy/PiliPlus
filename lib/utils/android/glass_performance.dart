import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_liquid_glasses/flutter_liquid_glasses.dart'
    show GlassDebugProbe;
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';

/// Bounded, opt-in FrameTiming collection over the Profile VM service.
/// No periodic logging, screenshots or account/content data are collected.
/// Release tree-shakes the registration and exposes no diagnostic endpoint.
abstract final class GlassPerformance {
  static final _frames = <ui.FrameTiming>[];
  static bool _recording = false;
  static bool _truncated = false;

  static void _collect(List<ui.FrameTiming> frames) {
    final room = 12000 - _frames.length;
    _frames.addAll(frames.take(room));
    if (frames.length > room) _truncated = true;
  }

  static Map<String, Object> _durations(Iterable<int> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return {'count': 0};
    double percentile(double p) =>
        sorted[((sorted.length - 1) * p).ceil()] / 1000;
    return {
      'count': sorted.length,
      'p50Ms': percentile(.5),
      'p95Ms': percentile(.95),
      'p99Ms': percentile(.99),
      'maxMs': sorted.last / 1000,
      'over8_33ms': sorted.where((us) => us > 8333).length,
      'over16_67ms': sorted.where((us) => us > 16667).length,
    };
  }

  static void install() {
    if (!kProfileMode) return;
    developer.registerExtension('ext.spy.glass', (method, params) async {
      final action = params['action'] ?? 'status';
      switch (action) {
        case 'begin':
          if (_recording) {
            SchedulerBinding.instance.removeTimingsCallback(_collect);
          }
          _frames.clear();
          _truncated = false;
          SchedulerBinding.instance.addTimingsCallback(_collect);
          _recording = true;
        case 'end':
          // Timings are batched by the engine; allow the last batch to arrive.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          SchedulerBinding.instance.removeTimingsCallback(_collect);
          _recording = false;
        case 'set':
          final enabled = params['enabled'] == 'true';
          if (!Get.isRegistered<MainController>()) {
            return developer.ServiceExtensionResponse.error(
              developer.ServiceExtensionResponse.extensionError,
              'Main navigation is not ready',
            );
          }
          await GStorage.setting.put(
            SettingBoxKey.androidLiquidGlassNavigation,
            enabled,
          );
          Get.find<MainController>().androidLiquidGlassNavigation.value =
              enabled;
        case 'probe':
          GlassDebugProbe.mode.value =
              (int.tryParse(params['mode'] ?? '0') ?? 0).clamp(0, 8);
        case 'status':
          break;
        default:
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.invalidParams,
            'Unknown action',
          );
      }
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'type': 'GlassPerformance',
          'mode': 'profile',
          'probeMode': GlassDebugProbe.mode.value,
          'loadedShaders': GlassDebugProbe.loaded,
          'failedShaders': GlassDebugProbe.failed,
          'shaderSupported': ui.ImageFilter.isShaderFilterSupported,
          'accessibleNavigation': ui
              .PlatformDispatcher
              .instance
              .accessibilityFeatures
              .accessibleNavigation,
          'highContrast':
              ui.PlatformDispatcher.instance.accessibilityFeatures.highContrast,
          'disableAnimations': ui
              .PlatformDispatcher
              .instance
              .accessibilityFeatures
              .disableAnimations,
          'enabled': Pref.androidLiquidGlassNavigation,
          'recording': _recording,
          'truncated': _truncated,
          if (action == 'end') ...{
            'ui': _durations(
              _frames.map((frame) => frame.buildDuration.inMicroseconds),
            ),
            'raster': _durations(
              _frames.map((frame) => frame.rasterDuration.inMicroseconds),
            ),
            'totalSpan': _durations(
              _frames.map((frame) => frame.totalSpan.inMicroseconds),
            ),
          },
        }),
      );
    });
  }
}
