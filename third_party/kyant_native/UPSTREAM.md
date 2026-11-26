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

The selected thumb samples a complete scene: raw Flutter page underneath the
actual rendered track, then sharp accent glyphs. Like upstream's combined
backdrop, the page fills pixels outside the captured track. A transparent
capsule cutout would leave the unrefracted track visible underneath the lens,
producing multiple silhouettes. The track capture sits outside its translation
and press-scale modifiers, so it includes exactly the visible shape, transforms,
surface color and interactive highlight, rather than an untransformed export.

ButtonBackdrop applies the thumb's additional blur/tint to that complete scene
BEFORE adding foreground glyphs and running the original thumb lens. It does not
create another capsule or another lens. Glyph capture contains no rectangular
InteractiveHighlight glow. At full press the additional blur/tint disappear and
the complete scene is sampled directly; track material values remain unchanged.
The old material export, second full-width capsule and exported-clip patch are
removed after user feedback exposed their incorrect composition.

Four independent appearance sliders retain existing track preferences and add
thumb clarity (default90%, old0.1 tint) and extra blur (default16dp, 0..32dp).
Automatic/white/black base-color choices remain independent; automatic preserves
earlier light/dark defaults. The original thumb lens/highlight/spring formulas
are retained. PixelCopy buffers remain fixed-size during press/partial scrolling;
no new capture loop or dependency/SDK upgrade. The r12 repair awaits user visual
acceptance; compile/tests are not a native optics/performance pass.
