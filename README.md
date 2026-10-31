# Clash Go（Flutter 重构版）

使用 Flutter 对 [ClashGo](https://github.com/ChenL-eon/ClashGo) 的桌面重构：同一套 Material 3 界面面向 Windows 与 Android，内核使用 [mihomo](https://github.com/MetaCubeX/mihomo)。

Windows 与 Android 均为完整代理链路：Windows 使用系统代理，Android 通过 `VpnService` + TUN 接管设备流量（见[平台支持](#平台支持)）。

> A Flutter rewrite of ClashGo. Windows and Android are both fully functional; Android runs mihomo inside a VpnService with TUN takeover.

---

## 功能

- **订阅管理**：链接导入、本地 YAML 导入、二维码导入、自动命名、手动/自动更新、流量与到期信息、更新间隔、删除（含运行时配置清理）；三种导入方式统一收在页面右上角「+」下拉菜单（桌面为「二维码图片」、移动端为「扫描二维码」），页面不再平铺导入按钮，空状态只提示「点击右上角 +」；桌面订阅列表为两列紧凑卡片，展示类型/状态徽标、流量用量与更新时间。
- **内核生命周期**：mihomo 启停、端口/密钥变更自动重启、异常退出提示、启动超时与日志诊断、开机自动启动；运行中「停止」按钮使用红色浅底与红色图标/文字、无描边，与启动态的实心主题色明确区分。Windows 系统代理默认选中（旧配置升级时一次性迁移为开启），内核启动后自动写入系统代理，停止内核或退出应用时还原原设置，用户手动关闭后会记住选择。
- **Android VPN**：VpnService 前台服务、TUN 接管 DNS 与 TCP/UDP、通知栏常驻状态与停止操作、VPN 授权流程、退回后台保持运行。
- **代理**：策略组与节点列表、延迟测试（单节点/整组/全部）、节点切换与选择记忆、规则/全局/直连模式切换；内核未启动时离线预览当前订阅的节点，可直接选择节点（保存选择，启动内核后自动应用），并对节点/分组/全部执行 TCP 连接测速（显示 ms 或「超时」）。离线预览与启动内核都依赖订阅的本地缓存，缓存缺失时代理页给出说明与「更新订阅」按钮一键补齐，应用启动的自动更新与启动内核流程也会就地重取缓存（订阅地址失败后 10 分钟内不再重试）。显示选项（滚动到已选/风格/排序/布局/尺寸/隐藏超时代理）入口位于页面右上角、「测速全部」图标之后，菜单与按钮右缘对齐向下展开，二级菜单只在点击时展开、同时只开一个；页面头部只保留「测速全部」图标与组内「测速本组」，不再提供刷新按钮（节点由内核事件与 8 秒轮询自动刷新）。节点磁贴为带 1px 描边的两行卡片：名称在上，类型在左下、彩色延迟在右下，延迟文本可直接点击测速，选中为浅色底 + 主题色描边 + 对勾。
- **连接**：实时连接列表、速率统计、按主机/规则/进程搜索、连接详情、关闭单条或全部连接。
- **日志**：内核实时日志、级别筛选、关键字搜索、暂停、清空；输出区配色跟随主题（浅色模式浅面板、深色模式深面板，支持纯黑）。
- **规则**：生效规则列表、类型/内容/策略搜索、复制。
- **DNS**：通过内核 DNS 模块查询 A/AAAA/CNAME/TXT/MX/NS/SRV 记录，保留最近查询。
- **代理提供者**：外部 proxy-providers 列表、单个/全部更新、健康检查、流量信息。
- **设置**：归档为四组入口——个性化（主题、语言）、Clash（Clash 特性：端口、密钥、局域网、IPv6、系统代理、内核重启）、应用（应用行为、关于）、维护（数据管理），组内为「图标 + 标题 + 副标题 + 箭头」行，点击进入子页，子页左上角返回按钮回到入口页；中英文切换、跟随系统/浅色/深色/纯黑、6 种主题色、混合端口与 API 端口、API 密钥重新生成、允许局域网、IPv6、系统代理、自动启动、订阅自动更新、核心重启、数据清理入口、许可证与诊断信息均保留。语言、主题与主题色使用锚定下拉菜单就地选择，不再弹居中对话框；菜单右缘留出 16px 间距不贴窗口边，选中项为内缩 6px、圆角 10px 的高亮块，与圆角菜单（14px）形状一致；分组卡片内的行悬停/选中色块按卡片圆角裁剪，卡片描边绘制在色块之上，不再出现直角色块溢出圆角或遮住边框；页面底部弹出菜单（代理页「更多」、订阅页「添加」与卡片菜单、密钥菜单）统一为 22px 圆角卡片，行悬停色块同样按圆角裁剪、描边保持在最上层。
- **移动端布局**：主页 2×2 指标卡与启动面板、代理组下划线标签 + 双列节点卡（内核未启动时可离线预览并选择当前订阅节点、做 TCP 测速；选中节点使用整圈圆角描边 + 浅色底，与桌面节点磁贴一致；顶部图标行从左到右为搜索、「测速全部」与显示选项「⋯」）、订阅卡片流量/到期信息与圆形操作按钮（添加订阅只有右上角「+」一个入口，菜单内含链接/本地文件/二维码三项）、设置四组入口 + 子页；底部悬浮导航为大圆角胶囊造型，背景高斯模糊，选中胶囊在相邻项间滑动切换，图标与文字同步做颜色、字重和轻微缩放过渡；Windows 窗口宽度小于 1000px 时自动切换同一套布局。
- **桌面布局**：宽度 ≥1000px 时主页为仪表盘——标题栏右侧「系统代理 / TUN / 直连」接管方式切换与「启动」按钮；第一行「当前订阅」+「代理模式」，第二行「内核状态 / 接管方式 / 内核版本」，第三行「上传 / 下载 / 混合端口」，第四行整幅「网络流量」折线图；下方保留网络延迟与快捷入口。窄窗口按移动端顺序单列排布。代理页排序（默认/延迟/名称）同样为图标锚定下拉菜单。
- **桌面体验**：侧边栏/底部悬浮导航自适应（移动端底部仅主页、代理、订阅、设置；连接、日志、DNS、规则、提供者从主页快捷入口进入）、窄窗口与手机宽度布局、无控制台窗口闪烁、关闭窗口时优雅停止内核；侧边栏图标按语义重新选取——主页房屋、代理地球、订阅文档、连接链环、日志终端、设置齿轮，桌面与移动底栏保持一致；Windows 全局字体为 `Microsoft YaHei UI`，按钮、提示条与工具提示的文本样式统一继承主题字体，中文不再回落到宋体。
- **提示条**：全局 SnackBar 跟随明暗主题（浅色为白卡片、深色为深卡片，正文使用主题文字色，错误提示为红色底），桌面固定 420px 居中浮层、移动端左右留 18px 并抬到悬浮底栏上方；复制、节点切换提示、设置操作结果、订阅导入错误、内核通知等入口统一走同一套样式。
- **后台省电**：应用进入后台（Windows 失焦/最小化、Android 切后台）后停止 UI 侧 WebSocket、连接/代理轮询、延迟与自动更新等定时任务，仅保留 mihomo 内核进程与 Android VPN 前台服务；回到前台自动恢复并刷新。

### 未包含

ROOT TUN / TPROXY、按应用代理、二维码扫描、WebDAV、Wi-Fi 策略。以上能力在原项目中依赖额外的 Android 原生层，本次重构未实现。

---

## 平台支持

| 平台 | 状态 | 说明 |
|---|---|---|
| Windows 10/11 x64 | ✅ 完整链路 | 内置 mihomo v1.19.33，订阅导入 → 内核启停 → 代理/连接/日志/DNS/规则/提供者全流程可用 |
| Android arm64-v8a | ✅ 完整链路 | VpnService + 内置 mihomo v1.19.33（TUN），订阅导入 → 内核启停 → 节点切换/延迟 → 设备流量接管全流程可用 |

Windows 二进制包含 `core/mihomo.exe` 与 geodata；Android 仅打包 arm64-v8a 的 `libmihomo.so` 与 geodata，不包含 Windows 内核。

> Android 内置内核由 mihomo v1.19.33 源码以 `-tags "with_gvisor cmfa"` 编译。官方 Android 发布二进制在 TUN 初始化时会读取 `/data/system/packages.xml`（普通应用无权限），导致 `Start TUN listening error: build android rules ... permission denied`，因此不能直接使用；`cmfa` 标签会跳过这段 Android 包名规则构建。

---

## 构建与运行

### 环境

- Flutter SDK 3.47+（Dart 3.13.5+）
- Windows：Visual Studio 2022（含“使用 C++ 的桌面开发”）
- Android：Android SDK 36、JDK 21（仅构建 APK 时需要）
- 内核：`core/mihomo.exe` 与 `core/geodata/` 已随仓库提供

### Windows

```bash
flutter pub get
flutter build windows --release
# 产物：build/windows/x64/runner/Release/clash_go.exe
```

开发调试可直接运行 `flutter run -d windows`。

### Android

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64 --split-per-abi
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk（仅 arm64-v8a）
```

APK 已内置 `android/app/src/main/jniLibs/arm64-v8a/libmihomo.so`（mihomo v1.19.33，`with_gvisor cmfa`）与 geodata，无需额外下载。替换内核时需保留 `cmfa` 构建标签，否则 TUN 初始化会因读取 `/data/system/packages.xml` 失败而无法接管流量。

---

## 使用说明

1. 打开「订阅」，粘贴订阅链接或导入本地 YAML。
2. 回到首页点击电源按钮启动内核；启动成功后即可在「代理」选择节点。
3. Windows：系统代理默认开启——首次启动（含从旧版本升级）会自动选中「系统代理」，内核启动后把 Windows 代理指向混合端口，停止内核或关闭应用时还原原注册表设置；如不需要，可在「设置 → Clash 特性 → 系统代理」或首页右上角胶囊中关闭，关闭后会记住选择，不再自动开启。Android：首次启动会请求 VPN 授权，授权后设备流量自动经 TUN 接管，无需额外开关；通知栏常驻通知可返回应用或停止内核。
4. 默认端口：混合端口 `17890`，API 端口 `19090`。若被其他程序占用，请在设置中修改后重启内核。
5. API 默认仅监听 `127.0.0.1`。只有开启「允许局域网连接」后，同一网络的设备才能使用本机代理。

### 数据目录

Windows：`%APPDATA%\com.clashgo\clash_go\`

Android：`/data/user/0/com.clashgo.clash_go/files/`（应用私有目录，含 `runtime/` 与 `runtime/mihomo.log`）

```text
settings.json            应用设置
subscriptions/           订阅列表、配置文件与选择记忆
runtime/                 运行时配置 config.yaml、core.log、内核缓存与 geodata
proxies/                 节点选择状态
```

删除最后一个订阅时，应用会停止内核并清理运行时生成的配置和提供者缓存。

---

## 项目结构

```text
lib/
  core/          应用信息、路径、错误、格式化、主题、i18n
  models/        订阅、设置、代理、连接、规则、DNS、提供者等模型
  data/          本地持久化
  services/      mihomo API/WebSocket、内核管理、配置生成、订阅抓取、系统代理
  controllers/   应用状态与业务编排（ChangeNotifier）
  ui/            设计系统、Shell、四个主页面与工具页面
assets/          品牌图、图标、geodata
core/            Windows 内核与 geodata
windows/ · android/  平台工程
test/            单元测试（格式化、订阅、设置、i18n）
```

---

## 验证情况

2026-10-26 在 Windows 11 与 Android 真机（2410DPN6CC，Android 17 / API 37，arm64-v8a，HyperOS）上使用 mihomo v1.19.33 完成实机验证；2026-10-28 补充移动端底栏切换动画、后台节流、主页/日志/下拉菜单调整、首页仪表盘重构，以及全部下拉菜单统一为新浮层样式、订阅页三入口导入（链接/文件/二维码）、设置排版修正与代理页嵌套显示菜单（Windows 桌面/移动宽度、浅色/深色）。

Windows：

- 订阅新增/更新/重命名/删除、内核启停、密钥重新生成后自动重启、优雅退出终止内核
- 代理组/节点/延迟/切换、连接实时列表与详情、日志实时输出与筛选、DNS 查询、规则搜索、提供者健康检查与更新
- 中文/英文、浅色/深色/纯黑、主题色、自动启动、420px 手机宽度与 760px 窄窗口布局
- 移动端底部导航仅保留主页/代理/订阅/设置，连接与日志从主页快捷入口进入并可返回（设置页归档后原「工具」区已移除）
- 底部导航胶囊化改造（420×900）：大圆角悬浮底栏 + 背景高斯模糊（`BackdropFilter`），选中项使用包裹图标与文字的大胶囊高亮；浅色、深色与弹窗遮罩下均正常，1220×800 桌面侧边栏布局无变化
- 移动端新布局逐页截图验证（420×900）：主页指标卡/启动面板、代理组标签与双列节点卡（注入本地测试订阅验证离线预览与点击提示）、订阅卡片流量/到期/操作按钮、设置分组与搜索；1220×800 桌面四页复核无回归
- 底部悬浮导航与滚动内容留白正常，四页无溢出或渲染异常
- 修复 Windows 标题栏仅显示关闭按钮：根因是 `WindowOptions.backgroundColor` 会触发 window_manager 注入 DWM accent（`SetWindowCompositionAttribute`），导致最小化/最大化/关闭字形白字白底不可见；移除该参数后 1220×800 下 – □ ✕ 三键全部可见，最小化（`IsIconic=True`）、最大化（`IsZoomed=True`）、关闭（优雅退出）均实测可用
- 修复桌面侧边栏切换时两行同时亮起：根因是行底色由 `AnimatedContainer` 在「选中色 ↔ 透明」之间补间，`Color.lerp` 会把 RGB 一并插值到黑色，过渡帧两行同时闪出深灰；改为选中/悬停底色全部瞬时切换，并移除 InkWell 的悬停淡入（同样是透明起点的颜色补间）。ffmpeg ddagrab 60fps 实屏录制两次点击切换（129 + 164 帧，采样区避开光标）均 0 帧双高亮、0 帧深灰过渡，高亮底色在 1 帧内完成切换
- 移动端底栏切换动画（420×861 客户区，ddagrab 60fps 实屏录制 480 帧）：选中胶囊以 260ms easeOutCubic 从上一项滑到当前项，逐帧检测胶囊中心连续推进（75→170px，约 19 帧，首末帧受检测阈值影响），任意帧只有一个胶囊；图标/文字颜色、字重与 6% 缩放同步过渡，图标 180ms 交叉切换。按压/悬停底色置为透明，避免与滑动胶囊叠成“双高亮”，仅保留点击水波纹
- 后台节流（Windows 最小化由 Flutter 上报 `inactive`，代码按平台纳入后台）：最小化 3 秒内应用到 API 端口（19091）的 ESTABLISHED 连接由 4~5 降到 0，恢复窗口后回到 4；前后台各 10 秒进程 CPU 增量为 0.094s / 0.062s（桌面端 UI 空转本就很低，收益主要在移动端射频与轮询）；后台期间 mihomo 进程与端口保持，可继续转发流量；关闭窗口后内核随应用优雅退出、端口释放
- 2026-10-28 布局与菜单调整（1500×1000 与 800×1000 实屏截图，产物 `build/screenshots/ui_*.png`）：主页两栏镜像（左订阅卡+统计、右启动卡+速率+延迟）在空订阅与浅色下正常；主题色下拉锚定在设置行下方，选「星紫」后导航高亮、行内色点与按钮即时变色；主题下拉切「深色」全应用即时切换，日志输出区随之为深色面板（浅色时为白面板），设置/代理/移动端布局均无回归；语言下拉、移动端（800px）设置三项下拉与底栏布局正常；选完已还原为跟随系统 + 海蓝主题色
- 2026-10-28 首页仪表盘与下拉菜单（1500×1000 / 1100×900 / 600×900，浅色与深色，产物 `build/screenshots/ui2_*.png`）：首页按参考稿重排为「当前订阅 + 代理模式」「内核状态 / 接管方式 / 内核版本」「上传 / 下载 / 混合端口」「网络流量」四层卡片，空订阅时各行为 `—`/`-- B/s`、三列卡片高度对齐且无溢出；TUN 胶囊为禁用态，悬停提示「当前 Windows 版未提供 TUN 接管」，直连胶囊随 `systemProxy=false` 选中；语言/主题/主题色下拉在 1500px 下菜单右缘距窗口客户区约 76px（锚点右缘再内缩 16px），1100px 与 600px 移动布局下同样不贴边、不溢出，选中项高亮块相对菜单内缩 6px、圆角 10px，与 14px 圆角菜单形状匹配；验证后已还原设置并关闭测试实例
- 2026-10-28 离线选节点与提示条阴影（1500×1000 实屏截图，产物 `build/screenshots/r6_*.png`）：未启动内核时点击 select 组节点会立即勾选并持久化到 `proxies/selection_state.json`，提示「已选择，启动内核后生效」，重启应用后勾选保持；随后在临时端口 17892/19092 启动内核，API `/proxies/吹雪云` 返回的 `now` 与离线选择一致（`match=True`），运行态代理页勾选同步；非 select 组（自动选择/故障转移）点击节点仍执行测速；SnackBar 阴影由 elevation 4/2 降至 1/0（`r6_toast_zoom.png`）；验证后已停止内核、恢复 `settings.json`（SHA256 `322F065E…5E3C`）、注册表基线（`ProxyEnable=0` / `127.0.0.1:17891`）与测试前的节点选择（日本·移联01），未触碰用户运行中的实例
- 2026-10-28 提示条跟随主题（1500×1000 与 414×861 实屏截图，产物 `build/screenshots/r5_toast_*.png`）：未启动内核时点击节点提示「启动内核后才能切换节点」，原全局 SnackBar 在浅色主题下固定深色底、桌面横向几乎铺满窗口；现将 SnackBar 主题改为浅色白卡片/深色卡片底 + 主题正文色 + 14px 圆角浮层，桌面宽度固定 420px 居中，移动端左右 18px 并抬高 96px + 安全区避开悬浮底栏，错误提示保留红色底（深色主题下用深色字）；复制、节点提示、设置结果、订阅导入错误、内核通知统一走 `showAppToast`。浅色桌面、深色桌面、浅色移动、深色移动四组截图均与主题一致；验证后已恢复 `settings.json`（SHA256 `322F065E…5E3C`）与注册表基线（`ProxyEnable=0` / `127.0.0.1:17891`），未启动测试内核
- 2026-10-28 卡片紧凑化/停止按钮配色/离线测速/设置归档（1500×1000 桌面与 414×861 移动宽度实屏截图，产物 `build/screenshots/r4_*.png`）：订阅页改为两列紧凑卡片（图标、名称、类型/状态徽标、流量与更新时间、刷新与更多菜单），单卡宽度约半屏；运行中「停止」按钮改为浅蓝底 + 蓝色描边与文字的实心按钮，停止后恢复「启动」；内核未启动时代理页读取当前订阅 YAML 离线显示 3 个策略组与全部节点，并提示「代理未启动：显示订阅中的节点，测速结果为 TCP 连接延迟」，节点/整组/全部均可做 TCP 连接测速（桌面实测 89–135 ms 绿色、高延迟橙色、不可达「超时」红色），移动宽度同样可用；设置页归档为个性化/Clash/应用/维护四组入口，行样式为图标 + 标题 + 副标题 + 箭头，主题、语言、Clash 特性、应用行为、关于、数据管理子页均可进入并返回，入口页与子页均无溢出；验证使用临时端口 17892/19092、systemProxy=false，不写注册表，结束后已按备份恢复 `settings.json`（SHA256 `322F065E…5E3C`）并复查注册表为 `ProxyEnable=0` / `ProxyServer=127.0.0.1:17891`，未触碰用户运行中的实例与内核
- 2026-10-28 切换按钮双高亮与字体/系统代理修复（1500×1000 实屏截图，产物 `build/screenshots/r3_*.png`、`r3_net_test.log`）：代理模式分段控件去掉 160ms 底色补间与 InkWell 悬停填色（仅保留点击水波纹）后，「规则选中 + 全局悬停」与「全局选中 + 直连悬停」两种视频场景均只有选中项一处高亮；首页头部删除「直连」胶囊（代理模式内已有直连），「系统代理」改为可双向开关，内核未运行时「接管方式」提示「内核未运行，启动后自动写入系统代理」；Windows 文本主题显式使用 `Microsoft YaHei UI`（`fontFamilyFallback` 不会覆盖默认 Roboto，中文此前回落到宋体），中英文均为无衬线；修复系统代理从未生效导致启动后无法访问外网：备份文件路径把 `Directory` 直接插值成 `Directory: C:\...`，`File` 构造抛 `PathNotFoundException` 且发生在写注册表之前，改为 `paths.supportDir.path` 后启动内核即写入 `ProxyEnable=1`/`ProxyServer=127.0.0.1:17891`，`Invoke-WebRequest`（走系统代理）Google generate_204 → 204、YouTube → 200、GitHub → 200，`curl --proxy` 经 17891 访问 Cloudflare → 200（0.31s）；胶囊关/开切换后注册表在 `0/127.0.0.1:2080` 与 `1/127.0.0.1:17891` 间正确往返，停止内核后还原为 `0/127.0.0.1:2080` 并删除备份文件
- 2026-10-28 设置行悬停色块与字体修复（深色 1500×1000、浅色 1220×800、移动 520×900 实屏截图，产物 `build/screenshots/r7_*.png`）：设置子页行悬停时色块曾铺到卡片直角边缘并盖住描边，根因是行内 `InkWell` 的悬停底色绘制在 `SurfaceCard` 背景/边框之上且未裁剪；现由卡片统一按圆角裁剪子层、描边改为前景绘制，深/浅色与移动宽度下悬停色块均贴合圆角、边框完整可见（四角放大截图复核）。按钮文字此前回落到宋体，根因是 `FilledButton`/`TextButton`/`OutlinedButton` 以及 SnackBar、Tooltip 的文本样式为不含字族的 `TextStyle`，其自建 `DefaultTextStyle` 隔离了主题字体；现从 `textTheme`（labelLarge/bodyMedium/bodySmall）派生，桌面启动按钮放大 10 倍前后对比笔画为无衬线（像素差 avg 10.4、max 330）；验证后已恢复 `settings.json`（SHA256 `322F065E…5E3C`）、注册表基线（`ProxyEnable=0` / `127.0.0.1:17891`）与节点选择（`65EE3813…84C1F`），未触碰用户运行中的实例
- 2026-10-28 停止按钮配色/侧边栏图标/移动节点选中框（1500×1000 与 520×900、浅色与深色实屏截图，产物 `build/screenshots/r8_*.png`）：运行中「停止」按钮由浅蓝改为红色浅底 + 红描边/红字（桌面头部与移动主页大按钮），颜色取自 `palette.danger`（浅色 `#DC2626`、深色 `#F87171`），与启动态实心主题色区分；侧边栏与移动底栏图标改为主页房屋、代理地球、订阅文档、连接链环、日志终端、设置齿轮，先用 48px/18px 对照图确认小尺寸辨识度（`r8_icon_candidates.png`）；移动代理页选中节点卡移除左侧 3px 竖条，改为整圈 1.2px 圆角描边 + `accentSoft` 浅底 + 蓝色对勾，与桌面节点磁贴一致（`r8_selected_card_light_zoom.png`）；验证使用临时端口 17892/19092、`systemProxy=false`，结束后已恢复 `settings.json`（SHA256 `322F065E…5E3C`）、两份 `selection_state.json` 与注册表基线（`ProxyEnable=0` / `127.0.0.1:17891`），无内核与测试端口残留
- 2026-10-28 系统代理默认选中/停止按钮去描边/底部菜单圆角裁剪（1280×880 桌面与 520×900 移动、浅色与深色实屏截图，产物 `build/screenshots/r9_*.png`）：用旧版配置（无 `settingsVersion`、`systemProxy=false`）启动后，`settings.json` 立即写入 `settingsVersion=2`、`systemProxy=true`，首页「系统代理」胶囊为蓝色选中态（`r9_home_default_light.png`），「Clash 特性」子页开关同步开启；点击「启动」后注册表自动写入 `ProxyEnable=1` / `ProxyServer=127.0.0.1:17892`，接管方式显示「系统代理」，停止内核后还原为 `ProxyEnable=0` / `ProxyServer=127.0.0.1:17891`。另以 `settingsVersion=2` + `systemProxy=false` 重启，胶囊保持未选中（`r9_migration_once_off_zoom.png`），确认迁移只执行一次、不覆盖用户关闭选择；运行中「停止」按钮移除 `side` 描边，浅色（浅红底 + 红字）与深色（深红底 + 珊瑚红字）桌面及移动主页大按钮放大 4 倍均无边框（`r9_stop_light_zoom.png`、`r9_stop_dark_zoom.png`）；代理页「更多」与设置「API 密钥」底部菜单改为 22px 圆角卡片承载（SurfaceCard 圆角裁剪 + 前景描边），悬停「刷新节点」「管理订阅」「复制密钥」时色块上下缘贴合圆角、描边完整可见（`r9_more_sheet_hover_light_zoom.png` 等）；验证使用临时端口 17892/19092，结束后已恢复 `settings.json`（SHA256 `322F065E…5E3C`）、`selection_state.json`（`65EE3813…84C1F`）与注册表基线，无进程与测试端口残留
- 2026-10-28 全部下拉菜单统一为新浮层样式（1384×861 桌面与 604×901 移动宽度、浅色与深色实屏截图，产物 `build/screenshots/r10_*.png`、`r10b_*.png`）：新增共享样式 `appMenuStyle`/`appMenuItemStyle`（`lib/ui/widgets/common.dart`），浮层为 20px 圆角 + elevation 18 柔光阴影 + 外层 8px 内边距，菜单行 46px 高、左右 16px 内边距、悬停底色圆角 12px（= 20 − 8）与浮层同心，选中行只保留主题色文字与右侧 18px 主题色对勾、取消灰色选中底块；深色模式因阴影几乎不可见补 1px `palette.border` 描边，浅色保持无描边（`r10b_dropdown_theme_light_zoom.png` 无边、`r10b_dropdown_theme_dark_zoom.png` 有边）。覆盖全部 5 个菜单：设置页「主题」「主题色（含色点）」「语言」、移动代理页排序，以及订阅卡片「更多」菜单——后者原为 `PopupMenuButton`（InkWell 悬停块无圆角），已改为同样式的 `MenuAnchor`，编辑/删除行图标与文字对齐、删除为主题红（`r10_sub_menu_hover_light_zoom.png`、`r10b_sub_menu_hover_dark_zoom.png`）。右对齐锚点用 `alignmentOffset: Offset(-(menuWidth + 16), 6)` + `bottomEnd`，桌面菜单右缘距窗口 16px，604px 移动宽度下排序菜单与设置「主题」菜单均不贴边、不溢出（`r10b_mobile_sort_menu.png`、`r10b_mobile_theme_menu.png`）。本轮未启动内核、未写注册表（复查仍为 `ProxyEnable=0` / `ProxyServer=127.0.0.1:2080`），测试订阅与档案已删除，`settings.json`（`5C6D3A03…4F47`）、`subscriptions/subscriptions_list.json`（`B563ACDC…614C`）、`subscriptions/selection_state.json`（`2096D205…1FBA`）、`proxies/selection_state.json`（`65EE3813…84C1F`）四个文件按备份逐字节还原并核对 SHA256 一致
- 2026-10-28 订阅页移动端菜单改下拉浮层 + 移动端底栏缩小（491×901 移动宽度浅色/深色与 1384×861 桌面实屏截图，产物 `build/screenshots/r11_*.png`）：移动端订阅页头部「+」原为 `showModalBottomSheet` 底部弹窗（从链接添加 / 导入本地 YAML），现改为与桌面统一的 `MenuAnchor` + `appMenuStyle`/`appMenuItemStyle` 浮层下拉，复用 `_cardMenuContentWidth=150`、`_actionMenuRow` 与「按钮下方 6px、右缘内收 8」的锚点；卡片「更多」同样由底部弹窗改为浮层下拉（未启用订阅显示「使用」+「编辑」，已启用仅「编辑」），`_showAddSheet`/`_showCardMenu` 与 `onMore` 回调移除，桌面订阅页布局与卡片菜单未改动（`r11_mobile_add_menu_zoom.png`、`r11_mobile_card_menu.png`、`r11_mobile_card_menu_dark.png`、`r11_desktop_subs_dark.png`）。底部导航胶囊整体缩小一档：内容高 56→46（含 6px 内边距后总高 70→58）、外圆角 40→33、选中胶囊圆角 28→23、图标 21→19、文字 10.5→10 且图标/文字间距 3→2，左右留白 12→20、最大宽度 620→420（手机 393dp 下约 353dp 宽，604px 移动宽度下由 584 收窄到 420 并居中）；随之把移动页脚留白 112→96（`PageContainer`/`PageFrame`）与提示条底部 margin 96→84、104→92 一并下调，避免内容与底栏之间出现空档。代理页「更多」与设置「API 密钥」两处底部弹窗不在本轮范围内，保持原样。本轮未启动内核、未写注册表（复查 `ProxyEnable=0` / `ProxyServer=127.0.0.1:2080`），测试订阅与档案已删除，四个用户 JSON 文件按备份逐字节还原且 SHA256 与测试前基线一致
- 2026-10-28 订阅三入口、内核页排版、代理页嵌套菜单（422×861 / 384×861 移动宽度与 1284×821 桌面宽度、浅色与深色实屏截图，产物 `build/verify_ui12/r12_*.png`）：① 订阅页「+」由两项改为订阅链接 / 本地文件 / 二维码三项（`_importEntries`，桌面第三项为「二维码图片」，安卓与 iOS 为「扫描二维码」，按 `qrScannerSupported` 区分）。桌面端选图后用 zxing2 解码（先 1024 再 2048 边长、正反面各二值化），安卓端由 `lib/ui/widgets/qr_scan.dart` 用 mobile_scanner 实时识别；识别文本统一经 `subscriptionUrlFromQr` 归一化，支持 `clash://install-config?url=` 包装并拒绝非 http(s)。三条链路在 Windows 实屏逐条导入成功（`r12_02_import_menu.png`、`r12_05_link_added.png`、`r12_06_file_added.png`、`r12_08_qr_added.png`），落盘的 `subscriptions/profiles/<id>.yaml` 与订阅 URL 证明二维码解码得到的正是测试地址 `http://127.0.0.1:18099/demo.yaml`，导入后代理页离线节点同步可见；`test/qr_import_test.dart` 覆盖 PNG 解码、原始/反色像素解码与链接归一化。② 设置「Clash 特性」内核段原有一字一行的竖排标题（`内核路径`/`运行目录` 被尾部长路径挤没宽度），`_ValueRow` 尾部值改为 `Flexible` + `ConstrainedBox(maxWidth: 320)` + 单行省略，422 与 384 宽度、浅色与深色下标题均单行完整、路径以 `E:\Demo\ClashGo\b…` 省略并保留复制/打开图标（`r12_43_core_rows_light.png`、`r12_48_core_rows_dark.png`、`r12_49_core_rows_320.png`）。③ 代理页右上角「更多」改为参考稿的嵌套菜单（`DisplayMenu`，桌面与移动复用同一组件）：滚动到已选 ｜ 风格（标签页/列表）、排序（默认/延迟/名称）、布局（宽松/标准/紧凑）、尺寸（宽松/标准/紧凑）｜ 隐藏超时代理，行首线性图标、子菜单行尾 `›`、分组间细线，选中项主题色加右侧对勾；子菜单选项 `closeOnActivate: false`（勾选标记原地跳动、浮层不收起），仅「滚动到已选」点完收起浮层；桌面 1284px 宽度下子菜单在贴右缘时自动向左展开且不出屏（`r12_52_desktop_menu_root.png`、`r12_53_desktop_menu_layout.png`），选「标准」后 `proxyLayout` 落盘为 `standard` 且节点网格由 3 列变 2 列（`r12_54_desktop_layout_standard.png`）；移动宽度下已实屏复核排序=延迟持久化、布局=宽松单列、尺寸=加高卡片、隐藏超时代理后 6 节点剩 2 并提示「已隐藏 4 个超时节点」（`r12_19`–`r12_23`）。新增 `test/proxy_display_menu_test.dart` 8 例锁定六项标签与两条分组线、四个子菜单回调参数、子菜单不收起与「滚动到已选」收起、隐藏开关的对勾态。④ 离线测速超时判定修正：`OfflineLatency.probe` 失败返回 `-1`、无回执返回 `null`，此前 `-1` 会显示成 `-1 ms`，现两者一律计为「超时」（`r12_25_probed.png`：两节点 1 ms、四节点超时）。本轮未启动内核、未写注册表（复查 `ProxyEnable=0x1` / `ProxyServer=127.0.0.1:2080`，与测试前一致），测试订阅与三份 profile YAML 已删除，`settings.json`（`5C6D3A03…4F47`）、`subscriptions/subscriptions_list.json`（`B563ACDC…614C`）、`subscriptions/selection_state.json`（`2096D205…1FBA`）、`proxies/selection_state.json`（`65EE3813…84C1F`）四个文件按备份逐字节还原并核对 SHA256 一致，本地测试服务（18099/18100）已停止
- 2026-10-28 离线态订阅缓存自愈（1300×860 桌面与 460×900 移动宽度、用户真实订阅实屏截图，产物 `build/verify_ui13/r13_*.png`）：内核未启动时的节点预览、离线测速与切换都依赖 `subscriptions/profiles/<id>.yaml`，该缓存缺失时代理页只会显示「订阅里没有可预览的节点」且「刷新」无效，启动内核也会以 `AppError('noProfile')` 失败——用户真实数据即卡在此状态（`r13_01_offline_proxy_user.png`）。新增 `AppController.hasCachedProfile`/`ensureProfile`（本地订阅重读原文件，远程订阅静默更新一次），三处接入：① 代理页离线空状态在缓存缺失时改为警示条「这个订阅还没有本地缓存，更新一次即可离线查看节点、测速和切换」+「更新订阅」主按钮（桌面与移动宽度同一分支，更新中按钮随 `updatingSubscriptions` 置灰，静默更新失败补「获取订阅失败」提示），点击后重读缓存即列出 3 个策略组 / 25 个节点（`r13_02_offline_noprofile.png`、`r13_03_after_update.png`，终版复测 `r13_08_final_before_click.png`/`r13_09_final_after_click.png`）；② `startCore` 在读取 profile 前先 `ensureProfile`，消除上述死锁；③ 自动更新流程把「未到更新期但缓存缺失」也计入待更新，应用启动与每分钟定时器都会自愈（删除缓存 + `autoUpdateSubscriptions=true` 重启后无需任何点击即显示节点并保留离线选择，`r13_07_autoheal_offline.png`），并按 `lastErrorAt` 做 10 分钟退避，避免订阅地址失效时每分钟打网络。离线 TCP 测速与切换在补齐缓存后实测可用：单节点 379 ms（`r13_04_offline_latency.png`）、点选「SG新加坡•移联01」写入 `proxies/selection_state.json` 且节点卡/组卡/侧栏同步（`r13_05_offline_select.png`）、移动宽度双列节点卡与选中描边正常（`r13_06_mobile_offline.png`）。本轮未启动内核、未改注册表（复查 `ProxyEnable=0` / `ProxyServer=127.0.0.1:2080`），`settings.json`（`D6CAE03D…2316`）、`subscriptions/subscriptions_list.json`（`B563ACDC…614C`）、`subscriptions/selection_state.json`（`2096D205…1FBA`）、`proxies/selection_state.json`（`65EE3813…84C1F`）四个文件按备份逐字节还原并核对 SHA256 一致，含订阅令牌的两份备份已删除；测试中补齐的 `subscriptions/profiles/07625888…3013.yaml`（34,726 B）作为用户订阅缓存保留
- 2026-10-29 代理页头部与节点卡片改版（1300×860 桌面与 460×900 移动宽度、浅色、用户真实订阅离线态实屏截图，产物 `build/verify_r14/r14_*.png`）：① 头部「测速全部」由胶囊改为图标按钮（仪表盘图标 + 悬停提示），桌面右上角只剩该图标，移动端顶部图标行保留搜索与「测速全部」，原先桌面头部、移动图标行与「无分组」空状态的三处刷新按钮全部删除（节点由内核事件与 8 秒轮询自动刷新）；点击图标后 25 个节点在数秒内出现 70–112 ms 延迟并按延迟重排（`r14_12_desktop_testall_tooltip.png`、`r14_15`/`r14_16`）。② 显示选项「⋯」从搜索框右侧移到页面左上角：桌面位于「代理」标题左侧（`PageHeader.leading`），移动端位于图标行最左（`MobilePageHeader` 新增 `leading` 插槽），菜单锚点由右上角 `bottomEnd` 改为左上角 `bottomStart`，浮层与按钮左缘对齐向下展开（桌面 `r14_02_menu_open.png`、移动 `r14_10_mobile_menu.png`）。③ 二级菜单改为仅点击展开：`SubmenuButton` 的 `hoverOpenDelay` 设为 1 天以屏蔽悬停自动展开，每个子菜单单独持有 `MenuController` 并在 `onOpen` 时关闭其它子菜单，保证同时只开一个——悬停「风格」2 秒不展开（`r14_03_hover_style_no_open.png`），点击后展开「标签页 / 列表」（`r14_04_click_style_open.png`），此时悬停「排序」不切换、点击才切换且「风格」子菜单关闭（`r14_05_hover_sort_keeps_style.png`、`r14_06_click_sort_single_open.png`）；移动宽度下子菜单在 460px 屏幕内不出屏（`r14_11_mobile_submenu.png`）。④ 桌面节点磁贴按参考稿改为两行带边框卡片：1px `palette.border` 描边、名称在上（字号随尺寸档位），类型在左下、彩色延迟在右下，延迟为纯色文本（无胶囊底与行首圆点）且可点击测速，选中态为 `accentSoft` 底 + 1.2px 主题色描边 + 名称右侧对勾；实测点击卡片右下「—」后出现「99 ms」并触发按延迟重排（`r14_07_selected_card.png`、`r14_08_delay_test.png`、`r14_14_cards_zoom.png`），`_NodeScale.rowPadding` 随之移除。本轮未启动内核、未改注册表（复查 `ProxyEnable=0` / `ProxyServer=127.0.0.1:2080`），`settings.json`（`FF338042…2B5`）、`subscriptions/subscriptions_list.json`（`A9CF8652…C23`）、`subscriptions/selection_state.json`（`2096D205…1FBA`）、`proxies/selection_state.json`（`AC789532…AB66`）四个文件按备份逐字节还原并核对 SHA256 一致，含令牌的备份已删除，无 `clash_go` 进程残留
- 2026-10-29 显示选项回到右上角、订阅导入收进「+」（1300×860 桌面与 460×900 移动宽度、浅色实屏截图，产物 `build/verify_r15/r15_*.png`）：① 代理页「⋯」从左上角移回页面右上角：桌面位于「测速全部」图标之后、页面最右，移动端图标行从左到右为搜索 / 测速全部 / ⋯（`r15_02_desktop_proxy.png`、`r15_10_mobile_proxy.png`）；菜单锚点相应改回 `bottomEnd`，并按实测菜单宽 244px（行内容 168 + 二级箭头区 28 + 菜单行左右 32 + 浮层内边距 16）计算偏移，浮层与按钮右缘对齐、右缘内收 8px（像素扫描得浮层 x=1012..1255，与订阅页「+」菜单同一规则）；一级菜单行补足二级箭头所占的 28px，悬停块铺满整行不再短一截（`r15_03_desktop_menu.png`、`r15_11_mobile_menu.png`）；二级菜单仍为仅点击展开、同时只开一个，贴右缘时向左展开，桌面与 460px 移动宽度下均不出屏（`r15_05_desktop_style_submenu.png`、`r15_15_mobile_style_submenu.png`、`r15_16_mobile_hover_no_open.png`）。② 订阅页三种添加方式全部收进右上角「+」下拉菜单：桌面/移动页头只留「+」在最右（桌面在「更新全部」右侧），菜单内为订阅链接 / 本地文件 / 二维码图片（桌面）、扫描二维码（移动）（`r15_06_desktop_subscriptions.png`、`r15_07_desktop_add_menu.png`、`r15_08_mobile_subscriptions.png`、`r15_09_mobile_add_menu.png`）；原先桌面三枚平铺胶囊、移动端「+」的底部弹窗以及两端空状态里的导入按钮全部删除，空状态只保留文案「点击右上角 +，添加订阅链接、本地文件或二维码」（`r15_17_desktop_empty.png`、`r15_19_mobile_empty.png`、`r15_18_desktop_empty_menu.png`、`r15_21_mobile_empty_menu.png`），点「订阅链接」正常打开「添加订阅」对话框（`r15_20_mobile_add_dialog.png`、`r15_22_mobile_add_dialog.png`）。本轮未启动内核、未改注册表（复查 `ProxyEnable=0` / `ProxyServer=127.0.0.1:2080`）；因用户交付版实例自 19:08 起运行并占用 `E:\Test`，验证改用临时 `CLASHGO_HOME` 指向 `build/verify_r15/home` 并注入合成订阅完成，未与用户实例共用数据目录与端口；验证后删除隔离目录并还原 `app_paths.dart`，用户 `settings.json`（`FF338042…2B5`）、`subscriptions/subscriptions_list.json`（`A9CF8652…C23`）、`subscriptions/selection_state.json`（`2096D205…1FBA`）、`proxies/selection_state.json`（`AC789532…AB66`）四个文件 SHA256 与测试前完全一致

Android：

- VPN 授权 → 前台服务启动 → mihomo 启动 → `tun0` 建立（`198.18.0.1/30`，MTU 9000，gVisor），内核日志确认 `[TUN] Tun adapter listening at: tun0(fd=1000)`
- TUN 数据面：设备内 `/system/bin/curl https://www.gstatic.com/generate_204` → `204`；`http://1.1.1.1` → `301`；`https://www.baidu.com` → `200`
- 混合端口经 `adb forward` 访问 → `204`；API 端口返回 `401`（鉴权生效）
- 真实机场订阅：策略组 58 个节点，整组测速 78 ms（自动选择）；切换至「香港高速02 BGP CMCU」后首页显示 84 ms，TUN 仍 `204`（0.38 s）
- 停止：mihomo 退出、TUN 关闭、混合端口不再监听、前台服务销毁、UI 计数归零；重复启动正常
- 退回桌面后 VPN 与流量保持；重新打开应用可继续显示运行时长/节点状态
- 通知栏常驻通知与「停止」动作已注册（`actions=1`，`PendingIntent` → `CoreVpnService`），授予通知权限后正常显示
- 新版移动端主页真机截图验证（1440×3200）：状态栏、VPN 标识、订阅流量 3.1 TB / 5 TB、IP 与节点区域、底部四导航均正常；受设备 `INJECT_EVENTS` 限制无法自动切换其余标签页，代理/订阅/设置已在 Windows 420×900 同布局下逐页验证
- 后台节流复用同一生命周期入口：切后台（`hidden`/`paused`）停止 UI 侧 WebSocket、轮询与自动更新，回前台（`resumed`）恢复；VPN 前台服务与 mihomo 子进程不受影响

构建与静态检查：`flutter analyze` 无告警；`flutter test` 21/21 通过（`widget_test.dart` 9 例 + `qr_import_test.dart` 4 例 + `proxy_display_menu_test.dart` 8 例）；`flutter build windows --release` 与 `flutter build apk --release --target-platform android-arm64 --split-per-abi` 均成功（`app-arm64-v8a-release.apk`，42.8 MB，仅 arm64-v8a，SHA256 `101AD5CA…EA5A`；Windows 交付目录 75 个文件，`data/app.so` SHA256 `4A7304BD…A278`，`clash_go.exe` SHA256 `0611F499…5315`）。

未验证项：HyperOS 折叠通知栏在自动化环境下无法展开并点击「停止」按钮（动作本身已注册且停止逻辑已通过应用内按钮验证）；Windows 开机自启未实现，设置中的「启动时自动运行」指应用打开后自动启动内核（已实机验证）；底部导航滑动动画、后台节流、本轮首页仪表盘与下拉菜单调整均在 Windows 实屏验证，Android 仅完成编译打包、未在真机复测（本次无 Android 设备连接）；本轮的设置行悬停圆角裁剪与按钮字体继承、停止按钮配色、侧边栏图标与移动节点选中框同样在 Windows（桌面与移动宽度、明暗主题）实屏验证，Android 仅编译通过；系统代理默认开启的旧配置迁移、停止按钮去描边与底部菜单圆角裁剪已在 Windows 浅色/深色、桌面与移动宽度实屏验证，Android 端系统代理开关本身不适用（走 VPN），仅编译通过；本轮全部下拉菜单的新浮层样式（含深色 1px 描边与订阅卡片「更多」菜单改 `MenuAnchor`）同样只在 Windows 浅色/深色、1384×861 与 604×901 实屏验证，Android 端仅编译打包、未真机复测；订阅页移动端菜单改浮层下拉与底栏缩小同样只在 Windows 移动宽度（491×901）浅色/深色实屏验证，Android 端仅编译打包（底栏在真机上的安全区高度会再叠加 `viewPadding.bottom`，未实测）；空订阅状态下的仪表盘数值为占位符，未注入真实订阅复核流量/到期回显；本轮的安卓摄像头扫码（mobile_scanner 预览、相机权限弹窗与实时识别）只完成编译打包与解码链路单元测试，未连真机复测（本次无 Android 设备连接），Windows 端走的是「选择二维码图片」分支并已实屏验证；代理页嵌套菜单的触摸交互（子菜单点击热区、`closeOnActivate` 手感）在 Windows 移动宽度（422px）与桌面宽度实屏验证，真机触摸与状态栏安全区未复测。离线缓存自愈的三条链路里，代理页按钮与自动更新自愈在 Windows 实屏验证，`startCore` 前的 `ensureProfile` 只做了代码级复核（本轮未启动内核，避免改动系统代理），「更新订阅」失败时的「获取订阅失败」提示同样未制造断网场景实屏触发；Android 端本轮仅编译打包，离线缓存自愈与更新按钮未在真机复测；本轮代理页「测速全部」图标化、显示选项移到左上角（二级菜单仅点击展开）与两行带边框节点卡片只在 Windows 浅色下以 1300×860 桌面与 460×900 移动宽度实屏验证，深色主题、真机触摸热区与 Android 端未复测（仅编译打包）。本轮「⋯」回到右上角（菜单宽 244px、右缘内收 8px、二级菜单左翻）与订阅页三入口收进「+」同样只在 Windows 浅色下以 1300×860 桌面与 460×900 移动宽度实屏验证，深色主题、订阅「+」菜单在真机上的触摸热区与 Android 端未复测（仅编译打包）。

---

## 许可证与致谢

本项目以 **GPL-3.0** 发布，详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

- 原始项目：[ChenL-eon/ClashGo-legacy](https://github.com/ChenL-eon/ClashGo-legacy)（Android，GPL-3.0）——品牌、图标与交互灵感
- 设计参考：[YuKongA/Mishka](https://github.com/YuKongA/Mishka)
- 代理内核：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0），`core/mihomo.exe` 与 geodata 来自其发布产物
- Flutter 及 `pubspec.yaml` 中的开源依赖各自遵循其许可证

本项目与上述上游组织无隶属关系。请遵守当地法律法规及服务提供商条款，仅将代理功能用于合法用途。
