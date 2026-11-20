#import "AudioMixPlugin.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <stdbool.h>
#import <stdatomic.h>

static atomic_bool piliPlusMixWithOthers = false;

// The pinned mpv 0.39 AudioUnit output and flutter_volume_controller both call
// setCategory:error:, which clears category options. A later Dart configure()
// cannot undo the interruption caused by their immediate setActive:YES call.
// Intercept only that legacy setter, only for playback, and only while the
// user has enabled mixing. Explicit category/options setters remain untouched.
@interface AVAudioSession (PiliPlusAudioMix)
- (BOOL)piliPlus_setCategory:(AVAudioSessionCategory)category
                      error:(NSError **)outError;
@end

@implementation AVAudioSession (PiliPlusAudioMix)
- (BOOL)piliPlus_setCategory:(AVAudioSessionCategory)category
                      error:(NSError **)outError {
  if (atomic_load_explicit(&piliPlusMixWithOthers, memory_order_relaxed) &&
      [category isEqualToString:AVAudioSessionCategoryPlayback]) {
    return [self setCategory:category
                withOptions:AVAudioSessionCategoryOptionMixWithOthers
                      error:outError];
  }
  return [self piliPlus_setCategory:category error:outError];
}
@end

@implementation AudioMixPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method original = class_getInstanceMethod(
        AVAudioSession.class, @selector(setCategory:error:));
    Method replacement = class_getInstanceMethod(
        AVAudioSession.class, @selector(piliPlus_setCategory:error:));
    method_exchangeImplementations(original, replacement);
  });
  FlutterMethodChannel *channel = [FlutterMethodChannel
      methodChannelWithName:@"com.example.piliplus/audio_mix"
            binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:[[AudioMixPlugin alloc] init]
                          channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"setMixWithOthers"] &&
      [call.arguments isKindOfClass:NSNumber.class]) {
    atomic_store_explicit(&piliPlusMixWithOthers, [call.arguments boolValue],
                          memory_order_relaxed);
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}
@end
