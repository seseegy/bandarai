package com.rosdie.bandarai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bandarai/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Directory where Android extracted the bundled .so files;
                    // the only location an app may execute binaries from.
                    "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
