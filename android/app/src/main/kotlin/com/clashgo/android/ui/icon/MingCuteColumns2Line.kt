// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/columns-2-line.svg
package com.clashgo.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteColumns2Line: ImageVector by lazy {
    ImageVector.Builder(
        name = "Columns2Line",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M6,5 H8.5 A2.5,2.5 0 0,1 11,7.5 V16.5 A2.5,2.5 0 0,1 8.5,19 H6 A2.5,2.5 0 0,1 3.5,16.5 V7.5 A2.5,2.5 0 0,1 6,5 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
        addPath(
            pathData = PathParser().parsePathString("M15.5,5 H18 A2.5,2.5 0 0,1 20.5,7.5 V16.5 A2.5,2.5 0 0,1 18,19 H15.5 A2.5,2.5 0 0,1 13,16.5 V7.5 A2.5,2.5 0 0,1 15.5,5 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
