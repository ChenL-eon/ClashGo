// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/layout-sidebar-line.svg
package com.stelliberty.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteLayoutSidebarLine: ImageVector by lazy {
    ImageVector.Builder(
        name = "LayoutSidebarLine",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M6,4.5 H18 A3,3 0 0,1 21,7.5 V16.5 A3,3 0 0,1 18,19.5 H6 A3,3 0 0,1 3,16.5 V7.5 A3,3 0 0,1 6,4.5 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
        addPath(
            pathData = PathParser().parsePathString("M9.5 4.5v15M12.5 9h4.5M12.5 13h4.5").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
