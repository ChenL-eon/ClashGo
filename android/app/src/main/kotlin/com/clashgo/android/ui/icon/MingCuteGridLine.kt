// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/grid-line.svg
package com.clashgo.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteGridLine: ImageVector by lazy {
    ImageVector.Builder(
        name = "GridLine",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M6,4 H8.5 A2,2 0 0,1 10.5,6 V8.5 A2,2 0 0,1 8.5,10.5 H6 A2,2 0 0,1 4,8.5 V6 A2,2 0 0,1 6,4 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
        addPath(
            pathData = PathParser().parsePathString("M15.5,4 H18 A2,2 0 0,1 20,6 V8.5 A2,2 0 0,1 18,10.5 H15.5 A2,2 0 0,1 13.5,8.5 V6 A2,2 0 0,1 15.5,4 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
        addPath(
            pathData = PathParser().parsePathString("M6,13.5 H8.5 A2,2 0 0,1 10.5,15.5 V18 A2,2 0 0,1 8.5,20 H6 A2,2 0 0,1 4,18 V15.5 A2,2 0 0,1 6,13.5 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
        addPath(
            pathData = PathParser().parsePathString("M15.5,13.5 H18 A2,2 0 0,1 20,15.5 V18 A2,2 0 0,1 18,20 H15.5 A2,2 0 0,1 13.5,18 V15.5 A2,2 0 0,1 15.5,13.5 Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
