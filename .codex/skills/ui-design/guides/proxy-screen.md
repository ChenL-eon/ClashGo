# 代理页

## 横向标签与纵向分组

- 默认用文字 + 下划线的横向标签，选中态用主题主色，标签透明，点击时无涟漪与容器背景。布局偏好存在 `PROXY_GROUP_TABS`。选中组按名字保存：全局模式会调整组顺序，搜索也会改变下标。
- 标签栏消费剩余的横向滚动与惯性，拖到边缘时外层主页保持不动；纵向余量交给外层。
- 横向模式直接展示节点，解除固定放在顶栏左侧，全量测速使用顶栏右侧入口；列表模式隐藏顶栏全量测速，每组卡片头自带组测速。标签位于顶栏下方（放进内容的 stickyHeader 会被顶栏遮住）。标签用横向懒列表，滚动位置与内容列表分开保存。每组内容用 `SaveableStateProvider` 保存位置，并在 ViewModel 缓存偏移（宽屏外壳会重建组合树）；展开集合也由 ViewModel 持有。切组用整视口淡入淡出；淡出的列表使用动画内容参数里的组快照，淡出期间显示的始终是旧组。
- 全局模式固定选中并展示 GLOBAL，与「显示 GLOBAL」开关无关。当前组消失或被搜索过滤掉时，展示第一个可见组。

## 展开与节点布局

- 分组卡片两行：组名；「类型 · 当前节点 · 已测可用数/总数」。已测可用数只计正延迟。右侧延迟数字只显示状态，组测速由展开按钮左侧的独立测速图标触发。
- 分组图标在图片加载成功后才显示，缺失或失败时不占位。
- 节点行始终是顶层 lazy item，从第一帧起就占满高度，懒列表只测量可见行（从 0 插值高度会让整组被当作首屏内容一次测完）。
- 展开用可见行的淡入与位置动画；收起直接移除节点行。组头与节点卡片各自是完整圆角。
- 分行按 1 / 2 / 3 列切分，对应布局的紧凑、标准、宽松；行内 Layout 按当前列数等宽排列，行参数为 `ImmutableList`。节点卡片尺寸独立分紧凑、标准、宽松，调整内边距、字号、圆角与行距。
- 排序、过滤、分行在构建 LazyColumn 内容前按组缓存。仅在按延迟排序或隐藏不可用节点时把延迟表纳入缓存键，普通测速回填保持默认顺序。
- 「仅显示可用节点」只排除已测且超时的节点，未测速的保留。搜索命中组名时显示整组，否则只展示命中的节点。
- 节点卡片首行是名称，第二行协议与延迟按基线对齐；左右留白相同，延迟靠右对齐。第二行保留最小高度，各测速状态下卡片高度一致，底部留 6.dp。延迟按钮与节点选择分别响应点击。
- 选中态只用侧边强调条与勾选，固定节点带图钉；背景与名称颜色同普通节点。
- 节点选择和解除固定只有内核成功后才更新界面与存储；失败原因经 `ProxyUiState.error` 交给页面显示本地化提示，提示后清空，连续失败也能反馈。

## 搜索

顶栏图标切换搜索框显隐，图标 `holdDownState` 跟随 `searchVisible`。收起时同时清空 query，列表回到完整内容。展开时用 SmallTopAppBar 默认居中的小标题，收起时恢复自适应大标题；展开后先把列表滚到顶，再 `FocusRequester.requestFocus()` 进入输入态。`filterGroups`：组名命中或组内有节点命中都保留该组。

## 空态

空态是一个居中的 lazy item，顶栏与列表结构保持可用。文案按 `groups.isEmpty()` 在「暂无代理组」与「搜索无命中」间选择；「请先启动代理服务」只在 `groups.isEmpty() && !isProxyRunning` 时出现（代理在跑而列表为空也是真实情形：只有 GLOBAL 组且用户隐藏了它）。

## 图标

- 顶栏在标签风格用 `AppIcons.TestDelay`（MingCute dashboard_2_line）测试所有节点延迟；全量测速期间保留图标、使用禁用色并禁止重复点击。列表风格隐藏该入口，在每个组头的展开按钮左侧放同一图标的组测速按钮，测速期间该按钮转圈并禁用。节点卡片的延迟区域无背景；未测速显示「—」，点击即测速；单个、批量与定时测速统一按当前仓库的实际请求状态，在节点延迟按钮处显示 `CircularProgressIndicator`。
- 展开按钮用 `AppIcons.ChevronRight`（right_small），旋转为向下或向上。
- 换图标时改 `gen_icons.py` 的 ICONS 表后重跑，调用点保持不变。

## 停止态

代理停止时由 `ProxyViewModel` 走离线会话，数据来自 `OfflineProxyRepository` 解析当前订阅配置，组、节点、provider 与运行态同形。排序、过滤、搜索、组切换、布局、尺寸、隐藏超时都直接消费 `ProxyUiState.groups`，不需要内核；选节点与解除固定写 `ProxySelectionStore`，下次启动时由运行态恢复。节点、组与全量测速在离线会话中进程内拨测，按钮不再受 `isRunning` 门控。

## 顶栏与代理设置

顶栏在标签风格放全量测速、搜索与更多菜单，列表风格只保留搜索与更多菜单；运行态组与节点随内核连接及轮询更新，停止态由离线快照填充。更多菜单使用 miuix `WindowCascadingListPopup`，保留默认定位和动画，第一层依次为滚动到已选、风格、排序、布局、尺寸、隐藏超时代理，随后是代理模式、GLOBAL 组；菜单内容超出屏幕时可滚动。

- 子菜单由 `DropdownItem.children` 声明，父菜单保留在后方；收起行为交给原生组件，不添加专用返回行。点选立即应用并收起菜单。风格、排序、布局、尺寸都是纯单选子菜单。
- 选路：代理模式使用单选子菜单。TUN Stack 不在此菜单，改在「设置 → Clash 特性 → 系统集成」的隧道配置块，非 ROOT TPROXY 模式显示，写入 `override.user.json` 的 `tun.stack` 并在代理运行时重启。
- 风格：标签页 / 列表单选。布局：紧凑 / 标准 / 宽松单选，分别对应 1 / 2 / 3 列，选项文案不显示列数。尺寸：紧凑 / 标准 / 宽松单选，只改节点卡片的内边距、字号与行距。
- 排序：默认 / 延迟 / 名称单选；`sortOption` 继续用 `key * 2 + reverse` 编码，但菜单不再提供倒序，只写偶数 key。
- 隐藏超时代理与 GLOBAL 组是开关；全局模式下 GLOBAL 始终开启并禁用开关。滚动到已选会展开选中组（列表模式）并滚到当前节点所在行。
- 自动测速间隔在订阅添加与编辑页管理。代理菜单只传值与回调；选路变更经 `HomeViewModel.applyProxyRouting` 保存 override 并调用 `restartWhenReady`，相同值不触发重启。

## 延迟检测地址

- 「设置 → Clash 特性 → 网络设置」的「统一延迟」上方是延迟检测链接：默认 `http://www.gstatic.com/generate_204`，备选 `http://cp.cloudflare.com/generate_204`，第三项自定义 http(s) 链接。选择存 `PlatformStorage` 的 `DELAY_TEST_URL`，不属于 `override.user.json`，不触发内核重启。
- 列表组头、节点、顶栏全量与定时测速都在发起前读取当前偏好，离线会话把同一地址传给 native 拨测。切换后下一次点击立即生效，不允许在 ViewModel 初始化时缓存地址。

## 两个 mode 值

展示用 `homeUiState.mode`：它是「override 持久值 + 运行时 `/configs` 轮询值」，停止态也有值，`switchMode` 内同步 `copy(mode=)` 即可回显。判断分流行为的 `globalModeActive` 读 `ProxyUiState.mode`，与 `loadProxies` 的组排序共用真值；停止态 `ProxyUiState` 由离线快照的 mode 与屏幕传入的展示模式填充。

## 出站模式与代理组

各出站模式下都显示全量代理组，并在内容顶部渲染模式提示。`GET /group` / `GET /proxies` 的返回与 `mode` 无关：direct 模式下 mihomo 在 `resolveMetadata` 直接返回 DIRECT，global 模式只由 GLOBAL 决定出口，而 `PUT /proxies/{group}` 在任何模式下都被接受并保存，切回 rule 立即生效，延迟测试照常可用，用户可以先选好节点再切回规则模式。mode 常量在 `ProxyViewModel.companion`。

## GLOBAL 组

`GET /group` 里 GLOBAL 与普通组同级（Selector）。`loadProxies` 用它的 `all` 作为组排序基准，同时把它排进列表：`mode == "global"` 时置顶（唯一生效出口），其余时候沉底；mode 从 `GET /configs` 实时读取。非全局模式下是否显示由 `PROXY_SHOW_GLOBAL_GROUP`（默认开）控制；全局模式始终显示，生效出口随时可选。开关只影响展示：`orderMap` 仍从 `globalGroup.all` 计算，过滤在 UI 层完成。默认开启的原因：rule 模式下 GLOBAL 的 `all` 覆盖全部节点与组，`/group/GLOBAL/delay` 是唯一的一键全量测速入口，提前选好的出口切到 global 时也立即生效。
