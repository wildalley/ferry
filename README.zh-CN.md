# 渡 Ferry

[English](README.md) | 简体中文

一个基于 Flutter 的 sing-box 客户端，支持 **Android**、**Linux** 和 **Windows**，前身是 **SingBox Client**。界面以紫色为唯一主色，配细网格背景和纸飞机标志，提供亮色与暗色主题，以及中英文界面。设计说明见 [docs/design/README.md](docs/design/README.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

三个平台都能真正跑代理，只是方式不同：

- **Android** 内嵌内核：Kotlin 写的 `VpnService` 通过自行编译的 `libbox.aar` 驱动 sing-box。
- **Linux** 托管一个系统里已安装的 `sing-box`，通过它的 Clash API 控制。原因是 `libbox.aar` 只能用于 Android，而桌面上的 TUN 需要一项进程内库无法自己获取的权限。
- **Windows** 用同样的方式托管随安装包附带的 `sing-box.exe`。系统代理模式通过 WinINet 暴露本地的 mixed 代理；TUN 模式使用 sing-box 内置的 Wintun 支持，并通过 UAC 提权。

## 功能

**代理运行时（Android）**

- 前台 `VpnService` 管理 VPN 生命周期，带通知栏和停止按钮
- 通过 `CommandServer` / `CommandClient` 驱动 sing-box v1.13
- 界面实时显示状态、流量计数，以及有上限、可清空的日志
- 通过 `selector` 出站在运行中切换节点，不需要重启隧道
- `urltest` 组可作为一个出口选项，由内核自己挑选最快的节点
- Flutter 引擎被杀掉后隧道依然在运行；重新打开应用会重新连上正在运行的服务
- 分流规则集打包在 APK 里，启动时不需要联网；过期的规则集会在隧道建立后自动更新

**代理运行时（Windows）**

- 托管一个随程序附带、校验和固定的 `sing-box.exe`
- 通过 Clash API 控制内核：切换节点、逐个节点测速、流量、连接数和内存
- 两种模式。默认是系统代理，不需要任何权限，会自动把 WinINet 指向本地入站；TUN 接管全部流量，会通过 UAC 弹窗请求管理员权限，可选的「系统 HTTP 代理」设置还能同时把本地入站暴露给 WinINet 应用。固定版本的 sing-box 自带 Wintun 支持，不需要另外放一份 `wintun.dll`
- 在断开、退出，以及异常退出后的下一次启动时，恢复用户原来的 WinINet 代理设置
- 用 Job Object 托管进程：界面意外关闭时，内核进程会被一并回收
- 进程输出、Clash API 流量、选择器变化和测速结果，与 Android 进入同一套有上限的界面数据流

**代理运行时（Linux）**

- 托管系统已安装的 `sing-box`（≥ 1.12），通过 Clash API 控制：切换节点、逐个节点测速、流量、连接数和内存
- 两种模式。默认是系统代理，完全不需要权限，会把 GNOME 或 KDE 指向本地入站；TUN 接管全部流量，会通过 polkit 弹窗为内核程序申请 `CAP_NET_ADMIN`，每个程序文件只需要一次
- 在断开、退出，以及异常退出后的下一次启动时，恢复桌面原来的代理设置
- 内核的标准输出和错误输出会进入日志页，启动失败时能看到原因
- 找不到内核、内核版本太旧、内核拒绝创建 TUN，都会用用户的语言说明原因和解决办法

**桌面外壳**

Linux 和 Windows 共用。

- 托盘图标反映连接状态，菜单里有显示/隐藏窗口、连接/断开，以及可勾选的代理模式
- 托盘菜单的「显示窗口 / 隐藏窗口」会跟随窗口的真实状态，无论窗口是通过托盘、任务栏、最小化、窗口管理器快捷键还是再次启动被显示或隐藏的
- 关闭窗口只是隐藏，隧道继续运行；如果托盘图标没能装上，关闭按钮会改为直接退出，避免窗口藏到一个无法唤回它的图标后面
- 隐藏或最小化时暂停绘制、动画和首页时钟；恢复窗口后保留所在页面和滚动位置。代理流量和统计数据在后台继续
- 退出时先停止内核并恢复桌面代理设置，再结束进程，不会让系统指向一个已经没有服务的端口
- 再次启动应用时，会把已在运行的那个窗口调到前台，而不是再起一个绑不上端口的进程

**导入**

- 订阅链接，包括 `subscription-userinfo` 中的流量配额和到期时间
- Clash / mihomo YAML（`proxies:`），可粘贴、从订阅拉取或读取文件：vless（reality、flow、uTLS）、vmess、trojan、shadowsocks（obfs、v2ray-plugin）、hysteria2、tuic v5、anytls、socks5 和 http，支持 ws/httpupgrade/grpc/h2/http 传输。节点 ID 与分享链接一致，同一节点无论以哪种格式导入都会保留延迟和收藏
- 二维码：Android 用摄像头扫描，所有平台都可以从图片识别（桌面上通常是截图）。识别结果会填进导入框，确认后才会导入
- 分享链接：vless、vmess、trojan、shadowsocks、hysteria2、tuic、anytls、socks、http，支持 reality、uTLS，以及 ws/grpc/h2/httpupgrade 传输。内核会拒绝的 `fp=` 指纹（有些面板会输出 `unsafe` 这类无效值，导致 sing-box 1.14 拒绝整个配置）会在导入时和生成配置时被丢弃，一个坏节点不会让整个连接起不来
- sing-box JSON 配置，完整文件或单独的 `outbounds` 数组
- 从磁盘读取配置文件

节点 ID 由服务器身份推导，重新导入订阅时会保留已测得的延迟和收藏状态。

**界面**

- 首页、节点、规则、日志、设置五个页面；手机上是紧凑的底部导航栏，桌面窗口是侧栏
- 首页主卡片集中显示隧道需要的全部信息，每项只出现一次：连接状态、出口节点、一个**潮位表**（水位就是对数刻度上的实时速率）、上下行速率、出口 IP，以及一个**纸飞机开关**，在「连接」和「断开」之间滑动
- 亮色和暗色主题，可跟随系统，也可手动指定
- 中文和英文，可跟随系统语言，也可手动指定
- 隧道建立后，延迟通过隧道测量（内核对每个代理做 URL 测试）；未连接时，对 TCP 节点做有超时上限的 TCP 握手测量；UDP/QUIC 节点等隧道启动后再测，避免被误判为不可达
- 节点按来源分组，可折叠、搜索、按延迟排序，并按需构建，几百个节点的订阅也能瞬间打开；每个节点显示所在地区的国旗（Windows 的表情字体不含国旗，改为显示地区代码）
- 单节点链式代理：让一个节点经由另一个节点出去，支持多跳和防环
- 动效跟随流量：潮位表每收到一次流量读数起伏一次，没有流量或开启了「减少动态效果」时保持静止
- 出口 IP 读数，经由隧道获取。这是唯一能确认流量确实从节点出去、而不是从用户自己线路出去的检查
- 订阅过期时，连接时会自动刷新
- 可查看生成的配置，便于排查问题
- **可选的检查更新**：每天在后台静默向 GitHub 查询一次最新发布；有新版本时，首页会出现一张可关闭的提示卡片，设置 → 关于里也会显示。它不会下载或安装任何东西，也不会单独更新 sing-box 内核——内核随每个版本一起发布，与该版本生成的配置格式相匹配

**分流规则**

- 内置规则集处理常见情况：国内直连、拦截广告、其余走代理
- 自定义规则处理具体情况，每条规则一个匹配条件、一个去向。可匹配域名、域名及其子域名、域名关键字、IP/CIDR、端口或进程名；去向可选代理、直连或拦截
- 按页面上显示的顺序匹配，并且排在内置规则集之前，所以你为某个域名写的规则优先于包含数百万条目的列表
- 可调整顺序，可单独停用而不删除，并且在交给内核前就会校验——端口写错会直接在界面上提示，而不是变成一个起不来的隧道
- 修改规则会重新加载正在运行的隧道，规则立即生效
- **策略组**：带名字的出口，每个组可以单独选一个节点（或「自动」）。比如让「AI」走美国节点、「流媒体」走香港节点，其余流量仍走主节点。规则除了代理/直连/拦截，还可以指向某个策略组。每个组都可以在连接中实时切换节点，不影响主节点，也不会断开连接。删除策略组时，指向它的规则会自动改走主节点；组里选的节点不见了会回退到「自动」，因此过期的引用永远不会让内核起不来
- 策略组还可以挂**规则集**：geosite 分类（`openai`、`netflix`）、geoip 国家（`geoip:jp`）或任意 `.srs` 文件链接。规则集由应用下载并以本地文件引用，未下载成功的不会写进配置，也就不会让内核起不来

## 环境要求

```text
Flutter 3.47+
Dart 3.3+
```

构建 Android：需要 JDK 17、带 NDK 的 Android SDK，以及用于编译 `libbox.aar` 的 Go 1.24+。

构建 Linux：除了 Flutter 常规的桌面工具链（clang、cmake、ninja、GTK3），托盘还需要 appindicator 开发包——缺少时 `tray_manager` 的 CMake 会直接报错，整个程序都编不出来：

```bash
sudo apt-get install libayatana-appindicator3-dev   # Debian、Ubuntu
sudo pacman -S --needed libayatana-appindicator     # Arch
```

## 构建

`android/app/libs/libbox.aar` 不在仓库里——它是从 sing-box 源码编译出来的、约 23 MB 的二进制文件。先编译它：

```bash
./scripts/build-libbox.sh
```

脚本把 sing-box 固定在某个发布 tag，使用 sing-box 自己的 gomobile 分支和编译标签，把 aar 写到 `android/app/libs/`。需要设置 `ANDROID_HOME` 和 `ANDROID_NDK_HOME`，或者把 SDK 放在脚本能找到的标准位置。

然后：

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

`--target-platform android-arm64` 很重要：aar 只编了 arm64，如果打通用 APK，其他架构里不会有 `libbox.so`，一启动就会崩溃。

桌面端不需要 aar：

```bash
flutter run -d linux
flutter run -d windows
```

在 Windows 上，导入订阅后点「连接」即可。默认是系统代理模式，会自动配置 WinINet。如果要透明接管 TCP/UDP，到「设置 → 代理模式 → TUN」；可选的「系统 HTTP 代理」还会为不走虚拟网卡的应用配置 WinINet。第一次启动 TUN 时 Windows 会弹出 UAC 提权，提权后的新实例会自动继续刚才的连接。

### 打包

`scripts/package.sh` 一次性构建所有安装包，输出到 `dist/`：

```bash
scripts/package.sh            # 当前机器能构建的全部
scripts/package.sh deb apk    # 或指定其中几个
```

| 产物 | 需要 |
| --- | --- |
| `ferry_<版本>-<构建号>_amd64.deb` | 上面的 Linux 工具链即可——有 `dpkg-deb` 时用它，否则用 `ar` + `tar` |
| `ferry-<版本>-<构建号>-x86_64.pkg.tar.zst` | `makepkg` 和 `fakeroot`，也就是需要 Arch 系统 |
| `ferry-<版本>-<构建号>-arm64.apk` | JDK、Android SDK，以及 `android/app/libs/libbox.aar` |
| `ferry-windows-x64-<sha>.zip` | 装有 Visual Studio C++ 工具链的 Windows 机器，以及固定版本的 sing-box 压缩包 |

缺少工具的产物会被跳过并打印原因，其余照常构建。所有图标——启动图标、托盘图标、Windows 图标，以及 `docs/design/icon/linux/` 里 Linux 桌面用的各尺寸图标——都由应用绘制标志的同一段代码生成：

```bash
RENDER_ICONS=1 flutter test test/render_icons_test.dart
```

两种 Linux 安装包的文件布局相同：程序放在 `/usr/lib/ferry/`，通过 `/usr/bin/ferry` 软链接启动，另带桌面启动项和各尺寸 hicolor 图标。构建都不需要 root——deb 可以退回用 `ar`+`tar`，`makepkg` 本来就拒绝以 root 运行。两者都把 appindicator 运行库列为硬依赖，因为程序链接了它们，缺了就加载不起来。两者也都声明替代旧的 `singbox-client` 包，升级时会把旧包换掉，而不是新旧并存。

## 持续集成

`.github/workflows/build.yml` 包含五个任务：

| 任务 | 运行环境 | 产出 |
| --- | --- | --- |
| `verify` | `ubuntu-latest` | `flutter analyze`、`flutter test` |
| `package` | `ubuntu-latest` | deb 和 arm64 APK |
| `windows` | `windows-latest` | Windows x64 发布包（`.zip`） |
| `arch` | `archlinux:base-devel` 容器 | `.pkg.tar.zst` |
| `release` | `ubuntu-latest` | 推送 `v*` tag 时，把构建成功的产物发布到一个 GitHub Release |

`ubuntu-latest` 自带 `scripts/build-libbox.sh` 需要、而普通桌面环境通常没有的 JDK 17、Android SDK 和 NDK。`libbox.aar` 按 `SINGBOX_TAG` 缓存，只有第一次运行需要花约 15 分钟编译。两个 Linux 任务都会安装各自发行版的 appindicator 包，因为托盘是构建依赖，而不只是运行依赖。

Arch 包单独一个任务，因为写 `.PKGINFO`、`.MTREE` 和 `.BUILDINFO` 的 `makepkg` 只存在于 Arch 上；而且在 Arch 上打的 deb 会链接比 Debian 更新的 glibc。容器里的一切都以普通用户运行：`makepkg` 和 `flutter` 都拒绝以 root 运行。

每个构建任务各自上传产物，即使其中一个失败，`release` 也会运行，一个坏掉的产物不会拖住其他产物的发布。

**签名**：APK 使用正式密钥签名，密钥从仓库的 4 个 secret 还原：`FERRY_KEYSTORE_BASE64`（`.jks` 文件的 base64）、`FERRY_KEYSTORE_PASSWORD`、`FERRY_KEY_ALIAS` 和 `FERRY_KEY_PASSWORD`。缺少它们时构建会退回 debug 密钥；如果是 `v*` tag，构建会直接失败，而不是发布一个无法覆盖升级已安装版本的 APK。本地构建时，把同样的 4 个值以 `storeFile`、`storePassword`、`keyAlias`、`keyPassword` 写进 `android/key.properties`（已被 git 忽略）。请务必备份密钥库：用其他密钥签名的版本无法升级已安装的应用。

## 验证

```bash
flutter analyze
flutter test
```

638 个测试通过，19 个跳过，覆盖：分享链接解析（包括 uTLS 指纹白名单）、配置生成、链式代理与防环、重复出站标签处理、自定义规则校验与位置、策略组的配置生成、实时切换与规则集、Clash YAML 导入（开发时用 `sing-box check` 校验过输出）、二维码识别、节点列表按需构建、检查更新、从 SingBox Client 迁移桌面数据、导入格式识别、两个桌面运行时共用的 Clash API 客户端、polkit 授权、基于模拟对象的 Linux 系统代理后端、退出流程、单实例 socket、托盘菜单构建、后台暂停动画与日志跟随回调上限、基于模拟控制器的界面交互，以及包含配色对比度在内的本地化与主题检查。Windows 的提权判断有单元测试；它的 WinINet 桥接、Job Object 和真实 TUN 网卡仍需要在 Windows 上验证。

视觉回归截图需要设置环境变量才会运行，因为它们依赖本机字体渲染，只在录制它们的机器上有意义：

```bash
VISUAL_SNAPSHOTS=1 flutter test test/visual_snapshot_test.dart
```

端到端的隧道行为——真实节点承载真实流量——没有自动化验证，需要真实订阅才能测试。依赖内核运行时上报数据的部分同样如此，包括延迟排序背后的 URL 测试结果。

托盘菜单、首次启动时的 polkit/UAC 弹窗、窗口隐藏/显示循环的自动化测试使用模拟对象，覆盖菜单内容、退出顺序、`pkexec` 参数和 socket 交接。它们仍需要在更多桌面环境和 Windows 安装上做实际验证。

`0.1.5-12` 的 Linux 版本包含了后台呈现方面的修复，起因是长时间驻留托盘后客户端内存约 1.2 GiB 的报告。该包安装后，重启并确认加载的是新的应用库；长时间运行的内存稳定性仍未验证。详见[内存问题调查与验证记录](docs/memory-investigation-2026-10.md)。

## 从 SingBox Client 升级

应用在 0.3.0 改名，标识也随之改变：Dart 包和可执行文件叫 `ferry`，Linux 安装包叫 `ferry`（安装在 `/usr/lib/ferry`），应用 ID 为 `com.wildalley.ferry`。

- **Linux 和 Windows** 会保留你的数据。新版第一次启动时，会从旧位置复制设置（订阅、节点、设置、规则）、规则集和内核缓存——Linux 上是 `~/.local/share/com.wildalley.singbox_client/` 和 `~/.local/share/singbox-client/`，Windows 上是 `%APPDATA%\com.wildalley\SingBox Client` 和 `%LOCALAPPDATA%\SingBox Client`。旧数据原样保留。请先退出旧版再启动新版：两者的单实例锁放在不同位置。
- **Android** 上，由于应用 ID 变了，系统会把它当作一个全新的应用：旧版无法升级上来，数据也读不到。请安装 0.3.0，重新导入订阅，然后卸载旧的 SingBox Client。

## 本地化

文案位于 `lib/l10n/app_en.arb` 和 `app_zh.arb`。修改后运行：

```bash
flutter gen-l10n
```

`AppState` 从不拼接面向用户的句子；它只上报一个 `NoticeKind`，由界面翻译，这样业务逻辑不依赖 `BuildContext`。

## 平台状态

| 平台 | 代理运行时 | 界面 |
| --- | --- | --- |
| Android（arm64） | 通过 libbox + VpnService 运行 sing-box | 有 |
| Linux（x86_64） | 托管 `sing-box` 进程 + Clash API | 有 |
| Windows（x64） | 托管 `sing-box.exe` + WinINet 系统代理，或提权后的 Wintun TUN | 有 |

两个桌面运行时是同一个基于 Clash API 的进程托管适配器，见 [`docs/architecture.md`](docs/architecture.md)；区别在于系统代理的设置方式——Linux 用 `gsettings`/`kwriteconfig`，Windows 用 WinINet——以及提权流程。Linux 给系统安装的内核授予文件权限；Windows 在选择 TUN 时通过 UAC 重新启动应用。

Linux 需要 `PATH` 上有 1.12 或更新的 `sing-box`——生成的配置使用 1.12 的格式。可以用 `SINGBOX_BINARY` 指定其他路径。两种模式的区别：

| 模式 | 权限 | 能接管的流量 |
| --- | --- | --- |
| 系统代理 | 不需要 | 遵守桌面代理设置的应用；仅 TCP |
| TUN | `CAP_NET_ADMIN` | 全部流量，包括 UDP |

**默认是系统代理**，所以全新安装后不需要任何授权就能连接。切换到 TUN 需要一次授权：启动内核前，应用会检查程序文件的权限，缺少时通过 polkit 申请——就是桌面挂载磁盘时弹出的那个密码框——实际执行的是：

```bash
pkexec setcap cap_net_admin,cap_net_raw+ep /usr/bin/sing-box
```

权限挂在程序文件上，而 `sing-box` 是应用自己启动的子进程，所以只需要授权一次，而不是每次连接都要：不安装任何特权辅助程序，应用本身也不提权。升级 `sing-box` 包会替换文件，权限也随之丢失——在 Arch 上，本包附带一个 libalpm 钩子，pacman 安装或升级 `sing-box` 时会自动重新执行 `setcap`，弹窗不会再出现；deb 的 `postinst` 会在本包安装或升级时重新授权。

只有位于系统目录（`/usr`、`/opt`、`/bin`、`/sbin`）下的 `sing-box` 会走这种自动授权，因为路径可能来自 `SINGBOX_BINARY`，以 root 身份对任意路径执行 `setcap` 等于给调用者指定的文件授权。其他位置的程序依然可以运行，请手动授权：

```bash
sudo setcap cap_net_admin,cap_net_raw+ep /path/to/sing-box
```

如果弹窗被取消，或者系统没有 polkit 代理，TUN 模式会提示并给出手动命令；系统代理模式不受影响。各运行时如何分担同一个 `ProxyController` 接口，见 [`docs/architecture.md`](docs/architecture.md)。

## 已知不足

- 0.3.0 及以前的 APK 由 CI 临时生成的 debug 密钥签名，从这些版本升级需要卸载重装；从 0.3.1 起所有版本使用同一把密钥，可以直接覆盖升级。
- 只支持 arm64。其他架构需要用不同的 `-target` 再跑一次 `scripts/build-libbox.sh`。
- Android 的分应用代理可以把选中的可启动应用排除在 VPN 之外。
- Android 无法在 0.3.0 改名时保留数据，见「从 SingBox Client 升级」。
- Linux 上标题里的汉字使用系统的中文衬线字体；Android 上 Flutter 找不到它，会显示为黑体。
- 两种 Linux 安装包都做过结构检查——deb 成员顺序和 control 字段、`pacman -Qip` 元数据、root 所有权、`/usr/bin` 软链接、桌面启动项。Arch 包有日常使用经验；deb 还没有在真实系统上安装过。
- Linux 运行时只有基于模拟对象的单元测试，没有真实隧道测试：没有自动化测试会启动真实的 `sing-box`、创建 TUN 或写入真实的桌面代理设置。
- Windows 运行时只有静态检查和单元测试，没有真实的 UAC/TUN 会话；仍需要一台 Windows 机器来端到端验证网卡创建和路由回滚。
- Linux 没有特权辅助程序。TUN 依赖 `sing-box` 程序文件上的权限，通过 polkit 授予，包升级会清除它，弹窗会再次出现。用 systemd 或 polkit 安装的辅助程序可以避免这一点。
- 只实现了 GNOME 和 KDE 的系统代理后端。在其他桌面上，该模式会启动内核，并在日志页说明无法设置桌面代理。
- 托盘需要面板上有东西来承载。GNOME 上这是 AppIndicator 扩展，默认没有安装；没有它图标就不会出现，关闭按钮会改为退出而不是隐藏。
- 托盘提示文字和点击事件只在 Windows 上有。Linux 的 AppIndicator 把菜单交给面板，不报告点击，所以菜单第一项就是唤回窗口的方式。
- 出口 IP 读数会请求第三方回显服务（`ip.sb`、`ifconfig.co`），它们能看到请求发出的地址。连接时和切换节点时会自动执行，并且走隧道；目前还没有关闭它的设置。旁边的刷新按钮在未连接时也能用，这时请求直接发出，显示的是你自己的地址——只有你点它时才会发生，从不自动发生。
- 自定义规则每条只有一个匹配条件、一个去向。需要同时满足两个条件的情况只能写配置文件，而本应用会生成配置，但不接受手工编辑。

## 安全

节点凭据、订阅令牌、UUID 和密码保存在本地存储和生成的配置中。它们会从日志和错误信息中脱敏，但「生成的配置」查看器按设计会完整显示——显示前会给出提醒。

切勿提交包含令牌的订阅链接、签名密钥库或生成的运行时状态。

## 许可证

GPL-3.0-or-later——见 [`LICENSE`](LICENSE)。Copyright 2026 WildAlley。

这个选择并非随意：Android 版链接了从 [sing-box](https://github.com/SagerNet/sing-box) 源码编译的 `libbox.aar`，而 sing-box 采用 GPLv3 *或更高版本*。分发的 APK 是一个组合作品，条款必须兼容。发布二进制前有两点值得了解：

- 任何拿到 APK 的人都有权获得对应源码。仓库是公开的，这就满足了这项义务。
- sing-box 额外附加了一条：未经事先同意，衍生作品不得使用其名称或暗示与其有关联。

Linux 安装包不含任何 sing-box 代码：那里的运行时执行的是用户另行安装的 `sing-box`，没有复制或链接它的任何部分。它们与本仓库同源，因此采用同样的许可证。deb 在 `usr/share/doc/ferry/copyright` 中声明，Arch 包在 `usr/share/licenses/ferry/LICENSE` 中声明。
