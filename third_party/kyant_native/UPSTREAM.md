# Kyant native navigation experiment

Catalog component source: https://github.com/Kyant0/AndroidLiquidGlass
Commit: eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5 (kmp).
Library dependency: io.github.kyant0:backdrop:2.0.1, resolved through Maven.
License: Apache-2.0, included in LICENSE.

The catalog components and gesture/animation helpers are copied into
android/app/src/main/kotlin/com/kyant/backdrop/catalog. Android specialization
removes expect/actual, uses a monotonic velocity clock, and exposes track tint
opacity/theme and background blur inputs. Blur defaults to the original 8dp;
the 0..16dp control changes both backdrop layers, skipping blur at zero while
retaining lens/highlight effects. The Compose optics, layered tab content, highlights and
spring recipes remain native. PiliPlus supplies its own icons, labels, badges,
selection bridge and lifecycle ownership.
External selection acknowledgement is deduplicated, explicit reselect taps
retain refresh behavior, and cancellation restores selection without navigation.
Native composition is keyed by dimensions/order to reset drag geometry on resize.

NativeKyantNavigation captures only the Flutter SurfaceView with bounded,
triple-buffered PixelCopy. It never captures the composed window, transmits
bitmap bytes over a channel, writes captured pixels to disk or requests screen
recording permission. Capture is coalesced after actual Flutter scene updates;
native press animation does not drive extra Flutter frames. This experimental
copy path has a synchronization/copy cost and is not a zero-copy implementation.

The sibling overlay is disabled behind other routes/dialogs, on pause, at full
scroll-hide and on disposal. Unsupported systems/builds or repeated capture
failures return to the existing Flutter bar. The user accepted the Release dev
implementation on 2026-11-26 and authorized formal-source promotion and Android
packaging, including an independent blur control. The opt-in preference still
defaults off. Native host resources are enabled in formal and acceptance builds;
SDK support, visibility and the user's preference continue to gate actual use.

2026-11-27: restored the complete r8 optical component/controls exactly. Only
Android foreground recovery from r9 is retained: focus/lifecycle/display/Surface
readiness, transient PixelCopy fallback, stale-result rejection, clean-scene
acknowledgement and one foreground scene. No r9 PressBackdrop, later button
material/colour controls, alternate layer graph, clipping or scale compensation
is active. N02 stays removed by the user's explicit choice. This is source-only;
no compilation, package, device operation or new visual acceptance is claimed.


2026-11-27 independent-control experiment (spy/dev only): expose the existing
visible bar and hidden tab material's blur/opacity separately. Blur calls the
library blur() directly (0..16dp); clarity changes existing tint alpha and is
not one of the demo's five lens/shape parameters. Existing tint already uses
#FAFAFA / #121212 and an inverse-theme 10% idle / black 3% pressed button shade.
Automatic preserves these colours/alphas; White/Black recolour those existing
surfaces independently. Selection shades retain their original strengths, even
at 100% material clarity. No layer, clipping, press transform, lens/highlight,
refraction/dispersion parameter or surface/lifecycle logic is reconstructed.
Corner-radius customization was explicitly declined. The graph stays identical
to accepted r13, whose source and APK remain the rollback baseline.
