# Kyant native navigation experiment

Catalog component source: https://github.com/Kyant0/AndroidLiquidGlass
Commit: eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5 (kmp).
Library dependency: io.github.kyant0:backdrop:2.0.1, resolved through Maven.
License: Apache-2.0, included in LICENSE.

The catalog components and gesture/animation helpers are copied into
android/app/src/main/kotlin/com/kyant/backdrop/catalog. Android specialization
removes expect/actual, uses a monotonic velocity clock, and exposes track tint
opacity/theme inputs. The Compose optics, layered tab content, highlights and
spring recipes remain native. PiliPlus supplies its own icons, labels, badges,
selection bridge and lifecycle ownership.

NativeKyantNavigation captures only the Flutter SurfaceView with bounded,
triple-buffered PixelCopy. It never captures the composed window, transmits
bitmap bytes over a channel, writes captured pixels to disk or requests screen
recording permission. Capture is coalesced after actual Flutter scene updates;
native press animation does not drive extra Flutter frames. This experimental
copy path has a synchronization/copy cost and is not a zero-copy implementation.

The sibling overlay is disabled behind other routes/dialogs, on pause, at full
scroll-hide and on disposal. Unsupported systems/builds or repeated capture
failures return to the existing Flutter bar. Only acceptance builds enable the
native host resource flag. Formal spy/main is unchanged.
