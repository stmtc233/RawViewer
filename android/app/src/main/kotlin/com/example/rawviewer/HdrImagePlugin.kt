package com.example.rawviewer

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.ImageView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.max

class HdrImagePlugin(private val activity: Activity, engine: FlutterEngine) {
    private val messenger = engine.dartExecutor.binaryMessenger
    private val channel = MethodChannel(messenger, "rawviewer/hdr")
    private val decoder = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var activeViews = 0
    private var previousColorMode = ActivityInfo.COLOR_MODE_DEFAULT

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "isSupported") {
                @Suppress("DEPRECATION")
                val display = activity.windowManager.defaultDisplay
                result.success(Build.VERSION.SDK_INT >= 34 &&
                    display.hdrCapabilities.supportedHdrTypes.isNotEmpty())
            } else {
                result.notImplemented()
            }
        }
        engine.platformViewsController.registry.registerViewFactory(
            "rawviewer/hdr_image", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
                    HdrView(context, viewId)
            })
    }

    fun close() {
        channel.setMethodCallHandler(null)
        decoder.shutdown()
        if (activeViews > 0) activity.window.colorMode = previousColorMode
        activeViews = 0
    }

    private inner class HdrView(context: Context, id: Int) : PlatformView {
        private val imageView = ImageView(context)
        private val methods = MethodChannel(messenger, "rawviewer/hdr/$id")
        private var bitmap: Bitmap? = null
        private var generation = 0
        private var disposed = false
        private var ownsHdrMode = false

        init {
            imageView.scaleType = ImageView.ScaleType.FIT_CENTER
            methods.setMethodCallHandler { call, result ->
                val path = call.argument<String>("path")
                val width = call.argument<Int>("width")
                if (call.method != "load" || path == null || width == null ||
                    Build.VERSION.SDK_INT < 34 || disposed) {
                    result.success(false)
                } else {
                    val request = ++generation
                    decoder.execute {
                        val decoded = try {
                            ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { decoder, info, _ ->
                                val extent = width.coerceIn(128, 8192)
                                val scale = minOf(1.0, extent.toDouble() / max(info.size.width, info.size.height))
                                decoder.setTargetSize(max(1, (info.size.width * scale).toInt()),
                                    max(1, (info.size.height * scale).toInt()))
                            }
                        } catch (_: Exception) { null }
                        main.post {
                            if (disposed || request != generation) {
                                decoded?.recycle()
                                result.success(false)
                            } else {
                                val isHdr = decoded != null && (decoded.hasGainmap() ||
                                    decoded.colorSpace == ColorSpace.get(ColorSpace.Named.BT2020_HLG) ||
                                    decoded.colorSpace == ColorSpace.get(ColorSpace.Named.BT2020_PQ))
                                if (isHdr) {
                                    if (!ownsHdrMode) {
                                        if (activeViews++ == 0) {
                                            previousColorMode = activity.window.colorMode
                                            activity.window.colorMode = ActivityInfo.COLOR_MODE_HDR
                                        }
                                        ownsHdrMode = true
                                    }
                                    val previous = bitmap
                                    bitmap = decoded
                                    imageView.setImageBitmap(decoded)
                                    previous?.recycle()
                                } else { decoded?.recycle() }
                                result.success(isHdr)
                            }
                        }
                    }
                }
            }
        }

        override fun getView(): View = imageView

        override fun dispose() {
            disposed = true
            generation++
            methods.setMethodCallHandler(null)
            imageView.setImageDrawable(null)
            bitmap?.recycle()
            bitmap = null
            if (ownsHdrMode) {
                ownsHdrMode = false
                if (activeViews > 0 && --activeViews == 0) {
                    activity.window.colorMode = previousColorMode
                }
            }
        }
    }
}
