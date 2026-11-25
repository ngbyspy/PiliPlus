# Source and local changes

Source: https://github.com/losewayy/flutter_liquid_glasses
Commit: f67b4615fcd6a47d2ffde15246b8888f8383446e (0.1.3)
License: Apache-2.0; see LICENSE. The upstream project attributes its optics and spring recipes to Kyant0/AndroidLiquidGlass.

Vendored for a reproducible Android navigation experiment. Material starts from that exact source. During the Android investigation, Profile-only shader probes were added to distinguish backdrop input, coordinate mapping, and foreground compositing. Negative glow alpha is reserved for those probes; ordinary rendering keeps the original nonnegative range.
Local segmented-control changes: custom item builder and theme colors; reselect callback; per-item accessibility actions; cancellation restores the controlled selection without navigation; the visual thumb ignores hit testing so destination semantics remain reachable.

Neutral optics (zero blur/refraction and neutral color controls) paint the surface tint without a backdrop filter. This avoids the idle thumb copy; press/drag still uses the original refraction shader and the track stays refractive.
