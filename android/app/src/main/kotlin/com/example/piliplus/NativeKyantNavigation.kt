package com.example.piliplus

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryController
import androidx.savedstate.SavedStateRegistryOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.kyant.backdrop.backdrops.layerBackdrop
import com.kyant.backdrop.backdrops.rememberLayerBackdrop
import com.kyant.backdrop.catalog.components.LiquidBottomTab
import com.kyant.backdrop.catalog.components.LiquidBottomTabs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

// Experimental native sibling overlay. PixelCopy reads only Flutter's own
// SurfaceView, never the composed window, so the glass cannot capture itself.
// Buffers are RAM-only, triple-buffered and copied only after actual Dart frames.
@RequiresApi(33)
class NativeKyantNavigation(private val activity: Activity, engine: FlutterEngine) {
    companion object {
        const val CHANNEL = "com.ngbyspy.piliplus/kyant_navigation"
        const val FRAMES = CHANNEL + "/frame"
        private var current: NativeKyantNavigation? = null
    }

    private data class Item(val id: String, val label: String, val badge: String?)
    private data class Config(
        val owner: Long, val left: Float, val top: Float, val width: Float,
        val height: Float, val dpr: Float, val selected: Int, val items: List<Item>,
        val dark: Boolean, val tint: Int, val foreground: Int, val opacity: Float,
        val fontScale: Float, val visible: Boolean
    )

    private class Owner : LifecycleOwner, SavedStateRegistryOwner {
        private val registry = LifecycleRegistry(this)
        private val state = SavedStateRegistryController.create(this)
        override val lifecycle: Lifecycle get() = registry
        override val savedStateRegistry: SavedStateRegistry get() = state.savedStateRegistry
        init {
            state.performAttach()
            state.performRestore(null)
            registry.currentState = Lifecycle.State.RESUMED
        }
        fun destroy() { registry.currentState = Lifecycle.State.DESTROYED }
    }

    private val messenger = engine.dartExecutor.binaryMessenger
    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private val owner = Owner()
    private var config by mutableStateOf<Config?>(null)
    private var image by mutableStateOf<ImageBitmap?>(null, neverEqualPolicy())
    private var root: FrameLayout? = null
    private var compose: ComposeView? = null
    private var crop = Rect()
    private var barX by mutableFloatStateOf(0f)
    private var barY by mutableFloatStateOf(0f)
    private var buffers = emptyList<Bitmap>()
    private var bufferIndex = 0
    private var dirty = false
    private var scheduled = false
    private var copying = false
    private var generation = 0
    private var errors = 0
    private var resumed = true
    private var disposed = false

    init {
        current?.dispose()
        current = this
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(true)
                "update" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) result.error("arguments", "Missing configuration", null)
                    else {
                        update(args)
                        result.success(null)
                    }
                }
                "hide" -> {
                    if ((call.argument<Number>("owner")?.toLong()) == config?.owner) hide()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        messenger.setMessageHandler(FRAMES) { _, reply ->
            invalidate()
            reply.reply(null)
        }
    }

    private fun update(args: Map<*, *>) {
        fun n(key: String, default: Float = 0f) = (args[key] as? Number)?.toFloat() ?: default
        val items = (args["items"] as? List<*>)?.mapNotNull {
            val item = it as? Map<*, *> ?: return@mapNotNull null
            Item(item["id"] as? String ?: return@mapNotNull null,
                item["label"] as? String ?: "", item["badge"] as? String)
        } ?: emptyList()
        if (items.size < 2) { hide(); return }
        val dpr = n("dpr", 1f)
        val next = Config(
            (args["owner"] as Number).toLong(), n("left") * dpr, n("top") * dpr,
            n("width") * dpr, n("height") * dpr, dpr,
            (args["selected"] as? Number)?.toInt()?.coerceIn(0, items.lastIndex) ?: 0,
            items, args["dark"] == true, (args["tint"] as Number).toInt(),
            (args["foreground"] as Number).toInt(), n("opacity", .4f).coerceIn(0f, 1f),
            n("fontScale", 1f), args["visible"] == true
        )
        if (next.width <= 0 || next.height <= 0) { hide(); return }
        if (config?.owner != next.owner) { generation++; image = null; errors = 0 }
        config = next
        if (!next.visible) hide() else invalidate()
    }

    private fun sourceView(view: View): SurfaceView? {
        if (view is SurfaceView && view.javaClass.name.startsWith("io.flutter.embedding"))
            return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            sourceView(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun createOverlay(): FrameLayout {
        root?.let { return it }
        val frame = object : FrameLayout(activity) {
            override fun dispatchTouchEvent(event: MotionEvent): Boolean {
                val c = config ?: return false
                if (event.actionMasked == MotionEvent.ACTION_DOWN &&
                    (event.x < barX || event.x > barX + c.width ||
                     event.y < barY || event.y > barY + c.height)) return false
                return super.dispatchTouchEvent(event)
            }
        }
        frame.clipChildren = true
        frame.setViewTreeLifecycleOwner(owner)
        frame.setViewTreeSavedStateRegistryOwner(owner)
        val view = ComposeView(activity).apply {
            setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnDetachedFromWindow)
            setContent { NativeBar() }
        }
        frame.addView(view, FrameLayout.LayoutParams(-1, -1))
        frame.visibility = View.INVISIBLE
        (activity.findViewById<ViewGroup>(android.R.id.content)).addView(frame)
        compose = view
        root = frame
        return frame
    }

    private fun invalidate() {
        val c = config ?: return
        if (disposed || !resumed || !c.visible) return
        dirty = true
        if (scheduled || copying) return
        scheduled = true
        activity.window.decorView.postOnAnimation {
            scheduled = false
            if (!disposed && resumed && dirty && config?.visible == true) capture()
        }
    }

    private fun capture() {
        val c = config ?: return
        val source = sourceView(activity.window.decorView)
        if (source == null || !source.holder.surface.isValid) {
            fail("Flutter surface is unavailable")
            return
        }
        val margin = ceil(c.height * .45f).toInt()
        if (c.top >= source.height || c.top + c.height <= 0 ||
            c.left >= source.width || c.left + c.width <= 0) {
            root?.visibility = View.GONE
            dirty = false
            return
        }
        // Keep buffer dimensions constant while the bar slides off screen.
        // Clipping the source size per pixel would allocate during scrolling.
        val w = (ceil(c.width).toInt() + margin * 2).coerceAtMost(source.width)
        val h = (ceil(c.height).toInt() + margin * 2).coerceAtMost(source.height)
        val x = (floor(c.left).toInt() - margin).coerceIn(0, source.width - w)
        val y = (floor(c.top).toInt() - margin).coerceIn(0, source.height - h)
        val rect = Rect(x, y, x + w, y + h)
        val frame = createOverlay()
        val sourceLocation = IntArray(2).also { source.getLocationInWindow(it) }
        val parentLocation = IntArray(2).also { (frame.parent as View).getLocationInWindow(it) }
        val layout = FrameLayout.LayoutParams(rect.width(), rect.height())
        layout.leftMargin = rect.left + sourceLocation[0] - parentLocation[0]
        layout.topMargin = rect.top + sourceLocation[1] - parentLocation[1]
        if (frame.layoutParams != null) {
            val old = frame.layoutParams as FrameLayout.LayoutParams
            if (old.width != layout.width || old.height != layout.height ||
                old.leftMargin != layout.leftMargin || old.topMargin != layout.topMargin)
                frame.layoutParams = layout
        }
        barX = c.left - rect.left
        barY = c.top - rect.top
        if (crop.width() != rect.width() || crop.height() != rect.height()) {
            generation++
            image = null
            buffers = List(3) { Bitmap.createBitmap(rect.width(), rect.height(), Bitmap.Config.ARGB_8888) }
            bufferIndex = 0
        }
        crop = rect
        val bitmap = buffers[bufferIndex]
        bufferIndex = (bufferIndex + 1) % buffers.size
        val captureGeneration = generation
        copying = true
        dirty = false
        try {
            PixelCopy.request(source, rect, bitmap, { status ->
                copying = false
                if (!disposed && captureGeneration == generation && config?.visible == true && resumed) {
                    if (status == PixelCopy.SUCCESS) {
                        errors = 0
                        image = bitmap.asImageBitmap()
                        frame.visibility = View.VISIBLE
                    } else fail("PixelCopy status " + status)
                }
                if (dirty) invalidate()
            }, handler)
        } catch (_: RuntimeException) {
            copying = false
            fail("PixelCopy request failed")
        }
    }

    private fun fail(reason: String) {
        dirty = false
        if (++errors >= 3) {
            val id = config?.owner
            hide()
            channel.invokeMethod("failed", mapOf("owner" to id, "reason" to reason))
        } else {
            // A first request can precede the first submitted Flutter buffer.
            // Retry for a bounded number of vsyncs, never an idle polling loop.
            dirty = true
            invalidate()
        }
    }

    private fun hide() {
        config = config?.copy(visible = false)
        generation++
        dirty = false
        root?.visibility = View.GONE
        image = null
        buffers = emptyList()
        crop = Rect()
    }

    fun pause() { resumed = false; generation++; root?.visibility = View.GONE }
    fun resume() { resumed = true; invalidate() }

    fun dispose() {
        if (disposed) return
        disposed = true
        generation++
        root?.let { (it.parent as? ViewGroup)?.removeView(it) }
        compose?.disposeComposition()
        owner.destroy()
        buffers = emptyList()
        image = null
        config = null
        if (current === this) {
            messenger.setMessageHandler(FRAMES, null)
            channel.setMethodCallHandler(null)
            current = null
        }
    }

    @Composable
    private fun NativeBar() {
        val c = config ?: return
        val bitmap = image
        val backdrop = rememberLayerBackdrop()
        val selected = rememberUpdatedState(c.selected)
        val selectedProvider = remember { { selected.value } }
        val density = c.height / 64f
        CompositionLocalProvider(LocalDensity provides Density(density, c.fontScale)) {
            Box(Modifier.fillMaxSize()) {
                Canvas(Modifier.fillMaxSize().alpha(0f).layerBackdrop(backdrop)) {
                    bitmap?.let { drawImage(it) }
                }
                LiquidBottomTabs(
                    selectedTabIndex = selectedProvider,
                    onTabSelected = { emitSelection(it) },
                    backdrop = backdrop,
                    tabsCount = c.items.size,
                    modifier = Modifier.offset { IntOffset(barX.roundToInt(), barY.roundToInt()) }
                        .size((c.width / density).dp, 64.dp),
                    surfaceOpacity = c.opacity, darkTheme = c.dark, accent = Color(c.tint)
                ) {
                    c.items.forEachIndexed { index, item ->
                        LiquidBottomTab(onClick = { emitSelection(index) }) {
                            Box {
                                NavIcon(item.id, Color(c.foreground))
                                item.badge?.let { badge ->
                                    BasicText(if (badge.isEmpty()) "•" else badge,
                                        modifier = Modifier.offset(17.dp, (-5).dp),
                                        style = TextStyle(color = Color(0xFFFF4A6A), fontSize = 10.sp))
                                }
                            }
                            BasicText(item.label, style = TextStyle(
                                color = Color(c.foreground), fontSize = 11.sp))
                        }
                    }
                }
            }
        }
    }

    private fun emitSelection(index: Int) {
        val c = config ?: return
        if (!c.visible || index !in c.items.indices) return
        channel.invokeMethod("selected", mapOf("owner" to c.owner, "id" to c.items[index].id))
    }

    @Composable
    private fun NavIcon(id: String, color: Color) {
        Canvas(Modifier.size(23.dp)) {
            val unit = size.width / 24f
            val path = Path()
            when (id) {
                "home" -> {
                    path.moveTo(3 * unit, 10 * unit); path.lineTo(12 * unit, 3 * unit)
                    path.lineTo(21 * unit, 10 * unit); path.lineTo(21 * unit, 21 * unit)
                    path.lineTo(15 * unit, 21 * unit); path.lineTo(15 * unit, 14 * unit)
                    path.lineTo(9 * unit, 14 * unit); path.lineTo(9 * unit, 21 * unit)
                    path.lineTo(3 * unit, 21 * unit); path.close()
                    drawPath(path, color, style = Stroke(1.8f * unit))
                }
                "mine" -> {
                    drawCircle(color, 4 * unit, Offset(12 * unit, 7 * unit), style = Stroke(1.8f * unit))
                    drawArc(color, 180f, 180f, false, Offset(4 * unit, 13 * unit),
                        androidx.compose.ui.geometry.Size(16 * unit, 15 * unit), style = Stroke(1.8f * unit))
                }
                else -> {
                    drawRoundRect(color, Offset(3 * unit, 5 * unit),
                        androidx.compose.ui.geometry.Size(18 * unit, 14 * unit),
                        androidx.compose.ui.geometry.CornerRadius(3 * unit), style = Stroke(1.8f * unit))
                    path.moveTo(10 * unit, 9 * unit); path.lineTo(15 * unit, 12 * unit)
                    path.lineTo(10 * unit, 15 * unit); path.close(); drawPath(path, color)
                }
            }
        }
    }
}

