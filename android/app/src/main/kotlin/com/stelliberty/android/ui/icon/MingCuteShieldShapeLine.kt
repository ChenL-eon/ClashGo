// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/shield-shape-line.svg
package com.stelliberty.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteShieldShapeLine: ImageVector by lazy {
    ImageVector.Builder(
        name = "ShieldShapeLine",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("m11.649 3.132l-7 2.625A1 1 0 0 0 4 6.693v5.363a8 8 0 0 0 4.422 7.155l3.354 1.677a.5.5 0 0 0 .448 0l3.354-1.677A8 8 0 0 0 20 12.056V6.693a1 1 0 0 0-.649-.936l-7-2.625a1 1 0 0 0-.702 0Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Miter,
        )
    }.build()
}
