// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/more-1-line.svg
package com.stelliberty.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteMore1Line: ImageVector by lazy {
    ImageVector.Builder(
        name = "More1Line",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M12.5 12a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0m6 0a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0m-12 0a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = SolidColor(Color.Black),
        )
        addPath(
            pathData = PathParser().parsePathString("M12.5 12a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0Zm6 0a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0Zm-12 0a.5.5 0 1 1-1 0a.5.5 0 0 1 1 0Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
