// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/link-line.svg
package com.clashgo.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteLinkLine: ImageVector by lazy {
    ImageVector.Builder(
        name = "LinkLine",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("m11.646 5.989l-1.414-1.414a4 4 0 1 0-5.657 5.656l2.829 2.829a4 4 0 0 0 5.657 0m-.707 4.95l1.414 1.414a4 4 0 1 0 5.657-5.657l-2.829-2.828a4 4 0 0 0-5.657 0").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
