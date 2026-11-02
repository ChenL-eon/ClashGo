package com.clashgo.clash_go

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.Collator

class MainActivity : FlutterActivity() {

    private var pendingVpnPermission: MethodChannel.Result? = null
    private var linkChannel: MethodChannel? = null
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureLink(intent)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> listApps(result)
                "icons" -> loadIcons(call.arguments as? List<*>, result)
                else -> result.notImplemented()
            }
        }
        linkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINK_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    // 冷启动时 intent 先于 Flutter 引擎到达，链接在这儿等着被取走。
                    "consumeInitial" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureLink(intent)
    }

    private fun captureLink(intent: Intent?) {
        val data = intent?.data ?: return
        if (!data.scheme.equals("clash", ignoreCase = true)) return
        val text = data.toString()
        val channel = linkChannel
        if (channel == null) {
            pendingLink = text
        } else {
            channel.invokeMethod("link", text)
        }
    }

    private fun listApps(result: MethodChannel.Result) {
        Thread({
            val payload = try {
                collectLaunchableApps()
            } catch (t: Throwable) {
                runOnUiThread {
                    result.error("apps_list", t.message ?: "Cannot read installed apps", null)
                }
                return@Thread
            }
            runOnUiThread { result.success(payload) }
        }, "clashgo-app-list").start()
    }

    private fun collectLaunchableApps(): List<Map<String, Any>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val infos = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        val collator = Collator.getInstance()
        val seen = HashSet<String>()
        val apps = ArrayList<Map<String, Any>>()
        for (info in infos) {
            val pkg = info.activityInfo?.packageName ?: continue
            // 自身不参与分应用代理，列表里也不出现。
            if (pkg == packageName || !seen.add(pkg)) continue
            val label = info.loadLabel(packageManager)?.toString()?.trim().takeUnless { it.isNullOrEmpty() } ?: pkg
            val system = try {
                val appInfo = packageManager.getApplicationInfo(pkg, 0)
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            } catch (_: Throwable) {
                false
            }
            val entry = hashMapOf<String, Any>(
                "package" to pkg,
                "label" to label,
                "system" to system,
            )
            // 图标不跟列表一起回：几百个应用的原图塞进同一条 reply 会撞上
            // Binder 约 1 MB 的事务上限，整份列表都会失败。由 icons 分批取。
            apps.add(entry)
        }
        apps.sortWith { a, b -> collator.compare(a["label"] as String, b["label"] as String) }
        return apps
    }

    private fun loadIcons(arguments: List<*>?, result: MethodChannel.Result) {
        val packages = arguments
            ?.filterIsInstance<String>()
            ?.distinct()
            ?.take(MAX_ICONS_PER_CALL)
            ?: emptyList()
        Thread({
            val payload = HashMap<String, ByteArray>()
            for (pkg in packages) {
                try {
                    val drawable = packageManager.getApplicationInfo(pkg, 0).loadIcon(packageManager)
                    drawableToPng(drawable)?.let { payload[pkg] = it }
                } catch (_: Throwable) {
                    // 某个包在枚举之后被卸载、或图标读取失败：这一格留空即可。
                }
            }
            runOnUiThread { result.success(payload) }
        }, "clashgo-app-icons").start()
    }

    private fun drawableToPng(drawable: Drawable): ByteArray? {
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            return ByteArrayOutputStream().use { output ->
                if (bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) output.toByteArray() else null
            }
        } finally {
            bitmap.recycle()
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
            putExtra(CoreVpnService.EXTRA_API_SECRET, args["apiSecret"] as? String)
            putExtra(CoreVpnService.EXTRA_IPV6, args["ipv6"] as? Boolean ?: false)
            putExtra(CoreVpnService.EXTRA_BYPASS_PRIVATE, args["bypassPrivate"] as? Boolean ?: true)
            putExtra(CoreVpnService.EXTRA_MTU, (args["mtu"] as? Number)?.toInt() ?: 0)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_TITLE, args["notificationTitle"] as? String)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_TEXT, args["notificationText"] as? String)
            putExtra(CoreVpnService.EXTRA_NOTIFICATION_STOP, args["notificationStop"] as? String)
            putExtra(CoreVpnService.EXTRA_SPLIT_MODE, args["splitMode"] as? String ?: "all")
            putStringArrayListExtra(
                CoreVpnService.EXTRA_SPLIT_PACKAGES,
                ArrayList((args["splitPackages"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()),
            )
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
        private const val APPS_CHANNEL = "com.clashgo.clash_go/apps"
        private const val LINK_CHANNEL = "com.clashgo.clash_go/deeplink"
        private const val VPN_PERMISSION_REQUEST = 2102
        private const val NOTIFICATION_PERMISSION_REQUEST = 2103
        private const val MAX_ICONS_PER_CALL = 32
    }
}
