package com.example.rawviewer

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var hdrImages: HdrImagePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hdrImages = HdrImagePlugin(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hdrImages?.close()
        hdrImages = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
