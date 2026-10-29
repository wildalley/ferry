# Changelog / 更新日志

## Unreleased

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
