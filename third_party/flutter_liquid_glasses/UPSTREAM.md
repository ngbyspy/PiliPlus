# Source and local changes

Source: https://github.com/losewayy/flutter_liquid_glasses
Commit: f67b4615fcd6a47d2ffde15246b8888f8383446e (0.1.3)
License: Apache-2.0; see LICENSE. The upstream project attributes its optics and spring recipes to Kyant0/AndroidLiquidGlass.

Vendored for a reproducible Android navigation experiment. Shader files and material implementation are unchanged.
Local segmented-control changes: custom item builder and theme colors; reselect callback; per-item accessibility actions; cancellation restores the controlled selection without navigation; the visual thumb ignores hit testing so destination semantics remain reachable.
