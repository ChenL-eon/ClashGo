package com.clashgo.clash_go

// Android 的 ProcessBuilder 会关闭所有非标准 fd，而 tun fd 必须传给 mihomo 子进程，
// 所以这里用 JNI 自己 fork+exec。
object NativeProcess {

    private var loaded = false
    private var loadError: String? = null

    @Synchronized
    fun ensureLoaded(): Boolean {
        if (loaded) return true
        if (loadError != null) return false
        return try {
            System.loadLibrary("clashgo_native")
            loaded = true
            true
        } catch (t: Throwable) {
            loadError = t.message ?: t.javaClass.simpleName
            false
        }
    }

    fun loadFailure(): String? = loadError

    external fun nativeForkExec(
        binary: String,
        args: Array<String>,
        workDir: String,
        logFile: String?,
        tunFd: Int,
        childTunFd: Int,
    ): Int

    external fun nativeKill(pid: Int, force: Boolean)

    external fun nativeWaitpid(pid: Int, timeoutMs: Int): Int

    external fun nativePollExit(pid: Int): Int
}
