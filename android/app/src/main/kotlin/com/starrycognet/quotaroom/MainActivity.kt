package com.starrycognet.quotaroom

import android.webkit.CookieManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "quotaroom/cookie_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CookieManager.getInstance().setAcceptCookie(true)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookie" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "url is required", null)
                        } else {
                            // Chromium's CookieManager uses MakeAllInclusive(),
                            // which includes HttpOnly cookies. The one-argument
                            // public API is enough, so no hidden API reflection.
                            val cookie = CookieManager.getInstance().getCookie(url)
                            result.success(cookie)
                        }
                    }
                    "clearCookies" -> {
                        CookieManager.getInstance().removeAllCookies {
                            runOnUiThread { result.success(true) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
