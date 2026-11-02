<p align="center">
  <img src="assets/brand/app_icon_256.png" width="112" alt="ClashGo" />
</p>

<h1 align="center">ClashGo</h1>

<p align="center">
  <strong>轻量、完整的 mihomo 客户端 · Windows &amp; Android</strong>
</p>

ClashGo 是一款使用 Flutter 编写的 mihomo（Clash Meta）图形客户端，同一套 Material 3 界面同时覆盖 Windows 与 Android，内置 mihomo v1.19.33，无需额外部署内核。Windows 支持系统代理与 TUN，Android 通过 VpnService + TUN 接管流量；订阅、节点、连接、日志、规则、DNS 与代理提供者均可在界面内管理。

> A Flutter-based mihomo client for Windows and Android, with system proxy and TUN support.

<p align="center">
  <a href="https://github.com/ChenL-eon/ClashGo/releases/latest"><img src="https://img.shields.io/github/v/release/ChenL-eon/ClashGo?style=for-the-badge&amp;logo=github&amp;color=238636&amp;label=Release" alt="Latest Release" /></a>
  <a href="https://github.com/ChenL-eon/ClashGo/releases/latest"><img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android-2F81F7?style=for-the-badge" alt="Platform" /></a>
  <a href="https://github.com/MetaCubeX/mihomo/releases"><img src="https://img.shields.io/badge/Core-mihomo%20v1.19.33-8A2BE2?style=for-the-badge&amp;logo=go&amp;logoColor=white" alt="Core" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ChenL-eon/ClashGo?style=for-the-badge&amp;color=blue&amp;label=License" alt="License" /></a>
</p>

---

## 核心特性

- **双平台接管**：Windows 提供系统代理与 TUN 两种方式，同一时间只启用一种；Android 通过 VpnService 建立 TUN，接管设备 DNS 与 TCP/UDP 流量，前台通知显示当前节点与实时上下行速率并可直接停止内核。
- **开箱即用**：安装包、便携包与 APK 均内置 mihomo v1.19.33 与 geodata；Windows 首次开启 TUN 时由内核自动安装 Wintun 驱动。
- **订阅与节点**：支持链接、本地 YAML、二维码与剪贴板导入，Android 可直接打开 `clash://` 订阅链接；手动/自动/全部更新、手动排序、更新间隔、流量与到期信息，每个订阅可单独选择更新时是否经内核代理（默认直连）；策略组与节点切换、规则/全局/直连模式、单节点/整组/全部测速、离线预览与 TCP 测速，结果按订阅保存、重启后仍保留。
- **预览内核**：未接管流量时按需起一个只服务 `/proxies` 与测速的 mihomo（Windows 普通进程、Android 无 VpnService 的 fork+exec），节点列表与延迟来自真实代理；窗口最小化、收进托盘或应用退到后台即停，界面恢复后自动回来。它与接管内核互斥，接管中不并存。
- **运行可视化**：首页出口 IP 与地区旗帜、实时流量曲线；连接列表与搜索、日志筛选、生效规则查询、DNS 记录查询、代理与规则提供者更新、健康检查。
- **配置与分流**：Android 分应用代理（全部应用 / 仅代理所选 / 排除所选，支持搜索与全选）；DNS 配置（fake-ip / redir-host、主备 DNS、追加系统 DNS）；Hosts 覆盖（域名到 IP/目标域名的本地映射，同名条目覆盖订阅与 YAML 覆写）；内核选项（统一延迟、TCP 并发、Geo 低内存模式）；YAML 配置覆写；备份导出与整包恢复（设置、订阅原文、节点选择与测速结果）。
- **桌面常驻**：Windows 支持登录自启、关闭到托盘、托盘菜单快速显隐与启停内核；系统代理绕过列表可在设置中编辑；支持在线检查并更新本地 mihomo 内核。
- **界面与个性化**：桌面侧边栏 / 移动悬浮导航自适应（窗口宽度小于 1000px 切移动布局）、跟随系统/浅色/深色/纯黑、6 种主题色、中英文切换、设置搜索直达；策略组标签过多时自动换行，不再挤进无法横向滚动的单行。
- **后台与隐私**：退到后台后停止 UI 侧 WebSocket、连接/代理轮询、延迟探测与订阅自动更新，仅保留内核与 Android VPN 前台服务；未引入 WakeLock 或 AlarmManager。无账号、无广告、无遥测，API 默认只监听 `127.0.0.1`，配置全部保存在本机。
- **应用更新**：关于页支持稳定/预览双通道检查 GitHub Release，可设置启动时检查。

---

## 安装与下载

前往 [Releases](https://github.com/ChenL-eon/ClashGo/releases) 下载当前正式版 **v1.4.0**，各产物 SHA-256 见 Release 说明。

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Windows 10/11 x64 | [`ClashGo-1.4.0-windows-x64-setup.exe`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.4.0/ClashGo-1.4.0-windows-x64-setup.exe) | Inno Setup 安装包，需管理员权限；默认装到 `Program Files\ClashGo`，含开始菜单与可选桌面快捷方式 |
| Windows 10/11 x64 | [`ClashGo-1.4.0-windows-x64-portable.zip`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.4.0/ClashGo-1.4.0-windows-x64-portable.zip) | 便携包，解压后运行 `clash_go.exe` |
| Android 7.0+ | [`ClashGo-1.4.0-android-arm64-v8a.apk`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.4.0/ClashGo-1.4.0-android-arm64-v8a.apk) | 适用于绝大多数现代手机与平板，推荐优先选择 |
| Android 7.0+ | [`ClashGo-1.4.0-android-armeabi-v7a.apk`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.4.0/ClashGo-1.4.0-android-armeabi-v7a.apk) | 适用于 32 位 ARM 老设备；已完成构建与打包验证，未在 32 位真机复测 |

**注意事项**

- **Windows**：当前构建未做商业代码签名，SmartScreen 提示时选择「更多信息 → 仍要运行」。TUN 只对内核进程提权（每次以 TUN 启动通常请求一次 UAC），主界面保持普通权限；首次开启需要多等几秒安装 Wintun 驱动。系统代理与 TUN 互斥，关闭 TUN 后不会自动恢复系统代理。
- **Android**：APK 使用 debug 签名，同包名不同签名需先卸载再安装；首次启动内核会请求 VPN 授权，Android 13+ 还需授予通知权限。息屏时通知栏速率刷新暂停以省电，亮屏后恢复。
- **平台支持**：Windows 10/11 x64 与 Android 7.0+ arm64-v8a 完整链路已实机验证；armeabi-v7a 仅构建验证；Android 分应用代理本轮完成构建与界面回归，尚未在真机复测。暂不支持 Windows ARM64、macOS/Linux/iOS、Windows 按应用代理、root/TPROXY、WebDAV、Wi-Fi 策略。

---

## 快速开始

1. 打开「订阅」，点击右上角「+」，通过订阅链接、本地 YAML 或二维码导入配置。
2. 回到首页点击「启动」，然后在「代理」页测速并选择策略组与节点。
3. 选择接管方式：Windows 默认开启系统代理，需要全局接管时切到 TUN 并在 UAC 中确认；Android 授权 VPN 后自动接管。
4. 默认混合端口 `17890`、API 端口 `19090`，可在「设置 → Clash 特性」中修改后重启内核。

> API 默认仅监听 `127.0.0.1`；开启「允许局域网连接」后，同一网络的设备才能使用本机代理。

---

## 常见问题

- **Windows 提示未知发布者 / SmartScreen 拦截**：未购买代码签名，属预期现象；确认文件来自本仓库 Releases 后选择「更多信息 → 仍要运行」。
- **Windows 开启 TUN 后没有流量**：先在 UAC 中允许提权，确认没有同时开启系统代理，关闭其他虚拟网卡或端口占用工具；日志出现 `Tun adapter listening` 即正常，首次还需等待 Wintun 安装完成。
- **停止内核后系统代理没有恢复 / 关闭 TUN 后没切回系统代理**：系统代理会还原为启动前保存的设置，手动关闭的选择会被记住；关闭 TUN 不会替用户重新开启系统代理，属设计行为。
- **Android 后台运行一段时间后连接中断**：VPN 前台服务随内核保持，但部分系统的省电策略仍可能结束后台进程；请在系统设置中允许 ClashGo 后台运行并保留通知权限。
- **订阅导入或更新失败**：在服务商后台重置订阅链接后重试，确认内容是 Clash/mihomo YAML；失败后应用会在 10 分钟内暂停重试。
- **检查更新失败**：依赖 GitHub，网络无法直连时请先让系统代理或 TUN 正常工作再重试。

---

## 从源码构建

**环境**：Flutter 3.47.x（Dart 3.13.5+）；Windows 需 Visual Studio 2022（含「使用 C++ 的桌面开发」）；Android 需 SDK 36 与 JDK 21；生成安装包需 Inno Setup 6。`core/` 与两端 `libmihomo.so` 已随仓库提供。

### Windows

```bash
flutter pub get
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
```

构建过程会复制 `core/mihomo.exe` 与 `core/geodata`；调试可直接 `flutter run -d windows`。生成安装包：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" tool\windows_installer.iss
# 产物：build/release/ClashGo-1.4.0-windows-x64-setup.exe
```

便携包直接压缩 `build/windows/x64/runner/Release` 整个目录。

### Android

```bash
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --split-per-abi
# 产物：
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
```

APK 内置 `libmihomo.so` 与 geodata。Android 内核由 mihomo v1.19.33 源码以 `-tags "with_gvisor cmfa"` 编译：官方 Android 二进制会读取普通应用无权访问的 `/data/system/packages.xml`，`cmfa` 标签会跳过这段包名规则构建，替换内核时需保留该标签。

检查：`flutter analyze`、`flutter test`。

---

## 数据目录

Windows：`%APPDATA%\com.clashgo\clash_go\`；Android：`/data/user/0/com.clashgo.clash_go/files/`（应用私有目录）。

```text
settings.json            应用设置
subscriptions/           订阅列表、配置文件与选择记忆
runtime/                 运行时 config.yaml、core.log、内核缓存与 geodata
proxies/                 节点选择状态
```

删除最后一个订阅时，应用会停止内核并清理运行时生成的配置与提供者缓存。

---

## 项目结构

```text
lib/             core（应用信息/路径/主题/i18n）、models、data、services（API/内核/配置/接管）、
                 controllers（ChangeNotifier）、ui（设计系统/Shell/页面）
assets/          品牌图、图标、geodata
core/            Windows 内核与 geodata
tool/            Windows 安装包脚本
windows/ · android/ · test/ · docs/（验证记录）
```

---

## 验证与测试

交付前执行：`flutter analyze` 无 error/warning；`flutter test` 全绿；Windows release 与 arm64 / armeabi-v7a APK 构建成功。Windows 11 x64 实机覆盖系统代理与 TUN 启停、路由与 DNS 接管、UAC 授权、Wintun 首次安装；Android 真机覆盖 VPN 授权、TUN 数据面、节点切换、前台服务与停止。1.4.0 这轮 `flutter test` 整包单进程 206 项通过、30 项因 `flutter_tester` 未完成被中断，涉及的四个文件逐文件复跑全绿（12/11/3/5）。逐条记录见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

---

## 致谢

- 原始项目：[ChenL-eon/ClashGo-legacy](https://github.com/ChenL-eon/ClashGo-legacy)（Android，GPL-3.0）——品牌、图标与交互灵感
- 设计参考：[YuKongA/Mishka](https://github.com/YuKongA/Mishka)
- 代理内核：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0），`core/mihomo.exe`、`libmihomo.so` 与 geodata 来自其源码与发布产物
- README 排版参考：[appshubcc/Bettbox](https://github.com/appshubcc/Bettbox)；[Flutter](https://flutter.dev) 及 `pubspec.yaml` 中的依赖各自遵循其许可证

感谢所有上游作者与贡献者。本项目与上述组织无隶属关系。

---

## 开源协议

本项目采用 [GPL-3.0 License](LICENSE) 开源协议，第三方组件与上游项目的授权说明见 [NOTICE](NOTICE)。本项目不提供任何代理服务或订阅。请遵守当地法律法规及服务提供商条款，仅将代理功能用于合法用途。
