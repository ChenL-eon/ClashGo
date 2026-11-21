// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：icons/settings-3-fill.svg
package com.stelliberty.android.ui.icon

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

internal val MingCuteSettings3Fill: ImageVector by lazy {
    ImageVector.Builder(
        name = "Settings3Fill",
        defaultWidth = 24.dp,
        defaultHeight = 24.dp,
        viewportWidth = 24f,
        viewportHeight = 24f,
        autoMirror = false,
    ).apply {
        addPath(
            pathData = PathParser().parsePathString("M14.035 2.808c.369-.266.89-.39 1.402-.203a10 10 0 0 1 2.981 1.725c.417.35.57.86.524 1.313c-.075.752.058 1.48.42 2.106c.361.627.924 1.106 1.615 1.417c.414.187.782.576.875 1.113a10 10 0 0 1 0 3.44a1.51 1.51 0 0 1-.875 1.114c-.69.311-1.254.79-1.616 1.416c-.361.627-.494 1.354-.419 2.106c.046.452-.107.964-.524 1.313a10 10 0 0 1-2.981 1.724a1.51 1.51 0 0 1-1.402-.202c-.614-.442-1.31-.691-2.035-.691c-.724 0-1.42.249-2.035.691a1.51 1.51 0 0 1-1.402.202a10 10 0 0 1-2.981-1.724c-.417-.35-.57-.86-.524-1.313c.075-.752-.058-1.48-.42-2.106c-.361-.627-.925-1.105-1.615-1.416a1.51 1.51 0 0 1-.876-1.114a10 10 0 0 1 0-3.44c.094-.537.462-.926.876-1.113c.69-.311 1.254-.79 1.616-1.417c.361-.627.494-1.354.419-2.106a1.51 1.51 0 0 1 .524-1.313a10 10 0 0 1 2.981-1.725a1.51 1.51 0 0 1 1.402.203c.614.442 1.31.691 2.035.691c.724 0 1.42-.249 2.035-.691M12 8.999a3 3 0 1 0 0 6a3 3 0 0 0 0-6").toNodes(),
            pathFillType = PathFillType.NonZero,
            fill = SolidColor(Color.Black),
        )
    }.build()
}
