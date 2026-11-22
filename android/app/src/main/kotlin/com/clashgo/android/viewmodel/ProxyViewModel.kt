package com.clashgo.android.viewmodel

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clashgo.android.data.repository.OfflineProxyData
import com.clashgo.android.data.repository.OfflineProxyRepository
import com.clashgo.android.data.store.ProxySelectionStore
import com.clashgo.android.domain.model.DelayTestUrl
import com.clashgo.android.domain.model.ProviderInfo
import com.clashgo.android.domain.model.ProxyNode
import com.clashgo.android.domain.model.TestedDelay
import com.clashgo.android.domain.repository.MihomoRepository
import com.clashgo.android.platform.PlatformStorage
import com.clashgo.android.platform.StorageKeys
import com.clashgo.android.util.AppLogger
import com.clashgo.android.util.describe
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.ImmutableMap
import kotlinx.collections.immutable.ImmutableSet
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.persistentMapOf
import kotlinx.collections.immutable.persistentSetOf
import kotlinx.collections.immutable.toPersistentList
import kotlinx.collections.immutable.toPersistentMap
import kotlinx.collections.immutable.toPersistentSet
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

@Immutable
data class ProxyGroupUi(
    val name: String = "",
    val type: String = "",
    val now: String = "",
    val all: ImmutableList<String> = persistentListOf(),
    val delays: ImmutableMap<String, Int> = persistentMapOf(),
    val nodeTypes: ImmutableMap<String, String> = persistentMapOf(),
    val icon: String = "",
    val fixed: String = "",
) {
    val isSelectable: Boolean
        get() = isSelector ||
            type.equals("URLTest", ignoreCase = true) ||
            type.equals("Fallback", ignoreCase = true)

    val isSelector: Boolean get() = type.equals("Selector", ignoreCase = true)

    val isFixed: Boolean get() = fixed.isNotEmpty()
}

@Immutable
data class ProxyUiState(
    val groups: ImmutableList<ProxyGroupUi> = persistentListOf(),
    val testingGroups: ImmutableSet<String> = persistentSetOf(),
    val testingNodes: ImmutableSet<String> = persistentSetOf(),
    val error: String = "",
    val mode: String = "",
    val isProxyRunning: Boolean = false,
    val isTestingAllDelays: Boolean = false,
)

class ProxyViewModel(
    private val proxySelections: ProxySelectionStore? = null,
    private val getActiveUuid: () -> String? = { null },
    private val storage: PlatformStorage? = null,
    private val offlineRepository: OfflineProxyRepository? = null,
    private val activeSubscriptionId: StateFlow<String?>? = null,
    autoDelayRuns: Flow<MihomoRepository> = emptyFlow(),
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProxyUiState())
    val uiState: StateFlow<ProxyUiState> = _uiState.asStateFlow()

    private val _sortOption = MutableStateFlow(loadInitialSortOption())
    val sortOption: StateFlow<Int> = _sortOption.asStateFlow()

    private val _columnCount = MutableStateFlow(loadInitialColumnCount())
    val columnCount: StateFlow<Int> = _columnCount.asStateFlow()

    private val _nodeSize = MutableStateFlow(loadInitialNodeSize())
    val nodeSize: StateFlow<Int> = _nodeSize.asStateFlow()

    private val _groupTabs = MutableStateFlow(
        storage?.getString(StorageKeys.PROXY_GROUP_TABS, "true") != "false",
    )
    val groupTabs: StateFlow<Boolean> = _groupTabs.asStateFlow()

    private val _selectedGroupName = MutableStateFlow(
        storage?.getString(StorageKeys.PROXY_SELECTED_GROUP, "").orEmpty(),
    )
    val selectedGroupName: StateFlow<String> = _selectedGroupName.asStateFlow()

    private val _expandedGroups = MutableStateFlow(persistentSetOf<String>())
    val expandedGroups: StateFlow<ImmutableSet<String>> = _expandedGroups.asStateFlow()

    fun toggleExpandedGroup(name: String) {
        val current = _expandedGroups.value
        _expandedGroups.value = if (name in current) current.removing(name) else current.adding(name)
    }

    // 宽屏外壳切换会重新创建页面，滚动位置不能只依赖组合树内的保存键。
    private val scrollPositions = mutableMapOf<String, Pair<Int, Int>>()

    fun scrollPosition(key: String): Pair<Int, Int> = scrollPositions[key] ?: (0 to 0)

    fun updateScrollPosition(key: String, index: Int, offset: Int) {
        scrollPositions[key] = index to offset
    }

    fun updateSelectedGroupName(name: String) {
        _selectedGroupName.value = name
        storage?.putString(StorageKeys.PROXY_SELECTED_GROUP, name)
    }

    fun updateGroupTabs(enabled: Boolean) {
        _groupTabs.value = enabled
        storage?.putString(StorageKeys.PROXY_GROUP_TABS, enabled.toString())
    }

    private val _showGlobalGroup = MutableStateFlow(loadInitialShowGlobalGroup())
    val showGlobalGroup: StateFlow<Boolean> = _showGlobalGroup.asStateFlow()

    private val _hideUnavailableNodes = MutableStateFlow(loadInitialHideUnavailable())
    val hideUnavailableNodes: StateFlow<Boolean> = _hideUnavailableNodes.asStateFlow()

    private class Session(
        val repository: MihomoRepository?,
        val uuid: String?,
        val scope: CoroutineScope,
    ) {
        var selectionsRestored = false
        var displayMode = ""
        var offlineData: OfflineProxyData? = null
        val offlineDelays = mutableMapOf<String, Int>()
        val activeOfflineTests = mutableMapOf<String, Int>()
        val groupTests = mutableMapOf<String, Int>()
        val isOffline: Boolean get() = repository == null
    }

    private var session: Session? = null
    private var loadJob: Job? = null
    private val stateMutex = Mutex()

    private var nodeProviderMap: Map<String, String> = emptyMap()

    fun updateSortOption(option: Int) {
        _sortOption.value = option
        storage?.putString(StorageKeys.PROXY_NODE_SORT_OPTION, option.toString())
    }

    private fun loadInitialSortOption(): Int {
        val stored = storage?.getString(StorageKeys.PROXY_NODE_SORT_OPTION, "0")?.toIntOrNull() ?: 0
        return stored - stored % 2
    }

    fun updateColumnCount(count: Int) {
        val columns = count.coerceIn(1, 3)
        _columnCount.value = columns
        storage?.putString(StorageKeys.PROXY_NODE_COLUMNS, columns.toString())
    }

    private fun loadInitialColumnCount(): Int {
        val stored = storage?.getString(StorageKeys.PROXY_NODE_COLUMNS, "0")?.toIntOrNull()
        if (stored != null && stored in 1..3) return stored
        return if (storage?.getString(StorageKeys.PROXY_NODE_SINGLE_COLUMN, "false") == "true") 1 else 2
    }

    fun updateNodeSize(size: Int) {
        val value = size.coerceIn(0, 2)
        _nodeSize.value = value
        storage?.putString(StorageKeys.PROXY_NODE_SIZE, value.toString())
    }

    private fun loadInitialNodeSize(): Int =
        storage?.getString(StorageKeys.PROXY_NODE_SIZE, "1")?.toIntOrNull()?.coerceIn(0, 2) ?: 1

    fun updateHideUnavailableNodes(enabled: Boolean) {
        _hideUnavailableNodes.value = enabled
        storage?.putString(StorageKeys.PROXY_HIDE_UNAVAILABLE_NODES, if (enabled) "true" else "false")
    }

    private fun loadInitialHideUnavailable(): Boolean =
        storage?.getString(StorageKeys.PROXY_HIDE_UNAVAILABLE_NODES, "false") == "true"

    fun updateShowGlobalGroup(enabled: Boolean) {
        _showGlobalGroup.value = enabled
        storage?.putString(StorageKeys.PROXY_SHOW_GLOBAL_GROUP, if (enabled) "true" else "false")
    }

    private fun loadInitialShowGlobalGroup(): Boolean =
        storage?.getString(StorageKeys.PROXY_SHOW_GLOBAL_GROUP, "true") != "false"

    init {
        viewModelScope.launch {
            autoDelayRuns.collect { repo -> if (session?.repository === repo) loadProxies() }
        }
        // 停止态没有仓库变化可依赖，当前订阅切换时要自己重建离线会话。
        viewModelScope.launch {
            activeSubscriptionId?.drop(1)?.collect { uuid ->
                val current = session ?: return@collect
                if (!current.isOffline || current.uuid == uuid) return@collect
                current.scope.cancel()
                session = Session(null, uuid, newSessionScope())
                loadJob = null
                nodeProviderMap = emptyMap()
                _uiState.value = ProxyUiState(isProxyRunning = false)
                if (uuid != null) loadProxies()
            }
        }
    }

    private fun newSessionScope(): CoroutineScope =
        CoroutineScope(viewModelScope.coroutineContext + SupervisorJob(viewModelScope.coroutineContext[Job]))

    // 每个内核实例独占任务父节点；切换时取消请求和排队操作，响应再核对订阅归属。
    fun setRepository(repo: MihomoRepository?) {
        val uuid = getActiveUuid()
        if (session != null && session?.repository === repo && session?.uuid == uuid) return
        session?.scope?.cancel()
        session = Session(repo, uuid, newSessionScope())
        loadJob = null
        nodeProviderMap = emptyMap()
        _uiState.value = ProxyUiState(isProxyRunning = repo != null)
        val current = session ?: return
        if (repo != null) {
            current.scope.launch {
                var previousResults = emptyMap<String, TestedDelay>()
                combine(repo.testingNodes, repo.delayResults) { nodes, results -> nodes to results }
                    .collect { (nodes, results) ->
                        if (isCurrent(current)) {
                            val changedResults = results.filter { (name, delay) -> previousResults[name] != delay }
                            _uiState.value = _uiState.value.copy(
                                testingNodes = nodes.toPersistentSet(),
                                groups = _uiState.value.groups.map { it.withLiveDelays(changedResults) }.toPersistentList(),
                            )
                        }
                        previousResults = results
                    }
            }
        }
        if (repo != null || uuid != null) loadProxies()
    }

    fun updateDisplayMode(mode: String) {
        val current = session ?: return
        if (!current.isOffline) return
        val normalized = mode.lowercase()
        if (current.displayMode == normalized) return
        current.displayMode = normalized
        _uiState.value = _uiState.value.copy(
            mode = normalized,
            groups = arrangeGroups(_uiState.value.groups, normalized),
        )
    }

    fun loadProxies() {
        val current = session ?: return

        loadJob?.cancel()
        loadJob = current.scope.launch {
            // 刷新、恢复、选择与解除固定共用一把锁，快照发布和内核写入保持同一顺序。
            stateMutex.withLock {
                if (!isCurrent(current)) return@withLock
                _uiState.value = _uiState.value.copy(error = "")
                if (current.isOffline) loadOfflineProxies(current) else loadRuntimeProxies(current)
            }
        }
    }

    private suspend fun loadRuntimeProxies(current: Session) = coroutineScope {
        val repository = current.repository ?: return@coroutineScope
        val delayRevision = repository.delayResults.value.values.maxOfOrNull { it.revision } ?: 0L
        val groupsDeferred = async { repository.getGroups() }
        val proxiesDeferred = async { repository.getProxies() }
        val providersDeferred = async { repository.getProviders() }
        val configDeferred = async { repository.getConfig() }
        val groupsResult = groupsDeferred.await()
        val proxiesResult = proxiesDeferred.await()
        val providersResult = providersDeferred.await()
        val mode = configDeferred.await().getOrNull()?.mode?.lowercase().orEmpty()
        if (!isCurrent(current)) return@coroutineScope

        groupsResult.onSuccess { groupsResponse ->
            // 数千节点的延迟/类型映射在主线程要十余毫秒，正好落在切页动画期间；
            // 入参与产物都是不可变结构，搬到 Default 后只有 nodeProviderMap 要回主线程赋值。
            val mapped = withContext(Dispatchers.Default) {
                buildGroups(
                    groups = groupsResponse.proxies,
                    proxies = proxiesResult.getOrNull()?.proxies ?: emptyMap(),
                    providers = providersResult.getOrNull()?.providers ?: emptyMap(),
                    mode = mode,
                )
            }
            if (!isCurrent(current)) return@onSuccess
            // 刷新开始后的测量覆盖旧快照，其余延迟采用内核当前的健康检查记录。
            val recentDelays = repository.delayResults.value.filterValues { it.revision > delayRevision }
            val groups = mapped.first.map { it.withLiveDelays(recentDelays) }.toPersistentList()
            nodeProviderMap = mapped.second
            _uiState.value = _uiState.value.copy(groups = groups, mode = mode)
            if (!current.selectionsRestored) {
                current.selectionsRestored = restoreSelections(current, groups)
            }
        }.onFailure {
            AppLogger.warn(TAG, "loadProxies failed", it)
            _uiState.value = _uiState.value.copy(error = it.describe())
        }
    }

    private suspend fun loadOfflineProxies(current: Session) {
        val uuid = current.uuid
        val repository = offlineRepository
        if (uuid == null || repository == null) {
            if (isCurrent(current)) _uiState.value = _uiState.value.copy(groups = persistentListOf())
            return
        }
        repository.load(uuid)
            .onSuccess { data ->
                if (!isCurrent(current)) return@onSuccess
                current.offlineData = data
                val extraDelays = current.offlineDelays.toMap()
                val mapped = withContext(Dispatchers.Default) {
                    buildGroups(
                        groups = data.snapshot.groups,
                        proxies = data.snapshot.proxies,
                        providers = data.snapshot.providers,
                        mode = data.snapshot.mode,
                        extraDelays = extraDelays,
                    )
                }
                if (!isCurrent(current)) return@onSuccess
                nodeProviderMap = mapped.second
                val groups = applySelections(current, mapped.first)
                val mode = current.displayMode.ifEmpty { data.snapshot.mode }
                _uiState.value = _uiState.value.copy(
                    groups = arrangeGroups(groups, mode),
                    mode = mode,
                )
            }
            .onFailure {
                AppLogger.warn(TAG, "loadOfflineProxies failed", it)
                _uiState.value = _uiState.value.copy(error = it.describe())
            }
    }

    private fun buildGroups(
        groups: List<ProxyNode>,
        proxies: Map<String, ProxyNode>,
        providers: Map<String, ProviderInfo>,
        mode: String,
        extraDelays: Map<String, Int> = emptyMap(),
    ): Pair<ImmutableList<ProxyGroupUi>, Map<String, String>> {
        val allProxies = proxies.toMutableMap()
        val providerOf = mutableMapOf<String, String>()
        providers.forEach { (providerName, provider) ->
            provider.proxies.forEach { node ->
                if (node.name !in proxies) {
                    allProxies.putIfAbsent(node.name, node)
                    providerOf.putIfAbsent(node.name, providerName)
                }
            }
        }

        val globalGroup = groups.firstOrNull { it.name == GLOBAL_GROUP }
        val orderMap = globalGroup?.all
            ?.mapIndexed { index, name -> name to index }
            ?.toMap() ?: emptyMap()

        val orderedGroups = groups
            .filter { it.name != GLOBAL_GROUP }
            .sortedBy { orderMap[it.name] ?: Int.MAX_VALUE }
        val arrangedGroups = when {
            globalGroup == null -> orderedGroups
            mode == MODE_GLOBAL -> listOf(globalGroup) + orderedGroups
            else -> orderedGroups + globalGroup
        }

        val mapped = arrangedGroups
            .map { node ->
                val delays = mutableMapOf<String, Int>()
                val nodeTypes = mutableMapOf<String, String>()
                node.all.forEach { proxyName ->
                    val proxy = allProxies[proxyName]
                    val lastDelay = proxy?.history?.lastOrNull()?.delay
                    if (lastDelay != null && lastDelay > 0) {
                        delays[proxyName] = lastDelay
                    } else if (lastDelay == 0) {
                        delays[proxyName] = -1
                    } else if (proxy != null && proxy.now.isNotEmpty()) {
                        val nowProxy = allProxies[proxy.now]
                        val nowDelay = nowProxy?.history?.lastOrNull()?.delay
                        if (nowDelay != null && nowDelay > 0) {
                            delays[proxyName] = nowDelay
                        } else if (nowDelay == 0) {
                            delays[proxyName] = -1
                        }
                    }
                    extraDelays[proxyName]?.let { delays[proxyName] = it }
                    if (proxy != null && proxy.type.isNotEmpty()) {
                        nodeTypes[proxyName] = proxy.type
                    }
                }
                ProxyGroupUi(
                    name = node.name,
                    type = node.type,
                    now = node.now,
                    all = node.all.toPersistentList(),
                    delays = delays.toPersistentMap(),
                    nodeTypes = nodeTypes.toPersistentMap(),
                    icon = node.icon,
                    fixed = node.fixed,
                )
            }
            .toPersistentList()
        return mapped to providerOf
    }

    private fun arrangeGroups(groups: ImmutableList<ProxyGroupUi>, mode: String): ImmutableList<ProxyGroupUi> {
        val global = groups.firstOrNull { it.name == GLOBAL_GROUP } ?: return groups
        val rest = groups.filter { it.name != GLOBAL_GROUP }
        return (if (mode == MODE_GLOBAL) listOf(global) + rest else rest + global).toPersistentList()
    }

    private fun applySelections(current: Session, groups: ImmutableList<ProxyGroupUi>): ImmutableList<ProxyGroupUi> {
        val uuid = current.uuid ?: return groups
        val selectionMap = proxySelections?.selections(uuid).orEmpty()
        if (selectionMap.isEmpty()) return groups
        return groups.map { group ->
            val saved = selectionMap[group.name]?.takeIf { it in group.all }
            when {
                saved == null || !group.isSelectable -> group
                group.isSelector -> group.copy(now = saved)
                else -> group.copy(now = saved, fixed = saved)
            }
        }.toPersistentList()
    }

    fun selectProxy(group: String, proxy: String) {
        val current = session ?: return
        current.scope.launch {
            stateMutex.withLock {
                if (!isCurrent(current)) return@withLock
                val target = groupOf(group) ?: return@withLock
                if (!target.isSelectable) return@withLock
                if (proxy !in target.all) return@withLock
                _uiState.value = _uiState.value.copy(error = "")
                if (current.isOffline) {
                    _uiState.value = _uiState.value.copy(
                        groups = _uiState.value.groups
                            .map {
                                when {
                                    it.name != group -> it
                                    it.isSelector -> it.copy(now = proxy)
                                    else -> it.copy(now = proxy, fixed = proxy)
                                }
                            }
                            .toPersistentList(),
                    )
                    current.uuid?.let { proxySelections?.select(it, group, proxy) }
                    return@withLock
                }
                val result = current.repository?.selectProxy(group, proxy) ?: return@withLock
                if (!isCurrent(current)) return@withLock
                result.onSuccess {
                    _uiState.value = _uiState.value.copy(
                        groups = _uiState.value.groups
                            .map {
                                when {
                                    it.name != group -> it
                                    it.isSelector -> it.copy(now = proxy)
                                    else -> it.copy(now = proxy, fixed = proxy)
                                }
                            }
                            .toPersistentList(),
                    )
                    current.uuid?.let { proxySelections?.select(it, group, proxy) }
                }.onFailure {
                    AppLogger.warn(TAG, "selectProxy failed", it)
                    _uiState.value = _uiState.value.copy(error = it.describe())
                }
            }
        }
    }

    // 记录的选择也要一并删掉，它是恢复选择的数据来源，留着下次连接时会把刚解除的固定又推回去。
    fun unfixProxy(group: String) {
        val current = session ?: return
        current.scope.launch {
            stateMutex.withLock {
                if (!isCurrent(current)) return@withLock
                _uiState.value = _uiState.value.copy(error = "")
                if (current.isOffline) {
                    current.uuid?.let { proxySelections?.clear(it, group) }
                    loadOfflineProxies(current)
                    return@withLock
                }
                val result = current.repository?.unfixProxy(group) ?: return@withLock
                if (!isCurrent(current)) return@withLock
                result.onSuccess {
                    current.uuid?.let { proxySelections?.clear(it, group) }
                    loadRuntimeProxies(current)
                }.onFailure {
                    AppLogger.warn(TAG, "unfixProxy failed", it)
                    _uiState.value = _uiState.value.copy(error = it.describe())
                }
            }
        }
    }

    fun testGroupDelay(group: String) {
        val current = session ?: return
        if (!isCurrent(current)) return
        if (group in _uiState.value.testingGroups) return
        val nodes = groupOf(group)?.all ?: return
        if (nodes.isEmpty()) return
        val testUrl = currentDelayTestUrl()
        updateTestingGroups(current, listOf(group), testing = true)

        current.scope.launch {
            try {
                if (current.isOffline) {
                    runOfflineTest(current, nodes, testUrl)
                } else {
                    current.repository?.testDelays(nodes, nodeProviderMap, testUrl)
                    if (!isCurrent(current)) return@launch
                    loadProxies()
                }
            } finally {
                updateTestingGroups(current, listOf(group), testing = false)
            }
        }
    }

    fun testAllDelays() {
        val current = session ?: return
        if (!isCurrent(current)) return
        if (_uiState.value.isTestingAllDelays) return
        val groups = _uiState.value.groups
        val nodes = groups.flatMapTo(LinkedHashSet()) { it.all }
        if (nodes.isEmpty()) return
        val names = groups.map { it.name }
        val testUrl = currentDelayTestUrl()
        updateTestingGroups(current, names, testing = true)
        _uiState.value = _uiState.value.copy(isTestingAllDelays = true)
        current.scope.launch {
            try {
                if (current.isOffline) {
                    runOfflineTest(current, nodes, testUrl)
                } else {
                    val alreadyTesting = current.repository?.testingNodes?.value.orEmpty()
                    current.repository?.testDelays(nodes.filterNot { it in alreadyTesting }, nodeProviderMap, testUrl)
                    if (!isCurrent(current)) return@launch
                    loadProxies()
                }
            } finally {
                updateTestingGroups(current, names, testing = false)
                if (isCurrent(current)) _uiState.value = _uiState.value.copy(isTestingAllDelays = false)
            }
        }
    }

    private suspend fun runOfflineTest(current: Session, nodes: Collection<String>, testUrl: String) {
        val data = current.offlineData ?: return
        val repository = offlineRepository ?: return
        val names = nodes.distinct()
        if (names.isEmpty()) return
        updateOfflineTestingNodes(current, names, testing = true)
        try {
            repository.testDelays(data, names, testUrl)
                .onSuccess { delays ->
                    if (!isCurrent(current)) return@onSuccess
                    current.offlineDelays.putAll(delays)
                    _uiState.value = _uiState.value.copy(
                        groups = _uiState.value.groups.map { it.withDelays(delays) }.toPersistentList(),
                    )
                }
                .onFailure {
                    AppLogger.warn(TAG, "offline delay test failed", it)
                    if (isCurrent(current)) {
                        _uiState.value = _uiState.value.copy(error = it.describe())
                    }
                }
        } finally {
            updateOfflineTestingNodes(current, names, testing = false)
        }
    }

    private fun updateOfflineTestingNodes(current: Session, nodes: Collection<String>, testing: Boolean) {
        if (!isCurrent(current)) return
        nodes.forEach { name ->
            val count = (current.activeOfflineTests[name] ?: 0) + if (testing) 1 else -1
            if (count > 0) current.activeOfflineTests[name] = count else current.activeOfflineTests.remove(name)
        }
        _uiState.value = _uiState.value.copy(testingNodes = current.activeOfflineTests.keys.toPersistentSet())
    }

    // 全量测速可以与已经开始的组测速重叠，最后一轮结束才停止组的进度显示。
    private fun updateTestingGroups(current: Session, groups: Collection<String>, testing: Boolean) {
        if (!isCurrent(current)) return
        groups.forEach { name ->
            val count = (current.groupTests[name] ?: 0) + if (testing) 1 else -1
            if (count > 0) current.groupTests[name] = count else current.groupTests.remove(name)
        }
        _uiState.value = _uiState.value.copy(testingGroups = current.groupTests.keys.toPersistentSet())
    }

    fun testNodeDelay(nodeName: String) {
        val current = session ?: return
        if (!isCurrent(current)) return
        if (nodeName in _uiState.value.testingNodes) return
        val testUrl = currentDelayTestUrl()
        if (current.isOffline) {
            current.scope.launch { runOfflineTest(current, listOf(nodeName), testUrl) }
            return
        }
        current.scope.launch {
            val provider = nodeProviderMap[nodeName]
            if (provider != null) {
                current.repository?.getProviderProxyDelay(provider, nodeName, testUrl)
            } else {
                current.repository?.getProxyDelay(nodeName, testUrl)
            }
            if (!isCurrent(current)) return@launch
            loadProxies()
        }
    }

    // 设置页写入后立即生效：每次点击测速都重新读取，不能只在 ViewModel 创建时缓存。
    private fun currentDelayTestUrl(): String =
        DelayTestUrl.normalize(storage?.getString(StorageKeys.DELAY_TEST_URL, DelayTestUrl.DEFAULT))

    private fun groupOf(name: String): ProxyGroupUi? =
        _uiState.value.groups.firstOrNull { it.name == name }

    private fun ProxyGroupUi.withLiveDelays(results: Map<String, TestedDelay>): ProxyGroupUi {
        if (results.isEmpty()) return this
        val delays = this.delays.toPersistentMap().builder()
        all.forEach { name -> results[name]?.let { delays[name] = it.delay } }
        return copy(delays = delays.build())
    }

    private fun ProxyGroupUi.withDelays(results: Map<String, Int>): ProxyGroupUi {
        if (results.isEmpty()) return this
        val delays = this.delays.toPersistentMap().builder()
        all.forEach { name -> results[name]?.let { delays[name] = it } }
        return copy(delays = delays.build())
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = "")
    }

    private fun isCurrent(current: Session): Boolean =
        session === current && getActiveUuid() == current.uuid

    private suspend fun restoreSelections(
        current: Session,
        groups: ImmutableList<ProxyGroupUi>,
    ): Boolean {
        val uuid = current.uuid ?: return true
        val selectionMap = proxySelections?.selections(uuid).orEmpty()
        if (selectionMap.isEmpty()) return true

        val updatedGroups = groups.toMutableList()
        var restored = true

        for ((index, group) in groups.withIndex()) {
            if (!isCurrent(current)) return false
            if (!group.isSelectable) continue
            val saved = selectionMap[group.name] ?: continue
            if (saved !in group.all) continue
            if (saved == (if (group.isSelector) group.now else group.fixed)) continue

            val result = current.repository?.selectProxy(group.name, saved) ?: return false
            if (!isCurrent(current)) return false
            result.onSuccess {
                updatedGroups[index] = if (group.isSelector) {
                    group.copy(now = saved)
                } else {
                    group.copy(now = saved, fixed = saved)
                }
            }.onFailure {
                restored = false
                AppLogger.warn(TAG, "restoreSelections failed", it)
                _uiState.value = _uiState.value.copy(error = it.describe())
            }
        }

        _uiState.value = _uiState.value.copy(groups = updatedGroups.toPersistentList())
        return restored
    }

    companion object {
        const val GLOBAL_GROUP = "GLOBAL"
        const val MODE_GLOBAL = "global"
        const val MODE_DIRECT = "direct"
        private const val TAG = "ProxyViewModel"
    }
}
