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

The visible 64dp Row and the thumb's hidden 56dp material have separate roles,
as in the pinned upstream component. The hidden material has its own Capsule,
base blur/tint, press-driven lens(24p,24p), highlight and interactive glow. Its
capture includes translation but not the visible bar's press scale. Capturing
the actual expanded 64dp bar in r12 replaced this upstream material stage; the
source-only correction restores the independent hidden stage. See
docs/kyant-bottom-tabs-rendering-audit.md for coordinates, effects and Git diffs.

ButtonBackdrop applies the thumb's additional blur/tint to page + hidden material
BEFORE adding foreground glyphs and running the original thumb lens. It does not
create another capsule or another lens. Glyph capture contains no rectangular
InteractiveHighlight glow and retains the hidden Row's 56dp Capsule clip. At full
press the additional blur/tint disappear; hidden base material remains. Page
pixels fill outside that hidden Capsule as in upstream. Material and glyphs are
captured separately for independent extra blur, so this is an adaptation, not
byte-for-byte upstream. The original post-lens 3% pressed black film is not
restored: the user's button tint fades to zero. No 56/78 sampling compensation,
exported material, second 64dp material capsule or shader sign change is used.

Four independent appearance sliders retain existing track preferences and add
thumb clarity (default90%, old0.1 tint) and extra blur (default16dp, 0..32dp).
Automatic/white/black base-color choices remain independent; automatic preserves
earlier light/dark defaults. The original thumb lens/highlight/spring formulas
are retained. PixelCopy buffers remain fixed-size during press/partial scrolling;
no new capture loop or dependency/SDK upgrade. The source-only hidden-material
correction is uncompiled and has no native rendering/visual/performance
acceptance. The latest compiled APK remains r12; prior builds/tests do not
validate this correction.
