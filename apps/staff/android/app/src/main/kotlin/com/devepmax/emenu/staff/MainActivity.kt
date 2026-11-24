package com.devepmax.emenu.staff

import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Si este aparato puede cobrar con Tap to Pay: chip NFC y Android 13 o más nuevo.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "devepmax/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "tapToPayHardware" -> {
                    val hasNfc = packageManager.hasSystemFeature(PackageManager.FEATURE_NFC)
                    val adapter = NfcAdapter.getDefaultAdapter(this)
                    result.success(
                        mapOf(
                            "nfc" to hasNfc,
                            "nfcOn" to (adapter?.isEnabled ?: false),
                            "android13" to (Build.VERSION.SDK_INT >= 33),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }
}
