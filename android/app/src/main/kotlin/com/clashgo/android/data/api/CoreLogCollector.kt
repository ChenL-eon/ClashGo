package com.clashgo.android.data.api

import com.clashgo.android.domain.model.LogEvent
import com.clashgo.android.domain.model.LogSource
import com.clashgo.android.domain.repository.MihomoRepository
import com.clashgo.android.util.AppLogger
import com.clashgo.android.util.DiagnosticLogStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class CoreLogCollector(
    private val scope: CoroutineScope,
    private val logs: DiagnosticLogStore = AppLogger.logs,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private var repository: MihomoRepository? = null
    private var visible = false
    private var job: Job? = null

    @Synchronized
    fun setRepository(repo: MihomoRepository?) {
        if (repository === repo) return
        repository = repo
        restart()
    }

    // 内核日志只服务于界面查看，应用退到后台就断开 /logs，避免服务运行期间持续解析推送。
    @Synchronized
    fun setVisible(visible: Boolean) {
        if (this.visible == visible) return
        this.visible = visible
        restart()
    }

    private fun restart() {
        job?.cancel()
        job = null
        logs.setCoreConnected(false)
        val repo = repository
        if (!visible || repo == null) return
        job = scope.launch(dispatcher) {
            // 内核向 /logs 推送时不看 log-level，只按订阅参数过滤；按实际生效的等级订阅，
            // 「核心日志」设置才能同时管住 mihomo.log 与这里。
            val level = repo.getConfig()
                .onFailure { AppLogger.warn("CoreLogCollector", "Failed to read core log level, using info", it) }
                .getOrNull()?.logLevel ?: "info"
            repo.logsFlow(level).collect { event ->
                synchronized(this@CoreLogCollector) {
                    if (!visible || repository !== repo) return@collect
                    when (event) {
                        LogEvent.Connected -> logs.setCoreConnected(true)
                        LogEvent.Disconnected -> logs.setCoreConnected(false)
                        is LogEvent.Message -> logs.append(LogSource.Core, event.message.type, "mihomo", event.message.payload)
                    }
                }
            }
        }
    }
}
