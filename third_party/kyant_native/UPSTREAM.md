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

Foreground recovery observes Android focus, Flutter display and SurfaceHolder
readiness. Missing/new surface buffers are transient: the original Flutter bar
is shown during bounded warm-up, and a scene-epoch acknowledgement prevents
capturing that fallback during handover. Late PixelCopy callbacks are discarded.
No polling runs in the background; after warm-up only actual scene/surface events
retry, with throttling. Compose lifecycle pauses with the activity/focus.

The selected thumb always samples the finished track material. Its own extra
blur/tint is exported separately, then combined with sharp foreground glyphs
before the original native lens/highlight animation. Pressing reduces only the
thumb's extra blur/tint to zero; it exposes the track, never the raw page.
Track blur/tint are unchanged by pressing. Four independent appearance sliders
retain existing track preferences, add thumb clarity (default90%, old0.1 tint)
and additional blur (default16dp, 0..32dp). The stronger thumb blur samples a
bounded crop with padding derived from the configured combined blur, without
resizing buffers during native press animation or partial scrolling.

Bar and thumb now have independent automatic/white/black base-color choices;
automatic preserves the earlier light/dark defaults. Opacity remains controlled
by each clarity preference and only the thumb's own tint fades on press.
The two exported material GraphicsLayers use the exact Capsule outline with
clip=true. Library 2.0.1 clips the displayed node but records an unclipped
rectangle for exportedBackdrop; sampling it through the next lens can expose
invisible corner tint. The local modifier caches the shape path by geometry
without changing the pinned library, shader or spring formulas. Native visual
acceptance of this repair is pending the user's own installation.
