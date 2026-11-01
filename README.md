<p align="center">
  <img src="assets/brand/app_icon_256.png" width="112" alt="Clash Go" />
</p>

<h1 align="center">Clash Go</h1>

<p align="center">
  <strong>轻量、完整的 mihomo 客户端 · Windows &amp; Android</strong>
</p>

Clash Go 是一款使用 Flutter 编写的 mihomo（Clash Meta）图形客户端，同一套 Material 3 界面同时覆盖 Windows 与 Android。Windows 支持系统代理与 TUN 两种接管方式，Android 通过 VpnService + TUN 接管设备流量；订阅、节点、连接、日志、规则、DNS 与代理提供者管理都可以在界面内完成，内置 mihomo v1.19.33，无需额外部署内核。

> A Flutter-based mihomo client for Windows and Android, with system proxy and TUN support.

<p align="center">
  <a href="https://github.com/ChenL-eon/ClashGo/releases/latest"><img src="https://img.shields.io/github/v/release/ChenL-eon/ClashGo?style=for-the-badge&amp;logo=github&amp;color=238636&amp;label=Release" alt="Latest Release" /></a>
  <a href="https://github.com/ChenL-eon/ClashGo/releases/latest"><img src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android-2F81F7?style=for-the-badge" alt="Platform" /></a>
  <a href="https://github.com/MetaCubeX/mihomo/releases"><img src="https://img.shields.io/badge/Core-mihomo%20v1.19.33-8A2BE2?style=for-the-badge&amp;logo=go&amp;logoColor=white" alt="Core" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/ChenL-eon/ClashGo?style=for-the-badge&amp;color=blue&amp;label=License" alt="License" /></a>
</p>

---

## 核心特性

- **双平台完整链路**：Windows 提供系统代理与 TUN 两种接管方式，同一时间只启用一种；Android 通过 VpnService 建立 TUN，接管设备 DNS 与 TCP/UDP 流量。两端共享同一套订阅、节点与运行状态界面。
- **开箱即用**：Windows 安装包、便携包与 Android APK 均内置 mihomo v1.19.33 与 geodata；Windows 侧无需手动下载 Wintun 驱动，首次开启 TUN 时由内核自动安装。
- **订阅管理**：支持订阅链接、本地 YAML 与二维码导入；手动/自动更新、一键更新全部订阅（逐个汇报成功与失败数量）、更新间隔、流量与到期信息、重命名与删除（同时清理运行时配置）。
- **节点与策略**：策略组与节点列表、单节点/整组/全部延迟测试、节点选择记忆、规则/全局/直连模式切换；内核未启动时也能离线预览订阅节点并做 TCP 测速。
- **运行可视化**：首页展示出口 IP 与节点地区旗帜、实时流量曲线；连接列表与详情、按主机/规则/进程搜索、内核日志与级别筛选、生效规则查询、DNS 记录查询、代理提供者更新与健康检查。
- **Windows 接管**：系统代理在启动内核后自动写入，停止内核或退出应用时还原；TUN 只提权内核进程，界面保持普通权限，通常每次以 TUN 启动内核会请求一次 UAC 授权；路由与 DNS 全接管，停止 TUN 后不会擅自改回系统代理。
- **Android 接管**：VpnService 前台服务、VPN 授权流程、退回后台保持隧道；通知栏显示当前节点与实时上下行速率，并可直接停止内核。
- **界面与个性化**：桌面侧边栏与移动端悬浮胶囊导航自适应（窗口宽度小于 1000px 时切换移动布局）；跟随系统/浅色/深色/纯黑、6 种主题色、中英文切换；设置项支持搜索直达。
- **后台与功耗**：应用退到后台后停止 UI 侧 WebSocket、连接/代理轮询、延迟探测与订阅自动更新，只保留内核进程与 Android VPN 前台服务；未引入 WakeLock 或 AlarmManager 保活。
- **应用更新与隐私**：关于页支持稳定/预览双通道检查 GitHub Release，可设置启动时检查；无账号、无广告、无遥测，API 默认只监听 `127.0.0.1`，订阅与配置全部保存在本机。

---

## 安装与下载

前往 [Releases](https://github.com/ChenL-eon/ClashGo/releases) 下载当前正式版 **v1.1.0**：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Windows 10/11 x64 | [`ClashGo-1.1.0-windows-x64-setup.exe`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.1.0/ClashGo-1.1.0-windows-x64-setup.exe) | Inno Setup 安装包，默认装到 `Program Files\ClashGo`，需要管理员权限，含开始菜单与可选桌面快捷方式 |
| Windows 10/11 x64 | [`ClashGo-1.1.0-windows-x64-portable.zip`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.1.0/ClashGo-1.1.0-windows-x64-portable.zip) | 便携包，解压到任意目录后运行 `clash_go.exe` |
| Android 7.0+ | [`ClashGo-1.1.0-android-arm64-v8a.apk`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.1.0/ClashGo-1.1.0-android-arm64-v8a.apk) | 适用于绝大多数现代手机与平板，推荐优先选择 |
| Android 7.0+ | [`ClashGo-1.1.0-android-armeabi-v7a.apk`](https://github.com/ChenL-eon/ClashGo/releases/download/v1.1.0/ClashGo-1.1.0-android-armeabi-v7a.apk) | 适用于 32 位 ARM 老设备；该内核已完成编译与打包验证，尚未在 32 位真机复测 |

各产物的 SHA-256 校验值见对应 Release 说明。

**Windows 注意事项**

- 当前构建未做商业代码签名。SmartScreen 提示「Windows 已保护你的电脑」时，选择「更多信息 → 仍要运行」。
- TUN 需要创建虚拟网卡并修改路由表，因此只对内核进程提权，主界面仍以普通权限运行。首次开启 TUN 会在系统中安装 Wintun 虚拟网卡驱动，需要多等几秒。
- 系统代理与 TUN 互斥：开启其中一个会自动关闭另一个；关闭 TUN 后不会自动恢复系统代理，需要时在首页手动开启。

**Android 注意事项**

- APK 目前使用 debug 签名。设备上若已安装同包名但签名不同的版本，需要先卸载再安装。
- 首次启动内核会请求 VPN 授权；Android 13 及以上还需要授予通知权限，否则前台通知不会显示。
- 通知栏在息屏时会暂停速率刷新以省电，亮屏后自动恢复。

---

## 快速开始

1. 打开「订阅」，点击右上角「+」，通过订阅链接、本地 YAML 或二维码添加入口导入配置。
2. 回到首页点击「启动」。内核启动后即可在「代理」页选择策略组与节点。
3. 选择接管方式：
   - Windows：默认开启系统代理；需要全局接管时在首页切换到 TUN，并在 UAC 弹窗中确认。
   - Android：首次启动会请求 VPN 授权，授权后设备流量自动经 TUN 接管。
4. 在「代理」页测速并切换节点；在「连接」「日志」「规则」「DNS」「代理提供者」中查看运行状态。
5. 默认混合端口为 `17890`，API 端口为 `19090`。若端口被占用，可在「设置 → Clash 特性」中修改后重启内核。

> API 默认仅监听 `127.0.0.1`。只有开启「允许局域网连接」后，同一网络的设备才能使用本机代理。

---

## 平台支持

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| Windows 10/11 x64 | 完整链路，已实机验证 | 系统代理与 TUN、订阅、节点、连接、日志、DNS、规则、提供者全流程可用 |
| Android 7.0+ arm64-v8a | 完整链路，已实机验证 | VpnService + TUN、节点切换、前台服务与通知栏状态 |
| Android 7.0+ armeabi-v7a | 完整链路，构建验证 | 内置 32 位内核，未在 32 位真机复测 |

暂不支持：Windows ARM64、macOS/Linux/iOS、root/TPROXY、按应用代理、WebDAV、Wi-Fi 策略。

---

## 常见问题

1. **Windows 提示未知发布者或 SmartScreen 拦截**
   当前构建未购买代码签名证书，属于预期现象。确认文件来自本仓库的 Releases 后，选择「更多信息 → 仍要运行」即可。

2. **Windows 开启 TUN 后没有流量**
   先在 UAC 弹窗中允许提权；确认没有同时开启系统代理；关闭其他会创建虚拟网卡或占用端口的代理工具；查看「日志」中是否出现 `Tun adapter listening`。首次启用还需要等待 Wintun 驱动安装完成。

3. **停止内核后系统代理没有恢复，或关闭 TUN 后没有自动切回系统代理**
   停止内核或退出应用时，系统代理会还原为启动前保存的设置。手动关闭系统代理的选择会被记住；关闭 TUN 不会替用户重新开启系统代理，需要在首页手动切换。

4. **Android 安装失败或覆盖安装失败**
   当前 APK 使用 debug 签名。若设备上已有同包名、不同签名的版本，请先卸载旧版本，再安装新包。

5. **Android 后台运行一段时间后连接中断**
   VPN 前台服务会随内核保持运行，但部分系统的省电策略仍可能结束后台进程。请在系统设置中允许 Clash Go 后台运行，并保持通知权限开启。

6. **订阅导入或更新失败**
   先在服务商后台重置订阅链接后重试，并确认内容是可解析的 Clash/mihomo YAML。更新失败后应用会在 10 分钟内暂停重试，避免反复请求失效地址。

7. **检查更新失败**
   应用更新检查依赖 GitHub。网络无法直连 GitHub 时，请先让系统代理或 TUN 正常工作，再重试。

---

## 从源码构建

### 环境

- Flutter 3.47.x（Dart 3.13.5+）
- Windows：Visual Studio 2022，含「使用 C++ 的桌面开发」
- Android：Android SDK 36、JDK 21（仅构建 APK 时需要）
- 安装包：Inno Setup 6（仅生成 Windows 安装包时需要）
- 内核：`core/mihomo.exe`、`core/geodata/` 与两端 `libmihomo.so` 已随仓库提供

### Windows

```bash
flutter pub get
flutter build windows --release
# 产物：build/windows/x64/runner/Release/
```

构建过程会把 `core/mihomo.exe` 与 `core/geodata` 复制到产物目录。调试可直接运行 `flutter run -d windows`。

生成安装包：

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" tool\windows_installer.iss
# 产物：build/release/ClashGo-1.1.0-windows-x64-setup.exe
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

APK 内置 `libmihomo.so` 与 geodata，无需额外下载。Android 内核由 mihomo v1.19.33 源码以 `-tags "with_gvisor cmfa"` 编译：官方 Android 二进制在 TUN 初始化时会读取普通应用无权访问的 `/data/system/packages.xml`，`cmfa` 标签会跳过这段包名规则构建。替换内核时需要保留该标签。

### 检查

```bash
flutter analyze
flutter test
```

---

## 数据目录

Windows：`%APPDATA%\com.clashgo\clash_go\`

Android：`/data/user/0/com.clashgo.clash_go/files/`（应用私有目录）

```text
settings.json            应用设置
subscriptions/           订阅列表、配置文件与选择记忆
runtime/                 运行时配置 config.yaml、core.log、内核缓存与 geodata
proxies/                 节点选择状态
```

删除最后一个订阅时，应用会停止内核并清理运行时生成的配置与提供者缓存。

---

## 项目结构

```text
lib/
  core/          应用信息、路径、错误、格式化、主题、i18n
  models/        订阅、设置、代理、连接、规则、DNS、提供者等模型
  data/          本地持久化
  services/      mihomo API/WebSocket、内核管理、配置生成、订阅抓取、系统代理、TUN 提权
  controllers/   应用状态与业务编排（ChangeNotifier）
  ui/            设计系统、Shell、四个主页面与工具页面
assets/          品牌图、图标、geodata
core/            Windows 内核与 geodata
tool/            Windows 安装包脚本
windows/ · android/  平台工程
test/            单元与组件测试
docs/            验证记录
```

---

## 验证与测试

交付前执行：

- `flutter analyze`：0 issues
- `flutter test`：98 项测试全部通过
- `flutter build windows --release` 与 arm64 / armeabi-v7a APK 构建成功
- Windows 11 x64 实机：系统代理与 TUN 启停、路由与 DNS 接管、UAC 授权流程、Wintun 首次安装
- Android 真机：VPN 授权、TUN 数据面、节点切换、前台服务与停止

逐条历史记录见 [docs/VERIFICATION.md](docs/VERIFICATION.md)。

---

## 致谢

- 原始项目：[ChenL-eon/ClashGo-legacy](https://github.com/ChenL-eon/ClashGo-legacy)（Android，GPL-3.0）——品牌、图标与交互灵感
- 设计参考：[YuKongA/Mishka](https://github.com/YuKongA/Mishka)
- 代理内核：[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0），`core/mihomo.exe`、`libmihomo.so` 与 geodata 来自其源码与发布产物
- README 结构与排版参考：[appshubcc/Bettbox](https://github.com/appshubcc/Bettbox)
- [Flutter](https://flutter.dev) 及 `pubspec.yaml` 中的开源依赖各自遵循其许可证

感谢所有上游作者与贡献者。本项目与上述组织无隶属关系。

---

## 开源协议

本项目采用 [GPL-3.0 License](LICENSE) 开源协议，第三方组件与上游项目的授权说明见 [NOTICE](NOTICE)。

本项目不提供任何代理服务或订阅。请遵守当地法律法规及服务提供商条款，仅将代理功能用于合法用途。
