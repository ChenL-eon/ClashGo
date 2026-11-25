package com.clashgo.android.data.store

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// 恢复备份会整目录换入，排队中的异步写入如果在这之后落盘，会把刚恢复的值又盖回旧值。
// 所有内存 store 的写盘都要先拿这把全局锁；恢复换入时递增 generation，让已经排队但还没拿锁的
// 旧快照直接失效。锁顺序固定为「全局锁 → store 自己的 writeLock」，避免反向死锁。
internal object MihomoFileLock {

    private val mutex = Mutex()

    @Volatile
    private var generation: Long = 0

    fun currentGeneration(): Long = generation

    fun isCurrent(value: Long): Boolean = generation == value

    suspend fun <T> withWrite(block: suspend () -> T): T = mutex.withLock { block() }

    suspend fun <T> withRestore(block: suspend () -> T): T = mutex.withLock {
        generation++
        block()
    }
}
