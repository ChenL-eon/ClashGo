package com.clashgo.clash_go

// Shared between CoreVpnService and the Flutter method channel. Both live in the
// same process, so a process-wide snapshot is enough; there is no cross-process
// state to keep in sync.
object CoreVpnState {

    @Volatile var state: String = "stopped"
    @Volatile var pid: Int = -1
    @Volatile var error: String? = null
    @Volatile var exitCode: Int? = null
    @Volatile var apiPort: Int = 0
    @Volatile var subscriptionId: String? = null
    @Volatile var startedAt: Long = 0L
    @Volatile var serviceRunning: Boolean = false

    fun snapshot(): Map<String, Any> {
        val map = mutableMapOf<String, Any>(
            "state" to state,
            "pid" to pid,
            "serviceRunning" to serviceRunning,
        )
        error?.let { map["error"] = it }
        exitCode?.let { map["exitCode"] = it }
        if (apiPort > 0) map["apiPort"] = apiPort
        subscriptionId?.let { map["subscriptionId"] = it }
        if (startedAt > 0) map["startedAt"] = startedAt
        return map
    }
}
