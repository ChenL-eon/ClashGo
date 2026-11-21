package com.clashgo.android.ui.screen.settings

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.clashgo.android.ui.component.AdaptiveTopAppBar
import com.clashgo.android.ui.component.BackButton
import com.clashgo.android.ui.component.LocalPreferenceHorizontalPadding
import com.clashgo.android.ui.component.PreferenceLayout
import com.clashgo.android.ui.component.pageBottomPadding
import com.clashgo.android.ui.component.blur.BlurredBar
import com.clashgo.android.ui.component.blur.rememberBlurBackdrop
import com.clashgo.android.ui.util.WideContentBox
import com.clashgo.android.ui.util.horizontalCutoutPadding
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuix.kmp.basic.Scaffold
import top.yukonga.miuix.kmp.blur.layerBackdrop
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.utils.overScrollVertical
import top.yukonga.miuix.kmp.utils.scrollEndHaptic

// 设置二级页骨架：带返回的毛玻璃顶栏 + 列表，末尾自带导航栏底距。
@Composable
internal fun SettingsSubPage(
    title: String,
    onBack: () -> Unit,
    topSpacing: Dp = 0.dp,
    content: LazyListScope.() -> Unit,
) {
    val scrollBehavior = MiuixScrollBehavior()
    val backdrop = rememberBlurBackdrop()
    val blurActive = backdrop != null
    val barColor = if (blurActive) Color.Transparent else MiuixTheme.colorScheme.surface

    Scaffold(
        topBar = {
            BlurredBar(backdrop = backdrop, blurActive = blurActive) {
                AdaptiveTopAppBar(
                    title = title,
                    color = barColor,
                    scrollBehavior = scrollBehavior,
                    navigationIcon = { BackButton(onBack) },
                )
            }
        },
    ) { innerPadding ->
        val bottomPadding = pageBottomPadding(innerPadding.calculateBottomPadding())
        CompositionLocalProvider(LocalPreferenceHorizontalPadding provides PreferenceLayout.SubPageHorizontalPadding) {
            WideContentBox { sidePadding ->
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .horizontalCutoutPadding()
                        .then(if (backdrop != null) Modifier.layerBackdrop(backdrop) else Modifier)
                        .scrollEndHaptic()
                        .overScrollVertical()
                        .nestedScroll(scrollBehavior.nestedScrollConnection),
                    contentPadding = PaddingValues(
                        top = innerPadding.calculateTopPadding() + topSpacing,
                        start = sidePadding,
                        end = sidePadding,
                    ),
                ) {
                    content()
                    item { Spacer(Modifier.height(bottomPadding)) }
                }
            }
        }
    }
}
