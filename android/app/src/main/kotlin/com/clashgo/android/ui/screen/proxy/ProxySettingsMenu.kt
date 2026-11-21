package com.clashgo.android.ui.screen.proxy

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import com.clashgo.android.BuildConfig
import com.clashgo.android.R
import com.clashgo.android.ui.icon.AppIcons
import com.clashgo.android.ui.util.TestTags
import top.yukonga.miuix.kmp.basic.DropdownEntry
import top.yukonga.miuix.kmp.basic.DropdownItem
import top.yukonga.miuix.kmp.basic.Icon
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.window.WindowCascadingListPopup

private val MODE_OPTIONS = listOf("rule" to "Rule", "global" to "Global", "direct" to "Direct")

private fun menuIcon(
    icon: ImageVector,
    enabled: Boolean = true,
): @Composable (Modifier) -> Unit = { modifier ->
    Box(modifier, contentAlignment = Alignment.Center) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = if (enabled) MiuixTheme.colorScheme.onSurface
            else MiuixTheme.colorScheme.disabledOnSecondaryVariant,
        )
    }
}

@Composable
internal fun ProxySettingsMenu(
    show: Boolean,
    onDismissRequest: () -> Unit,
    mode: String,
    onModeChange: (String) -> Unit,
    groupTabs: Boolean,
    onGroupTabsChange: (Boolean) -> Unit,
    columnCount: Int,
    onColumnCountChange: (Int) -> Unit,
    nodeSize: Int,
    onNodeSizeChange: (Int) -> Unit,
    onScrollToSelected: () -> Unit,
    hideUnavailable: Boolean,
    onHideUnavailableChange: (Boolean) -> Unit,
    showGlobalGroup: Boolean,
    onShowGlobalGroupChange: (Boolean) -> Unit,
    sortOption: Int,
    onSortOptionChange: (Int) -> Unit,
) {
    val modeIndex = MODE_OPTIONS.indexOfFirst { it.first == mode.lowercase() }.coerceAtLeast(0)
    val sortKey = (sortOption / 2).coerceIn(0, 2)
    val globalMode = mode.equals("global", ignoreCase = true)
    val sortChoices = listOf(
        0 to stringResource(R.string.proxy_sort_default),
        2 to stringResource(R.string.proxy_sort_delay),
        1 to stringResource(R.string.proxy_sort_name),
    )
    val layoutChoices = listOf(
        1 to stringResource(R.string.proxy_layout_compact),
        2 to stringResource(R.string.proxy_layout_standard),
        3 to stringResource(R.string.proxy_layout_loose),
    )
    val sizeChoices = listOf(
        0 to stringResource(R.string.proxy_size_compact),
        1 to stringResource(R.string.proxy_size_standard),
        2 to stringResource(R.string.proxy_size_loose),
    )
    val entries = listOf(
        DropdownEntry(
            items = listOf(
                DropdownItem(
                    text = stringResource(R.string.proxy_scroll_to_selected),
                    icon = menuIcon(AppIcons.BlurOn),
                    onClick = onScrollToSelected,
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_style_title),
                    icon = menuIcon(AppIcons.Layout),
                    children = listOf(
                        true to stringResource(R.string.proxy_style_tabs),
                        false to stringResource(R.string.proxy_style_list),
                    ).map { (tabs, label) ->
                        DropdownItem(
                            text = label,
                            selected = groupTabs == tabs,
                            onClick = { if (groupTabs != tabs) onGroupTabsChange(tabs) },
                        )
                    },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_sort_title),
                    icon = menuIcon(AppIcons.Sort),
                    children = sortChoices.map { (key, label) ->
                        DropdownItem(
                            text = label,
                            selected = sortKey == key,
                            onClick = { if (sortKey != key) onSortOptionChange(key * 2) },
                        )
                    },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_layout_title),
                    icon = menuIcon(AppIcons.Layers),
                    children = layoutChoices.map { (columns, label) ->
                        DropdownItem(
                            text = label,
                            selected = columnCount == columns,
                            onClick = { if (columnCount != columns) onColumnCountChange(columns) },
                        )
                    },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_size_title),
                    icon = menuIcon(AppIcons.Appearance),
                    children = sizeChoices.map { (size, label) ->
                        DropdownItem(
                            text = label,
                            selected = nodeSize == size,
                            onClick = { if (nodeSize != size) onNodeSizeChange(size) },
                        )
                    },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_hide_timeout),
                    icon = menuIcon(AppIcons.DarkMode),
                    selected = hideUnavailable,
                    onClick = { onHideUnavailableChange(!hideUnavailable) },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_mode),
                    summary = MODE_OPTIONS[modeIndex].second,
                    icon = menuIcon(AppIcons.Route),
                    children = MODE_OPTIONS.mapIndexed { index, (value, label) ->
                        DropdownItem(
                            text = label,
                            selected = modeIndex == index,
                            onClick = { if (modeIndex != index) onModeChange(value) },
                        )
                    },
                ),
                DropdownItem(
                    text = stringResource(R.string.proxy_show_global_group),
                    icon = menuIcon(AppIcons.Global, !globalMode),
                    selected = showGlobalGroup || globalMode,
                    enabled = !globalMode,
                    onClick = { onShowGlobalGroupChange(!showGlobalGroup) },
                ),
            ),
        ),
    )
    WindowCascadingListPopup(
        show = show,
        entries = entries,
        onDismissRequest = onDismissRequest,
        popupModifier = Modifier
            .semantics { testTagsAsResourceId = BuildConfig.DEBUG }
            .testTag(TestTags.Proxy.SETTINGS_MENU),
    )
}
