package com.example.piliplus

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var nativeKyant: NativeKyantNavigation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= 33 && resources.getBoolean(R.bool.spy_native_kyant)) {
            nativeKyant = NativeKyantNavigation(this, flutterEngine)
        } else {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
                "com.ngbyspy.piliplus/kyant_navigation").setMethodCallHandler { call, result ->
                if (call.method == "isSupported") result.success(false)
                else result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.piliplus/theme")
            .setMethodCallHandler { call, result ->
                if (call.method != "getSystemColorRoles") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 34) {
                    result.success(null)
                } else {
                    // Android 14 exposes the resolved Material roles used by
                    // Weeko, including OEM/user contrast adjustments.
                    val roles = listOf(
                        "primary", "on_primary", "primary_container", "on_primary_container",
                        "secondary", "on_secondary", "secondary_container", "on_secondary_container",
                        "tertiary", "on_tertiary", "tertiary_container", "on_tertiary_container",
                        "surface", "surface_dim", "surface_bright", "surface_container_lowest",
                        "surface_container_low", "surface_container", "surface_container_high",
                        "surface_container_highest", "on_surface", "on_surface_variant",
                        "outline", "outline_variant",
                    )
                    val colors = runCatching {
                        listOf("light", "dark").associateWith { mode ->
                            roles.associateWith { role ->
                                val id = resources.getIdentifier("system_${role}_$mode", "color", "android")
                                check(id != 0)
                                resources.getColor(id, null)
                            }
                        }
                    }.getOrNull()
                    result.success(colors)
                }
            }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (resources.getBoolean(R.bool.spy_profile_diagnostics)) {
            // AudioServiceActivity creates its own cached engine without the
            // activity's shell arguments. Initialize the VM first in Profile
            // so profiling/discovery flags reach that same audio engine.
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            val args = (flutterShellArgs.toArray().toList() + "--enable-dart-profiling")
                .distinct().toTypedArray()
            loader.ensureInitializationComplete(applicationContext, args)
        }
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPause() {
        nativeKyant?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        nativeKyant?.resume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        nativeKyant?.focusChanged(hasFocus)
    }

    override fun onDestroy() {
        nativeKyant?.dispose()
        nativeKyant = null
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
