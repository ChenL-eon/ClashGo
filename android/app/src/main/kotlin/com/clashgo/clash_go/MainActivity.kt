package com.clashgo.clash_go

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private var pendingVpnPermission: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInfo" -> result.success(coreInfo())
                "prepareVpn" -> prepareVpn(result)
                "startVpn" -> startVpn(call.arguments as? Map<*, *>, result)
                "stopVpn" -> stopVpn(result)
                "status" -> result.success(CoreVpnState.snapshot())
                else -> result.notImplemented()
            }
        }
    }

    private fun coreInfo(): Map<String, Any> {
        val dir = applicationInfo.nativeLibraryDir
        val binary = File(dir, "libmihomo.so")
        return mapOf(
            "nativeLibraryDir" to dir,
            "binaryPath" to binary.absolutePath,
            "binaryExists" to binary.exists(),
        )
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        if (pendingVpnPermission != null) {
            result.error("vpn_busy", "A VPN permission request is already pending", null)
            return
        }
        pendingVpnPermission = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } catch (t: Throwable) {
            pendingVpnPermission = null
            result.error("vpn_permission", t.message ?: "Cannot show VPN permission dialog", null)
        }
    }

    private fun startVpn(args: Map<*, *>?, result: MethodChannel.Result) {
        if (args == null) {
            result.error("vpn_args", "Missing start arguments", null)
            return
        }
        val intent = Intent(this, CoreVpnService::class.java).apply {
            action = CoreVpnService.ACTION_START
            putExtra(CoreVpnService.EXTRA_CONFIG_PATH, args["configPath"] as? String)
            putExtra(CoreVpnService.EXTRA_RUNTIME_DIR, args["runtimeDir"] as? String)
            putExtra(CoreVpnService.EXTRA_BINARY_PATH, args["binaryPath"] as? String)
            putExtra(CoreVpnService.EXTRA_LOG_PATH, args["logPath"] as? String)
            putExtra(CoreVpnService.EXTRA_API_PORT, (args["apiPort"] as? Number)?.toInt() ?: 0)
            putExtra(CoreVpnService.EXTRA_SUBSCRIPTION_ID, args["subscriptionId"] as? String)
            putExtra(CoreVpnService.EXTRA_IPV6, args["ipv6"] as? Boolean ?: false)
            putExtra(CoreVpnService.EXTRA_BYPASS_PRIVATE, args["bypassPrivate"] as? Boolean ?: true)
            putExtra(CoreVpnService.EXTRA_MTU, (args["mtu"] as? Number)?.toInt() ?: 0)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_TITLE, args["notificationTitle"] as? String)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_TEXT, args["notificationText"] as? String)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_STOP, args["notificationStop"] as? String)
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            result.success(true)
        } catch (t: Throwable) {
            result.error("vpn_start", t.message ?: "Cannot start VPN service", null)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        if (!CoreVpnState.serviceRunning) {
            result.success(true)
            return
        }
        try {
            startService(Intent(this, CoreVpnService::class.java).setAction(CoreVpnService.ACTION_STOP))
            result.success(true)
        } catch (t: Throwable) {
            result.error("vpn_stop", t.message ?: "Cannot stop VPN service", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST) {
            val pending = pendingVpnPermission
            pendingVpnPermission = null
            pending?.success(resultCode == RESULT_OK)
        }
    }

    override fun onDestroy() {
        pendingVpnPermission?.error("vpn_permission", "Activity destroyed before permission result", null)
        pendingVpnPermission = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.clashgo.clash_go/core"
        private const val VPN_PERMISSION_REQUEST = 2102
        private const val NOTIFICATION_PERMISSION_REQUEST = 2103
    }
}
