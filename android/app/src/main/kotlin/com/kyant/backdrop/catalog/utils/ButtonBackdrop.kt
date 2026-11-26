// PiliPlus integration of Kyant Backdrop's public composition API.
// No extra capsule or lens: material -> sharp foreground -> upstream thumb lens.
package com.kyant.backdrop.catalog.utils

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.ceil
import com.kyant.backdrop.Backdrop

@Composable
fun rememberButtonBackdrop(
    page: Backdrop,
    material: Backdrop,
    foreground: Backdrop,
    materialScale: () -> Float,
    blurRadius: () -> Float,
    tint: () -> Color
): Backdrop {
    val blur = rememberUpdatedState(blurRadius)
    val color = rememberUpdatedState(tint)
    val materialZoom = rememberUpdatedState(materialScale)
    val layer = rememberGraphicsLayer()
    return remember(page, material, foreground, layer) {
        object : Backdrop {
            override val isCoordinatesDependent: Boolean = true

            override fun DrawScope.drawBackdrop(
                density: Density,
                coordinates: LayoutCoordinates?,
                layerBlock: (GraphicsLayerScope.() -> Unit)?
            ) {
                // Keep an opaque page under the minified material. Scaling the
                // whole scene would expose transparent capture edges and let
                // the unrefracted visible bar bleed through again.
                val drawScene: DrawScope.() -> Unit = {
                    with(page) { drawBackdrop(density, coordinates, layerBlock) }
                    val factor = materialZoom.value().coerceIn(0.01f, 1f)
                    // Use the actual thumb bounds, not the padded blur buffer.
                    val pivot = coordinates?.size?.let {
                        Offset(it.width / 2f, it.height / 2f)
                    } ?: center
                    withTransform({ scale(factor, factor, pivot) }) {
                        with(material) { drawBackdrop(density, coordinates, layerBlock) }
                    }
                }
                val radius = with(density) { blur.value().dp.toPx() }
                if (radius > 0f) {
                    // Record neighboring scene pixels too. This is a rectangular
                    // working buffer, NOT a second shaped/drawn glass surface.
                    val padding = ceil(radius).toInt()
                    layer.renderEffect = BlurEffect(radius, radius, TileMode.Clamp)
                    layer.topLeft = IntOffset(-padding, -padding)
                    layer.record(density, layoutDirection, IntSize(
                        ceil(size.width).toInt() + padding * 2,
                        ceil(size.height).toInt() + padding * 2
                    )) {
                        translate(padding.toFloat(), padding.toFloat()) {
                            drawScene()
                        }
                    }
                    drawLayer(layer)
                } else {
                    // Fully pressed: no intermediate filter, sample the same
                    // page + visible bar directly. Never a transparent cutout.
                    drawScene()
                }
                drawRect(color.value())
                // The foreground contains glyphs ONLY, no rectangular glow.
                // It bypasses the extra material blur/tint, as upstream does.
                with(foreground) { drawBackdrop(density, coordinates, layerBlock) }
            }
        }
    }
}
