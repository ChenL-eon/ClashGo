// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/refresh-2-line.svg
package com.clashgo.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteRefresh2Line: ImageVector by lazy {
    ImageVector.Builder(
        name = "Refresh2Line",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M3.811 8.264A9 9 0 0 1 14.33 3.307a9 9 0 0 1 6.672 8.622c0 .08-.088.126-.154.082l-2.678-1.804c-.091-.062-.03-.205.078-.181L20 10.41m.189 5.327c-1.789 3.932-6.208 6.112-10.519 4.956a9 9 0 0 1-6.672-8.622c0-.08.088-.126.154-.082l2.678 1.805c.091.061.03.204-.078.18L4 13.59").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
    }.build()
}
