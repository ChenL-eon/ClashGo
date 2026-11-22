#!/usr/bin/env python3
"""从 ClashGo 的 SVG 生成 Compose ImageVector。

一次性工具：改 ICONS 表后重跑，产物提交进仓库。运行时不依赖网络，也不引图标库——
只取实际用到的 SVG，避免 material-icons-extended 那种「为几个图标拖进整个库」。

用法：
    python scripts/gen_icons.py            # 增量：SVG 已缓存则不重新下载
    python scripts/gen_icons.py --force    # 强制重新下载
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_RAW = "https://raw.githubusercontent.com/ChenL-eon/ClashGo/main/assets"
SVG_CACHE = Path("build/tmp/clashgo-assets")
OUT_PACKAGE = "com.clashgo.android.ui.icon"
OUT_DIR = Path("android/app/src/main/kotlin/com/clashgo/android/ui/icon")
SVG_NS = "{http://www.w3.org/2000/svg}"

# AppIcons 属性名 → ClashGo 的 assets/icons 文件名。左侧对齐调用点语义、右侧是上游原名；
# 生成产物按右侧命名，同名 vector 可由多个语义名共用。换图标只改右侧，调用点不动。
ICONS: dict[str, str] = {
    "Add": "icons/add-line.svg",
    "ArrowRight": "icons/right-small-line.svg",
    "Back": "icons/arrow-left-line.svg",
    "Backup": "icons/upload-line.svg",
    "Check": "icons/check-line.svg",
    "ChevronRight": "icons/right-small-line.svg",
    "Close": "icons/close-line.svg",
    "Delete": "icons/delete-2-line.svg",
    "Filter": "icons/sort-alpha-line.svg",
    "File": "icons/file-line.svg",
    "Folder": "icons/folder-line.svg",
    "Global": "icons/globe-line.svg",
    "Info": "icons/information-line.svg",
    "Layers": "icons/columns-2-line.svg",
    "Layout": "icons/layout-tabs-line.svg",
    "Link": "icons/link-line.svg",
    "Locate": "icons/focus-line.svg",
    "More": "icons/more-1-line.svg",
    "MoveDown": "icons/down-small-line.svg",
    "MoveUp": "icons/up-small-line.svg",
    "Overrides": "icons/list-check-line.svg",
    "Pin": "icons/pin-line.svg",
    "QrCode": "icons/qrcode-line.svg",
    "Refresh": "icons/refresh-2-line.svg",
    "Restore": "icons/download-2-line.svg",
    "Route": "icons/transfer-line.svg",
    "Search": "icons/search-line.svg",
    "SearchCleanup": "icons/close-circle-line.svg",
    "Settings": "icons/settings-3-line.svg",
    "SingleColumn": "icons/columns-1-line.svg",
    "Sort": "icons/sort-ascending-line.svg",
    "StatusClock": "icons/clock-line.svg",
    "StatusSubscription": "icons/list-check-line.svg",
    "SubscriptionRefresh": "icons/refresh-2-line.svg",
    "TestDelay": "icons/speed-line.svg",
    "Unpin": "icons/close-circle-line.svg",
    "Wifi": "icons/wifi-line.svg",
    # 四个 Tab 各一对：未选中用线框，选中用填充
    "NavHome": "icons/home-2-line.svg",
    "NavHomeActive": "icons/home-2-fill.svg",
    "NavProxy": "icons/shield-shape-line.svg",
    "NavProxyActive": "MingCuteShieldShapeFill",
    "NavSubscription": "icons/cloud-line.svg",
    "NavSubscriptionActive": "MingCuteCloudFill",
    "NavSettings": "icons/settings-3-line.svg",
    "NavSettingsActive": "icons/settings-3-fill.svg",
    "Appearance": "icons/grid-line.svg",
    "BlurOn": "icons/focus-line.svg",
    "DarkMode": "icons/eye-off-line.svg",
    "GitHub": "icons/terminal-line.svg",
    "Language": "icons/translate-line.svg",
    "LibraryBooks": "icons/folder-line.svg",
    "SwipeHorizontal": "icons/layout-sidebar-line.svg",
}

# 上游只有线框版的 Tab 图标，用同一路径额外生成填充态，保留选中/未选中的视觉差异。
SOLID_SOURCES: dict[str, str] = {
    "icons/shield-shape-line.svg": "MingCuteShieldShapeFill",
    "icons/cloud-line.svg": "MingCuteCloudFill",
}


def is_svg_source(value: str) -> bool:
    return value.endswith(".svg")


def vector_for(value: str) -> str:
    return vector_name(value) if is_svg_source(value) else value


def vector_name(rel: str) -> str:
    """`icons/close-circle-line.svg` → `MingCuteCloseCircleLine`。"""
    stem = rel.rsplit("/", 1)[-1].removesuffix(".svg")
    name = "MingCute" + "".join(part.capitalize() for part in stem.replace("-", "_").split("_"))
    return name

# 快照图标仅生成入口映射，矢量来源与许可见 .github/licenses/NOTICE.md。
FIXED_ICONS = {}

CAP = {"butt": "Butt", "round": "Round", "square": "Square"}
JOIN = {"miter": "Miter", "round": "Round", "bevel": "Bevel"}


def project_root() -> Path:
    """按标志文件向上找仓库根，避免脚本里出现绝对路径。"""
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / ".git").exists() and (candidate / "android" / "settings.gradle.kts").exists():
            return candidate
    sys.exit("error: 找不到仓库根（需同时存在 .git 与 android/settings.gradle.kts）")


def fetch(rel: str, dest: Path, force: bool) -> str:
    if dest.exists() and not force:
        return dest.read_text(encoding="utf-8")
    url = f"{REPO_RAW}/{rel}"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            if resp.status != 200:
                sys.exit(f"error: {url} 返回 {resp.status}")
            body = resp.read().decode("utf-8")
    except urllib.error.URLError as exc:
        sys.exit(f"error: 下载 {url} 失败：{exc}")
    if "<svg" not in body:
        sys.exit(f"error: {url} 不是 SVG（限流页面会被原样写入）")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(body, encoding="utf-8")
    return body


def shape_path(node: ET.Element, tag: str) -> str:
    """把 simple <circle> / <rect> 转成 path data，保持与应用现有 PathParser 一致。"""
    a = node.attrib
    if tag == "circle":
        cx, cy, r = float(a["cx"]), float(a["cy"]), float(a["r"])
        return (
            f"M{cx - r:g},{cy:g} A{r:g},{r:g} 0 1,0 {cx + r:g},{cy:g} "
            f"A{r:g},{r:g} 0 1,0 {cx - r:g},{cy:g} Z"
        )
    x, y, w, h = float(a["x"]), float(a["y"]), float(a["width"]), float(a["height"])
    r = min(float(a.get("rx") or a.get("ry") or 0), w / 2, h / 2)
    if r <= 0:
        return f"M{x:g},{y:g} H{x + w:g} V{y + h:g} H{x:g} Z"
    return (
        f"M{x + r:g},{y:g} H{x + w - r:g} "
        f"A{r:g},{r:g} 0 0,1 {x + w:g},{y + r:g} V{y + h - r:g} "
        f"A{r:g},{r:g} 0 0,1 {x + w - r:g},{y + h:g} H{x + r:g} "
        f"A{r:g},{r:g} 0 0,1 {x:g},{y + h - r:g} V{y + r:g} "
        f"A{r:g},{r:g} 0 0,1 {x + r:g},{y:g} Z"
    )


def parse_paths(svg: str, rel: str) -> tuple[float, float, list[dict[str, str]]]:
    """抽出 viewBox 与各图形，支持上游用到的 path / circle / rect。"""
    root = ET.fromstring(svg)
    box = (root.get("viewBox") or "0 0 24 24").split()
    if len(box) != 4:
        sys.exit(f"error: {rel} 的 viewBox 非法：{root.get('viewBox')}")
    width, height = float(box[2]), float(box[3])

    # 新版 MingCute 把颜色写在 <svg> 上供 path 继承，只读 path 会当成无填充无描边。
    root_fill = (root.get("fill") or "none").strip()
    root_stroke = (root.get("stroke") or "none").strip()
    root_stroke_width = (root.get("stroke-width") or "1").strip()

    paths: list[dict[str, str]] = []
    for node in root.iter():
        tag = node.tag.replace(SVG_NS, "")
        if tag in ("svg", "g", "defs", "title", "desc"):
            continue
        if tag in ("path", "circle", "rect"):
            data = node.get("d") if tag == "path" else shape_path(node, tag)
            if not data:
                sys.exit(f"error: {rel} 有 <{tag}> 缺少几何数据")
        else:
            sys.exit(f"error: {rel} 含不支持的元素 <{tag}>，需扩展生成器")
        paths.append(
            {
                "d": re.sub(r"\s+", " ", data).strip(),
                "fill": (node.get("fill") or root_fill).strip(),
                "fill_rule": (node.get("fill-rule") or "nonzero").strip(),
                "stroke": (node.get("stroke") or root_stroke).strip(),
                "stroke_width": (node.get("stroke-width") or root_stroke_width).strip(),
                "linecap": (node.get("stroke-linecap") or "butt").strip(),
                "linejoin": (node.get("stroke-linejoin") or "miter").strip(),
            }
        )
    if not paths:
        sys.exit(f"error: {rel} 没有任何 <path>")
    return width, height, paths


def render_path(p: dict[str, str], rel: str, solid: bool = False) -> str:
    """描边与填充都落成 Color.Black；实际着色由调用点的 tint 覆盖，
    源 SVG 里的 #10161F 属于 MingCute 的预览色，不该带进来。"""
    has_fill = solid or p["fill"] not in ("none", "")
    has_stroke = p["stroke"] not in ("none", "")
    if not has_fill and not has_stroke:
        sys.exit(f"error: {rel} 有既不填充也不描边的 path")
    if p["linecap"] not in CAP:
        sys.exit(f"error: {rel} 未知 stroke-linecap：{p['linecap']}")
    if p["linejoin"] not in JOIN:
        sys.exit(f"error: {rel} 未知 stroke-linejoin：{p['linejoin']}")

    fill_type = "EvenOdd" if p["fill_rule"] == "evenodd" else "NonZero"
    lines = [
        "        addPath(",
        f'            pathData = PathParser().parsePathString("{p["d"]}").toNodes(),',
        f"            pathFillType = PathFillType.{fill_type},",
        f"            fill = {'SolidColor(Color.Black)' if has_fill else 'null'},",
    ]
    if has_stroke:
        lines += [
            "            stroke = SolidColor(Color.Black),",
            f"            strokeLineWidth = {float(p['stroke_width'])}f,",
            f"            strokeLineCap = StrokeCap.{CAP[p['linecap']]},",
            f"            strokeLineJoin = StrokeJoin.{JOIN[p['linejoin']]},",
        ]
    lines.append("        )")
    return "\n".join(lines)


def render_icon(
    val: str,
    rel: str,
    width: float,
    height: float,
    paths: list[dict[str, str]],
    solid: bool = False,
) -> str:
    body = "\n".join(render_path(p, rel, solid) for p in paths)
    imports = [
        "androidx.compose.ui.graphics.Color",
        "androidx.compose.ui.graphics.PathFillType",
        "androidx.compose.ui.graphics.SolidColor",
        "androidx.compose.ui.graphics.vector.ImageVector",
        "androidx.compose.ui.graphics.vector.PathParser",
        "androidx.compose.ui.unit.dp",
    ]
    if any(p["stroke"] not in ("none", "") for p in paths):
        imports += [
            "androidx.compose.ui.graphics.StrokeCap",
            "androidx.compose.ui.graphics.StrokeJoin",
        ]
    import_block = "\n".join(f"import {i}" for i in sorted(imports))
    return f"""// 由 scripts/gen_icons.py 从 MingCute 生成，勿手改。源：{rel}
package {OUT_PACKAGE}

{import_block}

internal val {val}: ImageVector by lazy {{
    ImageVector.Builder(
        name = "{val.removeprefix("MingCute")}",
        defaultWidth = {width:g}.dp,
        defaultHeight = {height:g}.dp,
        viewportWidth = {width:g}f,
        viewportHeight = {height:g}f,
        autoMirror = false,
    ).apply {{
{body}
    }}.build()
}}
"""


def render_entry() -> str:
    icons = {name: vector_for(value) for name, value in ICONS.items()} | FIXED_ICONS
    props = "\n".join(
        f"    val {name}: ImageVector get() = {vector}" for name, vector in sorted(icons.items())
    )
    return f"""// 由 scripts/gen_icons.py 生成，勿手改。改图标请改脚本里的 ICONS 表后重跑。
package {OUT_PACKAGE}

import androidx.compose.ui.graphics.vector.ImageVector

// 全应用图标入口；Nav*Active 使用填充态，其余使用线框态。
object AppIcons {{
{props}
}}
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="从 MingCute SVG 生成 Compose ImageVector")
    parser.add_argument("--force", action="store_true", help="忽略缓存重新下载")
    args = parser.parse_args()

    root = project_root()
    cache = root / SVG_CACHE
    out = root / OUT_DIR
    out.mkdir(parents=True, exist_ok=True)

    for old in out.glob("MingCute*.kt"):
        old.unlink()

    for rel in sorted({value for value in ICONS.values() if is_svg_source(value)}):
        svg = fetch(rel, cache / rel, args.force)
        width, height, paths = parse_paths(svg, rel)
        val = vector_name(rel)
        (out / f"{val}.kt").write_text(render_icon(val, rel, width, height, paths), encoding="utf-8", newline="\n")
        aliases = sorted(n for n, r in ICONS.items() if r == rel)
        print(f"[ ok ] {val}.kt  <- {rel}  ({len(paths)} path)  {', '.join(aliases)}")

    for rel, val in sorted(SOLID_SOURCES.items()):
        svg = fetch(rel, cache / rel, args.force)
        width, height, paths = parse_paths(svg, rel)
        (out / f"{val}.kt").write_text(
            render_icon(val, rel, width, height, paths, solid=True), encoding="utf-8", newline="\n"
        )
        aliases = sorted(n for n, r in ICONS.items() if r == val)
        print(f"[ ok ] {val}.kt  <- {rel} (solid)  {', '.join(aliases)}")

    (out / "AppIcons.kt").write_text(render_entry(), encoding="utf-8", newline="\n")
    print(f"[ ok ] AppIcons.kt  ({len(ICONS)} 个语义名 / {len({vector_for(v) for v in ICONS.values()})} 个 vector)")
    print(f"[info] 输出目录 {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
