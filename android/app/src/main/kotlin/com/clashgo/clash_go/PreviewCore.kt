package com.clashgo.clash_go

import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 预览内核：界面可见时起一个不走 VpnService 的 mihomo，只服务 /proxies 和
 * 节点延迟测速。没有 tun、没有前台服务通知；界面不可见时由 Dart 侧停掉。
 * 与 CoreVpnService 互斥：接管中的内核在跑时不会接受预览启动。
 */
object PreviewCore {
    private const val TAG = "ClashGoPreview"
    private const val PID_FILE = "preview.pid"
    private const val MONITOR_INTERVAL_MS = 2000L
    private const val GRACEFUL_STOP_TIMEOUT_MS = 1500
    private const val FORCE_STOP_TIMEOUT_MS = 600

    private val lock = Any()

    @Volatile private var state = "stopped"
    @Volatile private var pid = -1
    @Volatile private var error: String? = null
    @Volatile private var exitCode: Int? = null
    @Volatile private var apiPort = 0
    @Volatile private var subscriptionId: String? = null
    @Volatile private var startedAt = 0L
    @Volatile private var stopping = false
    @Volatile private var logPath: String? = null
    @Volatile private var runtimePath: String? = null

    @Volatile private var startWorker: Thread? = null
    @Volatile private var stopWorker: Thread? = null
    @Volatile private var monitor: Thread? = null

    fun requestStart(args: Map<*, *>?): Boolean {
        val configPath = args?.get("configPath") as? String
        val runtimeDir = args?.get("runtimeDir") as? String
        val binaryPath = args?.get("binaryPath") as? String
        val log = args?.get("logPath") as? String
        val port = (args?.get("apiPort") as? Number)?.toInt() ?: 0
        val subId = args?.get("subscriptionId") as? String
        if (configPath.isNullOrBlank() || runtimeDir.isNullOrBlank() ||
            binaryPath.isNullOrBlank() || log.isNullOrBlank()
        ) {
            return false
        }
        synchronized(lock) {
            // 接管内核在跑时绝不并存：同一组端口，而且会让"代理已关"的语义变浑。
            if (CoreVpnState.serviceRunning) return false
            if (startWorker?.isAlive == true || stopWorker?.isAlive == true) return false
            if (pid > 0 || state == "running" || state == "starting") return false
            stopping = false
            state = "starting"
            error = null
            exitCode = null
            apiPort = port
            subscriptionId = subId
            startedAt = 0L
            logPath = log
            runtimePath = runtimeDir
        }
        startWorker = Thread({
            runStart(File(configPath), File(runtimeDir), File(binaryPath), log)
        }, "clashgo-preview-start").also { it.start() }
        return true
    }

    private fun runStart(configFile: File, runtime: File, binary: File, logFile: String) {
        try {
            if (!configFile.isFile) {
                throw IllegalStateException("Config file is missing: ${configFile.absolutePath}")
            }
            if (!runtime.isDirectory && !runtime.mkdirs()) {
                throw IllegalStateException("Cannot create runtime directory: ${runtime.absolutePath}")
            }
            if (!binary.isFile) {
                throw IllegalStateException("mihomo binary is missing: ${binary.absolutePath}")
            }
            if (!NativeProcess.ensureLoaded()) {
                throw IllegalStateException("Native helper unavailable: ${NativeProcess.loadFailure()}")
            }

            val args = arrayOf("-d", runtime.absolutePath, "-f", configFile.absolutePath)
            // tunFd / childTunFd 都是 -1：C helper 跳过 fd 搬运，子进程按普通进程运行。
            val child = NativeProcess.nativeForkExec(
                binary.absolutePath,
                args,
                runtime.absolutePath,
                logFile,
                -1,
                -1,
            )
            if (child <= 0) throw IllegalStateException("fork+exec failed (result=$child)")

            val aborted = synchronized(lock) {
                if (stopping) {
                    true
                } else {
                    pid = child
                    writePidFile(runtime, child)
                    state = "running"
                    error = null
                    startedAt = System.currentTimeMillis()
                    false
                }
            }
            if (aborted) {
                NativeProcess.nativeKill(child, false)
                NativeProcess.nativeWaitpid(child, GRACEFUL_STOP_TIMEOUT_MS)
                finishStopped(runtime)
                return
            }
            appendLog("preview core started: pid=$child")
            monitor = Thread({ monitorLoop(runtime, child) }, "clashgo-preview-monitor").also {
                it.start()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "preview start failed: ${t.message}")
            if (stopping) {
                finishStopped(runtime)
            } else {
                synchronized(lock) {
                    pid = -1
                    state = "error"
                    error = t.message ?: t.javaClass.simpleName
                    exitCode = null
                }
            }
        }
    }

    private fun monitorLoop(runtime: File, child: Int) {
        while (true) {
            try {
                Thread.sleep(MONITOR_INTERVAL_MS)
            } catch (_: InterruptedException) {
                return
            }
            if (stopping) return
            val code = try {
                NativeProcess.nativePollExit(child)
            } catch (_: Throwable) {
                -1
            }
            if (code == -2) continue
            var unexpected = false
            synchronized(lock) {
                if (pid != child) return
                pid = -1
                deletePidFile(runtime)
                if (stopping) {
                    state = "stopped"
                } else {
                    state = "error"
                    error = "mihomo exited with code $code"
                    exitCode = code.takeIf { it >= 0 }
                    unexpected = true
                }
            }
            appendLog(
                if (unexpected) {
                    "preview core exited unexpectedly (code=$code)"
                } else {
                    "preview core stopped (code=$code)"
                },
            )
            return
        }
    }

    fun requestStop(): Boolean {
        synchronized(lock) {
            if (stopWorker?.isAlive == true) return true
            if (pid <= 0 && state != "starting" && state != "running" &&
                state != "error" && state != "stopping"
            ) {
                state = "stopped"
                return true
            }
            stopping = true
            if (state == "running" || state == "starting") state = "stopping"
        }
        stopWorker = Thread({ runStop() }, "clashgo-preview-stop").also { it.start() }
        return true
    }

    private fun runStop() {
        try {
            startWorker?.join(2000)
            val child = synchronized(lock) { pid }
            if (child > 0) {
                monitor?.interrupt()
                NativeProcess.nativeKill(child, false)
                var code = NativeProcess.nativeWaitpid(child, GRACEFUL_STOP_TIMEOUT_MS)
                if (code == -1) {
                    NativeProcess.nativeKill(child, true)
                    code = NativeProcess.nativeWaitpid(child, FORCE_STOP_TIMEOUT_MS)
                }
                appendLog("preview core stopped (code=$code)")
            }
            finishStopped(runtimePath?.let(::File))
        } catch (_: Throwable) {
            finishStopped(runtimePath?.let(::File))
        }
    }

    fun status(): Map<String, Any?> = synchronized(lock) {
        mapOf(
            "state" to state,
            "pid" to pid,
            "serviceRunning" to false,
            "error" to error,
            "exitCode" to exitCode,
            "apiPort" to apiPort,
            "subscriptionId" to subscriptionId,
            "startedAt" to startedAt,
        )
    }

    /** 上个界面会话被系统杀掉后留下的预览内核：按 pid 文件收掉。 */
    fun cleanup(runtimeDir: String?) {
        if (runtimeDir.isNullOrBlank()) return
        val runtime = File(runtimeDir)
        val file = File(runtime, PID_FILE)
        if (!file.isFile) return
        val stale = try {
            file.readText().trim().toIntOrNull()
        } catch (_: Throwable) {
            null
        }
        try {
            file.delete()
        } catch (_: Throwable) {}
        if (stale == null || stale <= 0) return
        if (stale == pid || stale == CoreVpnState.pid) return
        // pid 会被复用：只杀命令行里确实是 mihomo 的那个进程。
        val cmdline = try {
            File("/proc/$stale/cmdline").readBytes().toString(Charsets.UTF_8)
        } catch (_: Throwable) {
            return
        }
        if (!cmdline.contains("mihomo")) return
        if (!NativeProcess.ensureLoaded()) return
        NativeProcess.nativeKill(stale, true)
        Log.i(TAG, "killed stale preview core pid=$stale")
    }

    private fun finishStopped(runtime: File?) {
        synchronized(lock) {
            pid = -1
            deletePidFile(runtime)
            state = "stopped"
            error = null
            exitCode = null
            apiPort = 0
            subscriptionId = null
            startedAt = 0L
            stopping = false
        }
    }

    private fun writePidFile(runtime: File, child: Int) {
        try {
            File(runtime, PID_FILE).writeText(child.toString())
        } catch (_: Throwable) {}
    }

    private fun deletePidFile(runtime: File?) {
        if (runtime == null) return
        try {
            File(runtime, PID_FILE).delete()
        } catch (_: Throwable) {}
    }

    private fun appendLog(message: String) {
        Log.i(TAG, message)
        val path = logPath ?: return
        try {
            val time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date())
            File(path).appendText("[$time] [preview] $message\n")
        } catch (_: Throwable) {}
    }
}
