package com.clashgo.clash_go

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.system.Os
import android.system.OsConstants
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CoreVpnService : VpnService() {

    private var tunFd = -1
    private var childPid = -1
    private val processLock = Any()

    @Volatile private var stopping = false
    @Volatile private var worker: Thread? = null
    @Volatile private var stopWorker: Thread? = null
    @Volatile private var monitor: Thread? = null
    @Volatile private var notificationWorker: Thread? = null
    @Volatile private var notifierConnection: HttpURLConnection? = null

    private var logPath: String? = null
    private var apiSecret = ""
    private var notificationTitle = "Clash Go"
    private var notificationText = "VPN"
    private var notificationStop = "Stop"

    override fun onCreate() {
        super.onCreate()
        CoreVpnState.serviceRunning = true
        createChannel()
        try {
            startForeground(NOTIFICATION_ID, buildNotification("Clash Go", "VPN", "Stop"))
        } catch (t: Throwable) {
            CoreVpnState.state = "error"
            CoreVpnState.error = "Foreground service failed: ${t.message}"
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> requestStop()
            else -> if (childPid <= 0 && worker?.isAlive != true) stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun handleStart(intent: Intent) {
        if (worker?.isAlive == true) {
            Log.i(TAG, "Start ignored: previous start still in progress")
            return
        }
        val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
        val runtimeDir = intent.getStringExtra(EXTRA_RUNTIME_DIR)
        val binaryPath = intent.getStringExtra(EXTRA_BINARY_PATH)
        val logFilePath = intent.getStringExtra(EXTRA_LOG_PATH)
        val allowIpv6 = intent.getBooleanExtra(EXTRA_IPV6, false)
        val bypassPrivate = intent.getBooleanExtra(EXTRA_BYPASS_PRIVATE, true)
        val tunMtu = intent.getIntExtra(EXTRA_MTU, 0)
        notificationTitle = intent.getStringExtra(EXTRA_NOTIFICATION_TITLE) ?: "Clash Go"
        notificationText = intent.getStringExtra(EXTRA_NOTIFICATION_TEXT) ?: "VPN connected"
        notificationStop = intent.getStringExtra(EXTRA_NOTIFICATION_STOP) ?: "Stop"
        apiSecret = intent.getStringExtra(EXTRA_API_SECRET) ?: ""
        logPath = logFilePath

        if (configPath == null || runtimeDir == null || binaryPath == null || logFilePath == null) {
            failStart(IllegalStateException("Missing start arguments"))
            return
        }
        // MTU 只有一份（Dart 侧 AppInfo.tunMtu）。这里不留兜底常量：宁可启动失败
        // 写进通知，也不能让内核设备和 gvisor 各按各的 MTU 跑，那是静默分片。
        if (tunMtu <= 0) {
            failStart(IllegalStateException("Missing tun MTU in start arguments"))
            return
        }
        val configFile = File(configPath)
        val runtime = File(runtimeDir)
        val binary = File(binaryPath)
        if (!configFile.isFile) {
            failStart(IllegalStateException("Config file is missing: $configPath"))
            return
        }
        if (!runtime.isDirectory && !runtime.mkdirs()) {
            failStart(IllegalStateException("Cannot create runtime directory: $runtimeDir"))
            return
        }
        if (!binary.isFile) {
            failStart(IllegalStateException("mihomo binary is missing: $binaryPath"))
            return
        }

        stopping = false
        CoreVpnState.state = "starting"
        CoreVpnState.pid = -1
        CoreVpnState.error = null
        CoreVpnState.exitCode = null
        CoreVpnState.apiPort = intent.getIntExtra(EXTRA_API_PORT, 0)
        CoreVpnState.subscriptionId = intent.getStringExtra(EXTRA_SUBSCRIPTION_ID)
        CoreVpnState.startedAt = 0L
        updateNotification(notificationTitle, notificationText)

        worker = Thread({
            runStart(configFile, runtime, binary, logFilePath, allowIpv6, bypassPrivate, tunMtu)
        }, "clashgo-vpn-start").also { it.start() }
    }

    private fun runStart(
        configFile: File,
        runtime: File,
        binary: File,
        logFilePath: String,
        allowIpv6: Boolean,
        bypassPrivate: Boolean,
        mtu: Int,
    ) {
        try {
            prepareGeodata(runtime)
            if (stopping) return

            val fd = establishTun(allowIpv6, bypassPrivate, mtu)
            synchronized(processLock) { tunFd = fd }
            if (stopping) {
                closeTunFd()
                return
            }

            val raw = configFile.readText()
            if (!raw.contains(TUN_FD_TOKEN)) {
                throw IllegalStateException("Config has no tun fd placeholder")
            }
            configFile.writeText(raw.replace(TUN_FD_TOKEN, CHILD_TUN_FD.toString()))
            appendLog("tun fd=$fd mtu=$mtu will be dup2'ed to $CHILD_TUN_FD in child")
            if (stopping) {
                closeTunFd()
                return
            }

            if (!NativeProcess.ensureLoaded()) {
                throw IllegalStateException("Native helper unavailable: ${NativeProcess.loadFailure()}")
            }
            val args = arrayOf("-d", runtime.absolutePath, "-f", configFile.absolutePath)
            val pid = NativeProcess.nativeForkExec(
                binary.absolutePath,
                args,
                runtime.absolutePath,
                logFilePath,
                fd,
                CHILD_TUN_FD,
            )
            if (pid <= 0) throw IllegalStateException("fork+exec failed (result=$pid)")

            val aborted = synchronized(processLock) {
                if (stopping) {
                    true
                } else {
                    childPid = pid
                    false
                }
            }
            if (aborted) {
                NativeProcess.nativeKill(pid, false)
                NativeProcess.nativeWaitpid(pid, 1000)
                closeTunFd()
                return
            }

            CoreVpnState.pid = pid
            CoreVpnState.startedAt = System.currentTimeMillis()
            CoreVpnState.state = "running"
            CoreVpnState.error = null
            appendLog("mihomo started: pid=$pid (ipv6=$allowIpv6, bypassPrivate=$bypassPrivate)")
            updateNotification(notificationTitle, notificationText)

            monitor = Thread({ monitorLoop() }, "clashgo-vpn-monitor").also { it.start() }
            startNotificationUpdater()
            Thread({ mirrorCoreLog(logFilePath) }, "clashgo-core-log").start()
        } catch (t: Throwable) {
            if (stopping) {
                closeTunFd()
                return
            }
            failStart(t)
        }
    }

    private fun establishTun(allowIpv6: Boolean, bypassPrivate: Boolean, mtu: Int): Int {
        val builder = Builder()
        builder.addAddress(TUN_GATEWAY, TUN_PREFIX)
        builder.setMtu(mtu)
        builder.setSession("ClashGo")
        builder.setBlocking(false)

        if (bypassPrivate) {
            BYPASS_PRIVATE_ROUTES4.forEach { builder.addRouteCidr(it) }
            builder.addRoute(TUN_DNS, 32)
        } else {
            builder.addRoute("0.0.0.0", 0)
        }

        if (allowIpv6) {
            builder.addAddress(TUN_GATEWAY6, TUN_PREFIX6)
            if (bypassPrivate) {
                BYPASS_PRIVATE_ROUTES6.forEach { builder.addRouteCidr(it) }
                builder.addRoute(TUN_DNS6, 128)
            } else {
                builder.addRoute("::", 0)
            }
        }

        builder.addDnsServer(TUN_DNS)
        if (allowIpv6) builder.addDnsServer(TUN_DNS6)
        builder.allowBypass()
        // Excluding our own package keeps mihomo's upstream sockets out of its tun.
        builder.addDisallowedApplication(packageName)
        builder.setMetered(false)

        val pfd = builder.establish()
            ?: throw IllegalStateException("VpnService.establish returned null (another VPN may be active)")
        val fd = pfd.detachFd()
        val adopted = ParcelFileDescriptor.adoptFd(fd)
        try {
            val flags = Os.fcntlInt(adopted.fileDescriptor, OsConstants.F_GETFD, 0)
            Os.fcntlInt(adopted.fileDescriptor, OsConstants.F_SETFD, flags and OsConstants.FD_CLOEXEC.inv())
            val after = Os.fcntlInt(adopted.fileDescriptor, OsConstants.F_GETFD, 0)
            appendLog("tun fd=$fd cloexec flags before=0x${Integer.toHexString(flags)} after=0x${Integer.toHexString(after)}")
            if ((after and OsConstants.FD_CLOEXEC) != 0) {
                throw IllegalStateException("FD_CLOEXEC still set on tun fd $fd")
            }
        } catch (t: Throwable) {
            try {
                adopted.close()
            } catch (_: Throwable) {}
            throw IllegalStateException("Cannot clear FD_CLOEXEC on tun fd: ${t.message}", t)
        }
        adopted.detachFd()
        return fd
    }

    private fun prepareGeodata(runtime: File) {
        val names = listOf("geoip.metadb", "geosite.dat", "GeoIP.dat")
        val marker = File(runtime, ".geodata-version")
        val version = appVersion()
        val ready = marker.isFile && marker.readText().trim() == version && names.all { File(runtime, it).isFile }
        if (ready) return

        appendLog("Preparing geodata (version $version)")
        names.forEach { name ->
            if (stopping) return
            val dst = File(runtime, name)
            assets.open("geodata/$name").use { input ->
                dst.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
            }
        }
        marker.writeText(version)
        appendLog("Geodata ready")
    }

    private fun appVersion(): String = try {
        val info = packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode.toString()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toString()
        }
    } catch (_: Throwable) {
        "1"
    }

    private fun monitorLoop() {
        while (!stopping) {
            try {
                // 隧道存续期间系统替 VpnService 持有 PARTIAL_WAKE_LOCK，CPU 不会深度休眠，
                // 这里的每一次唤醒都是真实功耗。Dart 侧还有 2s 的 status 轮询会先发现内核
                // 失联，所以存活探测放宽到 5s，只作为兜底。
                Thread.sleep(5000)
            } catch (_: InterruptedException) {
                return
            }
            val pid = synchronized(processLock) { childPid }
            if (pid <= 0) return
            val code = pollExit(pid)
            if (code == -2) continue
            if (code == -3) return
            handleUnexpectedExit(code)
            return
        }
    }

    // -2 while alive, -3 if another thread already cleaned up, otherwise the exit code.
    private fun pollExit(pid: Int): Int = synchronized(processLock) {
        if (childPid != pid) return -3
        val result = NativeProcess.nativePollExit(pid)
        if (result != -2) childPid = -1
        result
    }

    private fun handleUnexpectedExit(code: Int) {
        CoreVpnState.pid = -1
        CoreVpnState.exitCode = code.takeIf { it >= 0 }
        stopNotificationUpdater()
        closeTunFd()
        if (stopping) return
        CoreVpnState.state = "error"
        CoreVpnState.error = "mihomo exited with code $code"
        appendLog("mihomo exited unexpectedly (code=$code)")
        updateNotification(notificationTitle, "内核已退出 / Core exited")
        stopForegroundCompat()
        stopSelf()
    }

    private fun requestStop() {
        if (stopWorker?.isAlive == true) return
        stopping = true
        CoreVpnState.state = "stopping"
        stopNotificationUpdater()
        stopWorker = Thread({
            worker?.join(1500)
            monitor?.interrupt()
            cleanupChild(GRACEFUL_STOP_TIMEOUT_MS)
            closeTunFd()
            synchronized(processLock) { childPid = -1 }
            CoreVpnState.pid = -1
            CoreVpnState.exitCode = null
            CoreVpnState.apiPort = 0
            CoreVpnState.subscriptionId = null
            CoreVpnState.startedAt = 0L
            CoreVpnState.state = "stopped"
            CoreVpnState.error = null
            appendLog("VPN service stopped")
            stopForegroundCompat()
            stopSelf()
        }, "clashgo-vpn-stop").also { it.start() }
    }

    private fun cleanupChild(timeoutMs: Int) {
        val pid = synchronized(processLock) { childPid }
        if (pid <= 0 || !NativeProcess.ensureLoaded()) return
        NativeProcess.nativeKill(pid, false)
        var code = NativeProcess.nativeWaitpid(pid, timeoutMs)
        if (code == -1) {
            NativeProcess.nativeKill(pid, true)
            code = NativeProcess.nativeWaitpid(pid, 600)
        }
        synchronized(processLock) { if (childPid == pid) childPid = -1 }
        appendLog("mihomo stopped (code=$code)")
    }

    private fun closeTunFd() {
        val fd = synchronized(processLock) {
            val current = tunFd
            tunFd = -1
            current
        }
        if (fd < 0) return
        try {
            ParcelFileDescriptor.adoptFd(fd).close()
            Log.i(TAG, "Closed tun fd=$fd")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to close tun fd=$fd: ${t.message}")
        }
    }

    private fun failStart(t: Throwable) {
        val detail = t.message ?: t.javaClass.simpleName
        appendLog("start failed: $detail")
        CoreVpnState.state = "error"
        CoreVpnState.error = detail
        CoreVpnState.pid = -1
        CoreVpnState.exitCode = null
        closeTunFd()
        stopNotificationUpdater()
        updateNotification(notificationTitle, "启动失败 / Start failed")
        stopForegroundCompat()
        stopSelf()
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        requestStop()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopping = true
        stopNotificationUpdater()
        monitor?.interrupt()
        worker?.interrupt()
        cleanupChild(500)
        closeTunFd()
        synchronized(processLock) { childPid = -1 }
        if (CoreVpnState.state != "error") {
            CoreVpnState.state = "stopped"
            CoreVpnState.pid = -1
            CoreVpnState.error = null
            CoreVpnState.apiPort = 0
            CoreVpnState.subscriptionId = null
            CoreVpnState.startedAt = 0L
        }
        CoreVpnState.serviceRunning = false
        Log.i(TAG, "CoreVpnService destroyed")
        super.onDestroy()
    }

    // ------------------------------------------------------------------ logging

    private fun appendLog(message: String) {
        Log.i(TAG, message)
        val path = logPath ?: return
        try {
            val time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
            File(path).appendText("[$time] [service] $message\n")
        } catch (_: Throwable) {}
    }

    // Mirrors the startup section and any TUN/error lines to logcat, so a dead
    // data plane can be diagnosed without pulling the app-private log file.
    private fun mirrorCoreLog(path: String) {
        try {
            Thread.sleep(1500)
            val file = File(path)
            if (!file.isFile) return
            var extra = 0
            file.useLines { lines ->
                lines.forEachIndexed { index, line ->
                    val trimmed = line.trim()
                    if (trimmed.isEmpty()) return@forEachIndexed
                    val interesting = index < 40 ||
                        trimmed.contains("error", true) ||
                        trimmed.contains("warn", true) ||
                        trimmed.contains("tun", true) ||
                        trimmed.contains("dns", true)
                    if (interesting) {
                        Log.i("ClashGoCore", trimmed)
                        if (index >= 40 && ++extra > 200) return@useLines
                    }
                }
            }
            Log.i(TAG, "mirrored core startup log")
        } catch (_: Throwable) {}
    }

    // ------------------------------------------------- notification feed

    private fun startNotificationUpdater() {
        notificationWorker?.interrupt()
        notificationWorker = Thread({ notificationLoop() }, "clashgo-vpn-notify").also { it.start() }
    }

    private fun stopNotificationUpdater() {
        notificationWorker?.interrupt()
        notificationWorker = null
        notifierConnection?.disconnect()
        notifierConnection = null
    }

    // /traffic 不带 Upgrade 头时是普通 chunked 流，每秒一行 JSON；/proxies 每 10 秒
    // 拉一次取当前节点。息屏后通知栏没人看，停止读取，避免每秒唤醒。
    private fun notificationLoop() {
        val power = getSystemService(PowerManager::class.java)
        var node: String? = null
        var nextNodeFetch = 0L
        var failureLogged = false
        try {
            while (!stopping) {
                if (power != null && !power.isInteractive) {
                    Thread.sleep(SCREEN_OFF_POLL_MS)
                    continue
                }
                val port = CoreVpnState.apiPort
                if (port <= 0) {
                    Thread.sleep(FEED_RETRY_MS)
                    continue
                }
                if (node.isNullOrEmpty() || System.currentTimeMillis() >= nextNodeFetch) {
                    fetchActiveNode(port)?.let { node = it }
                    nextNodeFetch = System.currentTimeMillis() + NODE_REFRESH_MS
                }
                try {
                    val connection = openApi(port, "/traffic")
                    notifierConnection = connection
                    connection.connect()
                    connection.inputStream.bufferedReader().use { reader ->
                        while (!stopping) {
                            if (power != null && !power.isInteractive) break
                            val line = reader.readLine() ?: break
                            failureLogged = false
                            val frame = JSONObject(line)
                            val up = frame.optLong("up", 0L)
                            val down = frame.optLong("down", 0L)
                            val title = if (node.isNullOrEmpty()) notificationTitle else "Clash Go · $node"
                            updateNotification(title, "↑ ${formatRate(up)}   ↓ ${formatRate(down)}")
                            if (System.currentTimeMillis() >= nextNodeFetch) {
                                fetchActiveNode(port)?.let { node = it }
                                nextNodeFetch = System.currentTimeMillis() + NODE_REFRESH_MS
                            }
                        }
                    }
                } catch (t: Throwable) {
                    if (!stopping && !failureLogged) {
                        failureLogged = true
                        appendLog("notification feed unavailable: ${t.message}")
                    }
                } finally {
                    notifierConnection?.disconnect()
                    notifierConnection = null
                }
                if (!stopping) Thread.sleep(FEED_RETRY_MS)
            }
        } catch (_: InterruptedException) {
        }
    }

    private fun openApi(port: Int, path: String): HttpURLConnection {
        val connection = URL("http://127.0.0.1:$port$path").openConnection() as HttpURLConnection
        connection.connectTimeout = 3000
        connection.readTimeout = 12000
        connection.useCaches = false
        if (apiSecret.isNotEmpty()) {
            connection.setRequestProperty("Authorization", "Bearer $apiSecret")
        }
        return connection
    }

    // 与 Dart 的 ProxiesSnapshot.primaryGroup() 保持同一规则：跳过 GLOBAL，优先第一个
    // 有选中值的 Selector，否则退回第一个分组。
    private fun fetchActiveNode(port: Int): String? {
        val connection = openApi(port, "/proxies")
        return try {
            if (connection.responseCode != HttpURLConnection.HTTP_OK) return null
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val proxies = JSONObject(body).optJSONObject("proxies") ?: return null
            var firstGroupNow: String? = null
            var seenGroup = false
            val keys = proxies.keys()
            while (keys.hasNext()) {
                val name = keys.next()
                if (name == "GLOBAL") continue
                val item = proxies.optJSONObject(name) ?: continue
                val all = item.optJSONArray("all") ?: continue
                if (all.length() == 0) continue
                val now = item.optString("now", "")
                if (!seenGroup) {
                    seenGroup = true
                    firstGroupNow = now.ifEmpty { null }
                }
                val type = item.optString("type", "").lowercase(Locale.US)
                if ((type == "selector" || type == "select") && now.isNotEmpty()) return now
            }
            firstGroupNow
        } catch (_: Throwable) {
            null
        } finally {
            connection.disconnect()
        }
    }

    private fun formatRate(bytes: Long): String {
        if (bytes <= 0) return "0 B/s"
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var value = bytes.toDouble()
        var unit = 0
        while (value >= 1024 && unit < units.size - 1) {
            value /= 1024
            unit++
        }
        val text = when {
            value == value.toLong().toDouble() && unit <= 1 -> value.toLong().toString()
            value >= 100 -> String.format(Locale.US, "%.0f", value)
            else -> String.format(Locale.US, "%.1f", value).trimEnd('0').trimEnd('.')
        }
        return "$text ${units[unit]}/s"
    }

    // ------------------------------------------------------------- notifications

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, "Clash Go VPN", NotificationManager.IMPORTANCE_LOW).apply {
            description = "VPN connection status"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    @SuppressLint("DiscouragedApi")
    private fun buildNotification(title: String, text: String, stopText: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, CoreVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_stat_vpn)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_stat_vpn),
                    stopText,
                    stopIntent,
                ).build()
            )
        if (Build.VERSION.SDK_INT < 26) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_LOW)
        }
        return builder.build()
    }

    private fun updateNotification(title: String = notificationTitle, text: String = notificationText) {
        notificationTitle = title
        notificationText = text
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification(title, text, notificationStop))
        } catch (_: Throwable) {}
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= 24) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
    }

    private fun Builder.addRouteCidr(cidr: String): Builder {
        val parts = cidr.split('/')
        return addRoute(parts[0], parts[1].toInt())
    }

    companion object {
        private const val TAG = "CoreVpnService"
        private const val CHANNEL_ID = "clashgo_vpn"
        private const val NOTIFICATION_ID = 2101
        private const val TUN_FD_TOKEN = "__TUN_FD__"
        private const val CHILD_TUN_FD = 1000
        private const val TUN_GATEWAY = "198.18.0.1"
        private const val TUN_DNS = "198.18.0.2"
        private const val TUN_GATEWAY6 = "fdfe:dcba:9876::1"
        private const val TUN_DNS6 = "fdfe:dcba:9876::2"
        private const val TUN_PREFIX = 30
        private const val TUN_PREFIX6 = 126
        private const val GRACEFUL_STOP_TIMEOUT_MS = 3000
        private const val NODE_REFRESH_MS = 10_000L
        private const val FEED_RETRY_MS = 3000L
        private const val SCREEN_OFF_POLL_MS = 5000L

        const val ACTION_START = "com.clashgo.clash_go.action.START"
        const val ACTION_STOP = "com.clashgo.clash_go.action.STOP"
        const val EXTRA_CONFIG_PATH = "config_path"
        const val EXTRA_RUNTIME_DIR = "runtime_dir"
        const val EXTRA_BINARY_PATH = "binary_path"
        const val EXTRA_LOG_PATH = "log_path"
        const val EXTRA_API_PORT = "api_port"
        const val EXTRA_API_SECRET = "api_secret"
        const val EXTRA_SUBSCRIPTION_ID = "subscription_id"
        const val EXTRA_IPV6 = "ipv6"
        const val EXTRA_BYPASS_PRIVATE = "bypass_private"
        const val EXTRA_MTU = "tun_mtu"
        const val EXTRA_NOTIFICATION_TITLE = "notification_title"
        const val EXTRA_NOTIFICATION_TEXT = "notification_text"
        const val EXTRA_NOTIFICATION_STOP = "notification_stop"

        // Public IPv4 space only: RFC1918, link-local, loopback, multicast and
        // carrier-grade NAT stay outside the tunnel so LAN access keeps working.
        private val BYPASS_PRIVATE_ROUTES4 = listOf(
            "1.0.0.0/8", "2.0.0.0/7", "4.0.0.0/6", "8.0.0.0/7", "11.0.0.0/8", "12.0.0.0/6",
            "16.0.0.0/4", "32.0.0.0/3", "64.0.0.0/3", "96.0.0.0/4", "112.0.0.0/5",
            "120.0.0.0/6", "124.0.0.0/7", "126.0.0.0/8", "128.0.0.0/3", "160.0.0.0/5",
            "168.0.0.0/8", "169.0.0.0/9", "169.128.0.0/10", "169.192.0.0/11", "169.224.0.0/12",
            "169.240.0.0/13", "169.248.0.0/14", "169.252.0.0/15", "169.255.0.0/16",
            "170.0.0.0/7", "172.0.0.0/12", "172.32.0.0/11", "172.64.0.0/10", "172.128.0.0/9",
            "173.0.0.0/8", "174.0.0.0/7", "176.0.0.0/4", "192.0.0.0/9", "192.128.0.0/11",
            "192.160.0.0/13", "192.169.0.0/16", "192.170.0.0/15", "192.172.0.0/14",
            "192.176.0.0/12", "192.192.0.0/10", "193.0.0.0/8", "194.0.0.0/7", "196.0.0.0/6",
            "200.0.0.0/5", "208.0.0.0/4", "240.0.0.0/5", "248.0.0.0/6", "252.0.0.0/7",
            "254.0.0.0/8", "255.0.0.0/9", "255.128.0.0/10", "255.192.0.0/11", "255.224.0.0/12",
            "255.240.0.0/13", "255.248.0.0/14", "255.252.0.0/15", "255.254.0.0/16",
            "255.255.0.0/17", "255.255.128.0/18", "255.255.192.0/19", "255.255.224.0/20",
            "255.255.240.0/21", "255.255.248.0/22", "255.255.252.0/23", "255.255.254.0/24",
            "255.255.255.0/25", "255.255.255.128/26", "255.255.255.192/27",
            "255.255.255.224/28", "255.255.255.240/29", "255.255.255.248/30",
            "255.255.255.252/31", "255.255.255.254/32",
        )

        // Public IPv6 space only, excluding fc00::/7, fe80::/10 and ff00::/8.
        private val BYPASS_PRIVATE_ROUTES6 = listOf(
            "::/1", "8000::/2", "c000::/3", "e000::/4", "f000::/5", "f800::/6", "fe00::/9", "fec0::/10",
        )
    }
}
