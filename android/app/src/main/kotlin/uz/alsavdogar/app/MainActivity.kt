package uz.alsavdogar.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var smsBridge: SmsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SmsBridge(this)
        smsBridge = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SmsBridge.CHANNEL)
            .setMethodCallHandler { call, result -> bridge.onMethodCall(call, result) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        smsBridge?.onPermissionsResult(requestCode)
    }
}
