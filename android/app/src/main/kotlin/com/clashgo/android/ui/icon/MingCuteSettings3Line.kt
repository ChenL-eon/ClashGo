// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/settings-3-line.svg
package com.clashgo.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteSettings3Line: ImageVector by lazy {
    ImageVector.Builder(
        name = "Settings3Line",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M17.947 5.545a.51.51 0 0 0-.171-.447a9 9 0 0 0-2.684-1.551a.51.51 0 0 0-.473.075c-.761.548-1.658.88-2.619.88c-.96 0-1.858-.332-2.62-.88a.51.51 0 0 0-.473-.075a9 9 0 0 0-2.683 1.552a.51.51 0 0 0-.171.446c.093.933-.068 1.875-.548 2.706c-.48.832-1.215 1.443-2.07 1.828a.51.51 0 0 0-.302.373a9 9 0 0 0 0 3.098a.51.51 0 0 0 .301.373c.856.386 1.59.997 2.07 1.828s.642 1.773.549 2.706a.51.51 0 0 0 .171.447a9 9 0 0 0 2.683 1.552c.16.058.336.024.474-.075c.761-.549 1.659-.88 2.619-.88s1.858.331 2.62.88a.51.51 0 0 0 .473.075a9 9 0 0 0 2.683-1.552a.51.51 0 0 0 .171-.447c-.093-.933.068-1.875.548-2.706s1.215-1.442 2.07-1.828a.51.51 0 0 0 .302-.373a9 9 0 0 0 0-3.098a.51.51 0 0 0-.301-.373c-.856-.385-1.59-.996-2.07-1.828c-.48-.83-.642-1.773-.549-2.706Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Round,
        )
        addPath(
            pathData = PathParser().parsePathString("M15 12a3 3 0 1 1-6 0a3 3 0 0 1 6 0Z").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = null,
            stroke = SolidColor(Color.Black),
            strokeLineWidth = 2.0f,
            strokeLineCap = StrokeCap.Butt,
            strokeLineJoin = StrokeJoin.Round,
        )
    }.build()
}
