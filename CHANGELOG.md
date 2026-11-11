# Changelog / 更新日志

## 0.4.5 — 2026-11-11

### 中文

- **安全更新**：Android 和 Windows 内核改用 Go 1.27.4 编译，修复 Go 标准库 `net/http` 的 GO-2026-6859（CVE-2026-97054）：HTTP/1 服务端可能因 `MaxBytesReader` 头部竞争而崩溃。内核的 Clash API 服务只监听本机，实际风险较低。内核版本仍为 1.14.4-ferry.1。
- **更新检查**的 User-Agent 改为 `ferry-update-check`，不再沿用改名前的名称。
- 功能和界面无变化。Linux 使用系统安装的内核，不受此次重编译影响。

**升级说明**：可直接覆盖安装 0.4.4。

### English

- **Security update**: the Android and Windows cores are now built with Go 1.27.4, fixing GO-2026-6859 (CVE-2026-97054) in the standard library's `net/http`, an HTTP/1 server crash from a `MaxBytesReader` header race. The core's Clash API server listens only on loopback, so the practical exposure is low. The core version stays 1.14.4-ferry.1.
- **Update check** now identifies itself as `ferry-update-check` instead of the pre-rename name.
- No feature or UI changes. Linux uses the system-installed core and is unaffected by the rebuild.

**Upgrading**: installs over 0.4.4.

Downloads: Android arm64 APK, Linux amd64 deb, Arch Linux x86_64 package, Windows x64 ZIP.

## 0.4.4 — 2026-11-10

### 中文

- **依赖升级**：二维码扫描 `mobile_scanner` 升级至 7.5.0，本地设置 `shared_preferences` 升级至 2.5.6。
- **Android 构建工具链**：Gradle 9.9.0、Android Gradle Plugin 9.5.1。
- **CI 与发布流程**：GitHub Actions 升级（checkout 7、setup-java 6、setup-go 7、upload-artifact 7、download-artifact 8）。
- 功能和界面无变化。桌面托盘/窗口库（`tray_manager`、`window_manager`）的大版本升级涉及 API 变更，留待单独迁移；`androidx.core` 1.19 需要 Android API 37，暂缓。

**升级说明**：可直接覆盖安装 0.4.3。

### English

- **Dependencies**: `mobile_scanner` 7.5.0 (QR scanning) and `shared_preferences` 2.5.6.
- **Android toolchain**: Gradle 9.9.0 and Android Gradle Plugin 9.5.1.
- **CI and release pipeline**: GitHub Actions upgraded (checkout 7, setup-java 6, setup-go 7, upload-artifact 7, download-artifact 8).
- No feature or UI changes. The major upgrades of the desktop tray/window libraries (`tray_manager`, `window_manager`) change their APIs and are left for a separate migration; `androidx.core` 1.19 needs Android API 37 and is deferred.

**Upgrading**: installs over 0.4.3.

Downloads: Android arm64 APK, Linux amd64 deb, Arch Linux x86_64 package, Windows x64 ZIP.

## 0.4.3 — 2026-11-10

### 中文

- **修复 Android 启动即提示“无法打开安全存储”**：部分设备的系统 Keystore 无法使用，0.4.2 安装后会一直停在恢复页。现在若 Keystore 在首次使用时就失败（尚未保存过渡的数据），该安装会改用应用私有存储保存凭据：仅本应用可读，且已排除云备份和设备迁移，与 0.4.2 之前的保存方式一致。旧版本数据会完整迁移。
- **仍会安全失败的情况**：凭据已存入 Keystore 后又无法读取，或旧数据本身损坏时，仍保留数据并显示恢复页，不会自动清空。桌面端行为不变。
- **可诊断的恢复页**：恢复页显示失败原因（仅错误代码和系统消息，不含任何凭据），便于反馈设备问题。

**升级说明**：可直接覆盖安装 0.4.2；在 0.4.2 上卡在恢复页的设备，升级后首次启动即可进入。

### English

- **Fix Android startup stuck on "Secure storage is unavailable"**: on devices whose system Keystore cannot be used, 0.4.2 never got past the recovery screen. When the Keystore fails before it has ever held Ferry's data, that install now keeps credentials in app-private storage instead — readable only by the app and excluded from cloud backup and device transfer, as before 0.4.2. Existing data is migrated intact.
- **Still fails closed**: if the Keystore already holds the data and stops working, or legacy data is corrupt, the data is kept and the recovery screen is shown; nothing is erased. Desktop behaviour is unchanged.
- **Diagnosable recovery screen**: it now shows the failure cause (error codes and platform messages only, never a credential) so device issues can be reported.

**Upgrading**: installs over 0.4.2. Devices stuck on the recovery screen in 0.4.2 start normally after upgrading.

Downloads: Android arm64 APK, Linux amd64 deb, Arch Linux x86_64 package, Windows x64 ZIP.

## 0.4.2 — 2026-11-10

### 中文

- **内核升级**：Android 和 Windows 使用 sing-box 1.14.4，保留依赖安全升级及 Hysteria2 低延迟窗口修复；适配新版 Android DNS、平台回调和资源释放接口。
- **Linux TUN 授权**：补齐 Debian/Ubuntu、Arch 的授权工具依赖，分别提示取消、缺工具、认证失败和权限复查失败。支持 NixOS 声明式 capability 包装器，发行版说明见 Linux TUN 指南。
- **凭据保护**：节点、订阅和本地代理/API 凭据迁入平台凭据库；迁移须写入并回读成功后才清除旧数据，Android 备份排除凭据。密钥库不可用时保留数据并提示恢复。
- **本地代理鉴权**：Android 默认启用随机凭据；桌面默认关闭以兼容系统代理，可在设置中启用。开启鉴权后，连接本地 HTTP/SOCKS 端口的外部应用需要支持代理认证；普通 TUN 流量不受此项影响。
- **稳定性与性能**：串行处理核心操作并过滤过期回调，限制 HTTP/日志缓冲和并发轮询；后台暂停展示动画，大订阅解析移至后台，保留已支持协议。
- **构建与发布**：固定核心及工具链，校验 APK 签名和 16 KiB 对齐；所有平台通过后才发布，附带 SHA256SUMS、依赖清单和构建来源证明，依赖扫描告警或失败会阻断发布。
- **清理**：移除旧品牌设计稿、废弃背景素材及组件，统一图标生成入口，更新双语说明和待办。

**升级说明**：Android 正式 APK 沿用既有发布证书，可覆盖升级 0.3.1 及之后的正式签名版本。请在 Linux 上安装 sing-box ≥ 1.12，推荐使用发行版提供的当前稳定版；Windows 包内附带核心。首次升级涉及凭据迁移，桌面凭据库需要可用且已解锁。

**已知边界**：1.14 核心使 APK 比前版增大约 19 MiB（发布候选约 89 MiB）；各发行版真实授权、Android/Windows 实机协议和长时内存验收仍有待完成，不将回归测试结果等同于全部设备稳定性验证。

### English

- **Core**: Android and Windows now use sing-box 1.14.4 with security dependency upgrades and the Hysteria2 low-RTT window fix. Android bindings follow the new DNS, platform callback and resource lifecycle interfaces.
- **Linux TUN**: package authorization tools, distinguish cancellation and authentication/preflight failures, and verify capabilities after granting them. Support declarative NixOS wrappers with distribution-specific setup guidance.
- **Credentials**: migrate node, subscription and local proxy/API credentials to platform secure storage, verify writes before deleting old values, and exclude credentials from Android backup. Unavailable stores preserve data and offer recovery.
- **Proxy authentication**: random credentials are required on Android; desktop authentication remains optional and off by default. External HTTP/SOCKS clients must support authentication when enabled. Normal TUN traffic does not use this proxy login.
- **Reliability and performance**: serialize core operations, reject stale callbacks, bound HTTP/log buffering and polling, pause presentation work in the background, and parse large subscriptions off the UI isolate.
- **Builds and cleanup**: pin native sources/toolchains, enforce signature/alignment and dependency checks, publish only after every platform passes, and include checksums, inventories and provenance. Remove obsolete design assets and unused artwork code.

**Upgrading**: the official Android APK retains the existing signing certificate and can update official releases from 0.3.1 onward. Linux requires a separately installed sing-box ≥ 1.12; Windows includes its core. Desktop credential storage must be available and unlocked for migration.

**Known limits**: the new core adds about 19 MiB to the APK (the release candidate is about 89 MiB). Broader device, distribution authorization and long-running memory validation remains outstanding.

Downloads: Android arm64 APK, Linux amd64 deb, Arch Linux x86_64 package, Windows x64 ZIP.

## 0.4.1

### 中文

- **编辑订阅**：节点页和设置页可修改订阅名称、链接及 User-Agent；修改链接或 User-Agent 后立即刷新节点。
- **保留自定义名称**：手动重命名后，刷新订阅不再被服务端的名称覆盖；本地导入来源也可以重命名。
- **客户端标识**：支持常用 User-Agent 预设和自定义值，留空恢复默认；订阅与规则集请求的默认标识随应用版本更新。

### English

- **Edit subscriptions**: change the name, URL, and User-Agent from Nodes or Settings. Changing the URL or User-Agent refreshes the nodes immediately.
- **Keep custom names**: refreshing no longer overwrites a manually renamed subscription with the server's title. Local sources can also be renamed.
- **Client identification**: choose a common User-Agent preset or enter a custom value; leave it empty to restore the default. Default subscription and rule-set request agents now use the app version.

## 0.4.0

### 中文

- **扫码添加**：Android 可用摄像头扫描订阅或节点二维码；所有平台都可以从图片（如截图）识别。结果填进导入框，确认后导入。
- **Clash / mihomo 订阅**：支持导入 YAML 格式的订阅（粘贴、订阅链接或文件），覆盖主流协议和传输方式。
- **策略组规则集**：策略组可以挂 geosite 分类、geoip 国家或 `.srs` 链接，不用逐条写域名。
- **手机端布局**：节点行、规则行的次要按钮收进「更多」菜单，名称不再被截断；没有节点时首页显示引导卡片。
- **性能**：节点列表按需构建；首页不再每秒整页重建。

### English

- **QR import**: scan a subscription or node QR code with the camera on
  Android, or read one from an image (a screenshot) anywhere. The result goes
  into the import field for checking first.
- **Clash / mihomo subscriptions**: YAML configs import, pasted, fetched or
  from a file, across the common protocols and transports.
- **Rule-sets for policy groups**: geosite categories, geoip countries or
  `.srs` links, instead of typing domains one by one.
- **Phone layout**: node and rule rows fold their side buttons into a menu so
  names fit; an empty dashboard shows a first-run card.
- **Performance**: node rows are built lazily; the dashboard no longer
  rebuilds whole every second.

## 0.3.1

### 中文

- Android 安装包改用固定的正式密钥签名。0.3.0 及以前的 APK 由 CI 每次临时生成的密钥签名，无法覆盖升级；从本版本起，以后的版本都可以直接覆盖安装，数据保留。从 0.3.0 升到本版本需要最后一次卸载重装。
- 检查更新改为查询改名后的仓库 `wildalley/ferry`。

### English

- Android APKs are now signed with a persistent release key. Up to 0.3.0 each
  CI run signed with a fresh throwaway key, so no release could update the one
  before it; from this one on, updates install in place and keep your data.
  Moving from 0.3.0 to this release needs one last reinstall.
- The update check asks the renamed `wildalley/ferry` repository.

## 0.3.0

### 中文

**改名：SingBox Client → 渡 Ferry**

- 应用名改为「渡」（英文 Ferry），标识统一为 `ferry`：Linux 安装包和命令是 `ferry`，应用 ID 是 `com.wildalley.ferry`。
- Linux / Windows：新版首次启动会自动从旧位置复制订阅、节点、设置、规则、规则集和缓存，旧数据保留不动。请先退出旧版再启动新版。Arch 和 deb 包会自动替换旧的 `singbox-client` 包。
- Android：应用 ID 改变后系统会把它当作新应用，旧版无法直接升级，需要重新导入订阅后卸载旧版。

**全新界面**

- 统一的紫色主色加细网格背景；全部卡片改为实心，开关、下拉菜单风格统一。
- 新标志：紫色底板上的白色纸飞机和一道波浪，应用内、启动图标、托盘、Windows 和 Linux 图标全部同源生成。
- 首页主卡片集中显示连接状态、出口节点、出口 IP、上下行速率，每项只出现一次；新的「潮位表」用水位表示实时速率。
- 连接按钮改为纸飞机滑动开关；桌面端修正了开关内边距不对称的问题。
- 节点列表显示地区国旗；手机端边距、底部导航栏更紧凑。

**策略组（issue #2）**

- 可以新建带名字的策略组（如「AI」「流媒体」），每组单独选择节点或「自动」。
- 自定义规则可以指向某个策略组；连接中切换组的节点即时生效，不影响主节点、不断开连接。
- 删除策略组时其规则自动改走主节点；组内节点消失时回退到「自动」，不会导致内核无法启动。

**检查更新**

- 每天在后台静默检查一次 GitHub 最新发布；有新版本时首页显示可关闭的提示，设置 → 关于中也可手动检查。只提示、不强制、不自动下载安装。

**修复**

- 托盘菜单的「显示 / 隐藏窗口」现在跟随窗口真实状态（任务栏、最小化、快捷键、再次启动等方式也会同步）；最小化后从托盘恢复会正确还原窗口。
- 侧栏导航项按下时不再露出方角阴影；设置分组卡片的点击水波纹不再溢出圆角。
- 界面显示的版本号与 `pubspec.yaml` 不一致的问题（新增测试防止再次发生）。

### English

**Renamed: SingBox Client → 渡 Ferry**

- The app is now 渡 (Ferry), and its identifiers are `ferry`: the Linux package
  and command are `ferry`, the application ID is `com.wildalley.ferry`.
- Linux / Windows: the first launch copies subscriptions, nodes, settings,
  rules, rule-sets and the engine cache from the old locations, leaving the old
  copies in place. Quit the old version first. The Arch and deb packages
  replace the old `singbox-client` package.
- Android: a new application ID is a new app to the system; the old install
  cannot be upgraded. Re-import your subscription, then uninstall the old one.

**New look**

- One violet brand colour over a faint grid; every panel is solid, and the
  switches and menus share one style.
- A new mark — a white paper plane over a wave on a violet plate — drawn by one
  piece of code for the app, launcher, tray, Windows and Linux icons.
- The dashboard hero shows the stage, exit, exit IP and both rates, each once,
  with a new tide gauge whose water level is the live rate.
- Connect is a paper-plane switch; its padding is now even on the desktop.
- Nodes show their region's flag; tighter phone gutters and bottom bar.

**Policy groups (issue #2)**

- Named groups (e.g. "AI", "Streaming"), each with its own node or Auto.
- Custom rules can send to a group; switching a group's node while connected
  applies live, without touching the main node or dropping connections.
- Deleting a group moves its rules to the main exit; a group whose node is gone
  falls back to Auto, so the engine always starts.

**Update check**

- Once a day, silently, the app checks GitHub for a newer release and offers it
  on a dismissible dashboard card; Settings → About checks on demand. It never
  forces, downloads or installs anything.

**Fixes**

- The tray's show/hide item follows the window's real state, whichever way it
  was shown or hidden; restoring a minimized window from the tray works.
- No square corners behind the pressed rail item; settings cards clip their
  row ripples to their rounded edge.
- The version the UI showed had drifted from `pubspec.yaml` (now tested).
