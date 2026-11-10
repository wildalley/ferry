# 文档优化实施记录

日期：2026-11-10。审计基线：`d18c4a2`。保留工作区原有 CI、NDK、备份与 WebSocket 修改后继续实施。
用户确认的兼容策略：**Android 强制随机代理凭据，桌面默认兼容系统代理、可选鉴权**。
本文合并初次审计与实施结果；持续更新的剩余任务见[优化待办](optimization-plan.md)。

## CI 故障证据

初次审计时查到的最近成功运行是 2026-11-05 的 `41984483533`（`d18c4a2`），verify、deb/APK、Windows、Arch 均成功。
历史失败运行 `40798158365` 在 APK/deb 生成后退出于签名检查。
本地复现发现 build-tools 37 对有效 APK 输出 `V2 Signer: certificate ...`，旧 `Signer #1` 正则不匹配会在 `bash -e` 下报错。
原日志无法区分当次是验证失败还是输出匹配失败，不能断言历史证书损坏；本轮验证脚本兼容两种格式并强制检查正式证书指纹。

该成功运行是单轮热缓存样本：verify 1 分 55 秒、deb/APK 5 分 04 秒、Windows 4 分 26 秒、Arch 1 分 50 秒。
这些是历史基线，不是修改后流水线或 libbox 冷构建的性能。

修改后提交 `6b5f680` 的远端运行 `42749581155` 已全部成功：verify 1 分 30 秒、
deb/APK 12 分 39 秒、Windows 4 分 22 秒、Arch 2 分；分支推送的 release 正常跳过。
这是另一组构建输入下的完整流水线结果，不能把 deb/APK 时间增加直接视为性能退化；
首次固定输入后的 AAR 构建及新增扫描也在该任务内。正式 tag 的生产签名及发布步骤尚未执行。

## 已落地

| 范围 | 改动 | 验证 |
| --- | --- | --- |
| 敏感数据 | 使用固定版本 flutter_secure_storage 11.2.0 保存节点、订阅、Clash token 和独立代理密码 | 迁移、部分失败、回读失败、密钥库丢失、损坏数据、写入失败后重试测试 |
| 迁移保护 | 全部写入并回读确认后才删除旧 SharedPreferences 凭据；迁移标记防止密钥库丢失时静默创建空数据；Android 禁止 resetOnError | 启动失败保留数据，显示重试/退出界面；没有明文回退 |
| 本地代理 | Android 的 mixed 入口必须有 users；桌面设置可选；应用内订阅、规则、更新和出口 IP 请求携带同一会话的端口与凭据 | 真实 HTTP 407 鉴权、非预期代理拒绝、DIRECT 不发送代理凭据、配置和预览脱敏测试 |
| 鉴权兼容提示 | 仅在鉴权与系统代理组合启用时显示就地提示，说明不支持认证的客户端可能断网及对应设置；凭据界面说明重连不换密码 | 真实桌面开关交互、两平台文案、大字体/横竖屏/深浅主题等 13 项安全 UI 测试通过；外部应用兼容矩阵仍待验证 |
| Android 生命周期 | start/stop/reload/选择/测速进入进程内单个后台执行器；主线程不等待 Go I/O；代号取消过期操作，事件保留所属会话并在 UI 分发前过滤 | Kotlin 和 APK release 编译通过；真机慢启动/撤销/连续重连仍需验证 |
| 部分初始化 | server/client 创建后立即取得所有权，start/connect 抛错也会关闭；停止回调只入队，不重入引擎关闭 | 编译检查；未声称已验证所有 native 故障路径 |
| Clash HTTP | AbortableRequest，总时限、8 MiB 正文上限、显式取消；错误正文不排空；销毁时取消本对象请求，保留注入 client 所有权 | 真实 socket 的响应头/正文超时、chunked/Content-Length、错误 PUT、dispose 断开测试 |
| Windows HTTP | 使用同一有界传输辅助函数；轮询 finally 只清除对应会话的并发标记 | Dart 分析/测试通过；Windows 本机构建待 CI |
| Linux 轮询 | 每个会话最多一个 group 请求，旧完成不能释放新会话的保护 | 临时假引擎和慢 API 的跨会话回归测试 |
| 隐藏窗口 | Linux/Windows 不再重建或保留连接明细模型，继续采集流量总数与连接数量 | 隐藏/恢复时计数、列表回归；JSON 正文仍需解码，未声称消除了全部解析开销 |
| 订阅导入 | 紧凑字节缓冲、网络总时限与取消、文件及粘贴输入 4 MiB 上限、64 KiB 起使用后台 isolate 解析 | 超限文件、1k 节点回归及 1k/10k 基准 |
| QR | 16 MiB 文件上限和 12×1024² 像素预算在完整解码前生效；只解码动画首帧 | 伪造巨大 BMP、小文件像素炸弹、超大字节、动画与原有截图回归 |
| Linux 提权 | 提权前解析真实路径，文件和每级父目录必须 root 所有且不可由组/其他用户写；工具也校验；setcap 使用规范路径 | 拒绝不安全目标/用户文件/符号链接及原有命令测试 |
| 安装权限 | 删除 deb postinst 和 Arch hook 中的自动 setcap，改为用户首次选择 TUN 时按需授权 | 打包脚本语法检查；已有系统 capability 不自动撤销 |
| 临时配置 | Linux 退出时合并重复清理，并删除当前运行配置；Windows 原有运行配置清理保留 | 假引擎停止后的文件删除检查 |
| 备份/外部输入 | Android 明确排除 cloud backup/device transfer；更新链接严格匹配仓库与 tag；HTTP 订阅及跳过 TLS 校验有可见提示 | URL 越界回归、Android 资源编译、安全 UI 大字体/横竖屏/深浅主题测试 |

安全存储的边界：它保护持久化凭据，不保护已经解锁的应用内存，也不能使拥有同一用户权限的恶意进程失去所有访问能力。
桌面运行引擎时仍需要临时明文配置；原有用户备份、迁移来源目录、崩溃遗留文件不会被自动全盘删除。
本地代理密码初始化后持久保存，重连不自动轮换。普通 TUN 流量不使用 mixed 入口鉴权；
Android 额外开启「系统 HTTP 代理」或桌面开启鉴权后，外部应用需支持代理认证，否则可能无法联网。
「系统 HTTP 代理」默认关闭，桌面鉴权默认关闭；应用内网络请求已接入认证。
Linux 需要正在运行且已解锁的 Secret Service，发行包已补 libsecret 依赖。
密钥库锁定时应先解锁后重试；密钥丢失时只能从原设备/备份恢复或显式重置后重新导入，程序不会自动清空数据。

## CI 和发布

- Linux Flutter 3.47.2 下载增加官方 SHA-256；Gradle 9.3.1 wrapper 增加发行包摘要。
- sing-box v1.13.19 固定提交 `b5ebaa1fc0f2b94256180b95468e73ef53caa27d`；gomobile 固定提交 `b2c30f47825831593d6980af8191527490f9c968`，缓存包含这些构建输入和脚本。
- 发布要求 verify、deb/APK、Windows、Arch 全部成功，取消部分平台发布。
- 正式 tag 使用 `release` environment；其他构建不恢复发布签名。**仓库维护者仍须配置 environment 的受信任 refs/审批规则，并将 FERRY_KEY* 从 repository secrets 迁入该环境**，YAML 引用本身不创建保护规则。
- 已从现有 v0.4.1 公开发行 APK 核实发布证书 SHA-256：`2e414a31434c01f6ad7cd0ed80dcdca3f9de9c3983644a150f5110ea6c7ebbcc`。签名验证成功后才匹配证书，兼容新旧 apksigner 展示格式，换钥需显式审查。
- 输出 CycloneDX 包清单、OSV 告警、发布 SHA256SUMS，并在正式发布前生成 GitHub 构建来源证明。Android 和 Windows 分别从原生二进制的 Go build info 提取实际链接模块；不会把所有 go.mod 构建工具依赖都当成已打包内容。
- Dart 锁定依赖扫描失败会阻断 verify。Go 告警在开发构建中保留报告；**正式 tag 会阻断发布**。网络或扫描失败不会被当成“无漏洞”。
- Dart、Android 和 Windows 的依赖报告独立上传；扫描失败时仍保留已经生成的清单及告警，供排查下载。
- 新增 Dependabot 的 Pub、Gradle 和 Actions 受控更新配置。
- Android/Linux 打包分离 Dart 调试信息，CI 保留符号供崩溃还原。
- Gradle `exportReleaseDependencies` 在执行阶段解析实际 `releaseRuntimeClasspath`，遇到未解析依赖失败；
  导出 126 个 Maven 模块并并入 CycloneDX/OSV，CI 保留原始清单。本轮 Pub+Maven 共 219 项未返回公告。

### 当前发布阻断：Go 依赖告警

实际链接的 Android 核心中，OSV 返回 **9 个模块**存在版本告警：brotli、chi、compress、x/crypto、x/mod、x/net、x/sys、x/text、grpc。
详情保存在 [`security-advisories-2026-11-10.json`](security-advisories-2026-11-10.json)。这属于版本匹配，**没有完成漏洞函数可达性分析**，也不是整机安全证明。
本次扫描中 Dart 锁定依赖未返回公告；续轮已补齐 Maven 依赖版本审计。

已核实上游最新正式版 v1.14.4（2026-10-24 发布）的 go.mod，仍包含这些模块的部分受影响版本，不能通过简单替换版本号宣称告警全部修复。
远端 Windows 实际产物另有 11 个模块命中公告，包括 edwards25519、DHCP 和其 Go 1.26.5 标准库；
不能只处理 Android 的 9 项。当前默认产物的正式发布门槛继续阻断这些告警。

已在独立目录制作[安全补丁候选](../patches/sing-box/README.md)，固定依赖版本并原样回移上游 Go 1.27 HTTP/2 兼容文件。
Linux / Windows 编译、Android AAR 和核心单元测试通过，AAR Java/JNI 接口逐字节一致。
按实际链接清单复扫：Linux+Pub 152 项、Windows+Pub 149 项、Android+Pub+Maven 278 项均未返回已知公告。
HTTP、Trojan、V2Ray HTTP/HTTP2、TUIC 上游本地自测未失败；Hysteria2 四种场景的大数据 TCP 测试超时，
原始固定核心在同一工具链下也复现。原因尚未确认，故候选**未接入正式构建**，
未覆盖当前 AAR，也未替换 Windows 二进制。详细输入、命令、许可和后续验收见候选说明。

## 体积实测

Go 1.27.3、NDK 28.2.13676358、同一 sing-box/gomobile 提交进行 A/B。CI 仍固定 Go 1.25.14，因此不能将本地字节数直接当成远端产物预言。

| 项目 | 含 Tailscale | 不含 Tailscale | 差异 |
| --- | ---: | ---: | ---: |
| libbox.aar | 17,945,503 字节 | 14,161,658 字节 | −21.1% |
| libbox.so | 51,254,392 字节 | 40,083,664 字节 | −21.8%，约 10.65 MiB |

两份 AAR 的 `classes.jar` **逐字节相同**。应用节点模型不提供 Tailscale，故默认关闭；`WITH_TAILSCALE=1` 可还原对照构建。
保留 gVisor、QUIC、WireGuard、uTLS 和 Clash API，没有以删除已支持协议换体积。

- 原审计 APK：**81.26 MiB**。
- 加入安全存储后的同代码 A/B 基线：**82.07 MiB**。
- 最终默认 APK，裁剪 Tailscale、分离 Dart 符号、R8 关闭：**70.35 MiB**（73,772,015 字节），较原审计基线约减少 **13.4%**。
- R8 实验产物：**64.97 MiB**。已加入 Go/JNI keep 规则并成功构建，但默认仍关闭，需真机验证绑定、扫码和协议矩阵后启用。
- Linux release bundle 本轮重建约 **28 MiB**，此前现有 bundle 约 30 MiB；不同构建状态下的文件大小比较，不是运行内存收益。

`--analyze-size` 与 `--split-debug-info` 在此 Flutter 版本不能同时使用，分别构建并保留分析数据/符号。
本地 APK 使用 **Android Debug 证书**，不能覆盖正式签名安装；没有使用生产私钥或发布该文件。

## 导入性能实测

使用 `benchmark/import_benchmark_test.dart`，每种模式在独立进程运行，生成完全相同的 JSON 节点输入。以下为单轮 JIT 测量，不能代表 release 帧率或长期 RSS。

| 节点 | 同步总耗时 | 后台总耗时 | 同步主 isolate 最长 tick 间隔 | 后台最长 tick 间隔 |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 13.33 ms | 18.97 ms | 13.78 ms | 4.20 ms |
| 10,000 | 33.09 ms | 51.31 ms | 33.55 ms | 8.67 ms |

10k 对照进程峰值 RSS 约 152.6 MiB / 157.1 MiB。后台解析改善 UI 响应，但增加 isolate 启动、传输及内存开销；不声称总解析变快或内存下降。

```sh
flutter test benchmark/import_benchmark_test.dart --dart-define=MODE=sync --dart-define=COUNT=10000
flutter test benchmark/import_benchmark_test.dart --dart-define=MODE=isolate --dart-define=COUNT=10000
python3 scripts/sample-memory.py --pid GUI_PID --pid CORE_PID --duration 7200 --output build/memory.csv
```

内存采样脚本记录 RSS/PSS/Private_Dirty、FD 和线程数，不读取配置或网络内容。本轮只验证脚本可运行，没有执行 2–8 小时设备压测。

## Gradle 资源对比

新增 `scripts/profile-build.py` 跟踪构建进程及其子进程，包含脱离原进程组的 Java 进程，
以 PID 和启动时间区分 PID 复用，输出时间序列 CSV 与 JSON 峰值摘要。
用独立子会话中的 16 MiB 分配检查了子进程采样；最初只采进程组的无效样本已丢弃。

以下均为同一工作区、依赖与 SDK 已缓存、`--no-daemon --rerun-tasks` 的 294 项任务强制重建，
Kotlin 使用 `-Pkotlin.compiler.execution.strategy=in-process`，采样间隔 0.5 秒。
没有清除依赖缓存，不是冷下载基准，也不能代表所有 runner 或严格性能显著性。

| heap / metaspace / workers | 总耗时 | 进程树采样峰值 PSS | 峰值 RSS |
| --- | ---: | ---: | ---: |
| 8 GiB / 4 GiB / 默认 | 24.214 s | 3,719,732 KiB（3.55 GiB） | 3,802,480 KiB |
| 4 GiB / 1 GiB / 2（首轮） | 31.369 s | 3,491,929 KiB | 3,535,536 KiB |
| 4 GiB / 1 GiB / 2（复测） | 29.847 s | 2,889,639 KiB | 2,933,292 KiB |
| 4 GiB / 1 GiB / 默认 | 23.560 s | 3,527,249 KiB（3.36 GiB） | 3,607,816 KiB |

采用 **4 GiB heap / 1 GiB metaspace、Kotlin 进程内编译、默认 worker 数量**。
限 2 workers 在本机降低并发但慢约 6–7 秒，内存峰值也有波动，保留为低内存机器的显式参数。
这限制构建 JVM 的预算，不等于所有进程总内存不超过 4 GiB；仍需观察远端首次 AAR/APK 构建。

```sh
cd android
python3 -B ../scripts/profile-build.py --interval 0.5 --output ../build/profiles/gradle.json -- \
  ./gradlew --no-daemon --rerun-tasks -Ptarget-platform=android-arm64 :app:assembleRelease
```

## 验收与仍需执行

- Flutter：静态分析无问题；续轮全量 694 项测试通过、21 项按原有条件跳过；新增安全界面布局和凭据主动展示测试通过。
- Python：16 项通过；actionlint v1.7.7 和 shell 语法检查通过。
- Android arm64 release、Linux release 构建成功；APK 原生库、ELF LOAD 与 ZIP 16 KiB 对齐、签名有效性通过。
- 本地验收没有安装应用、切换真实 VPN 或发布版本。根目录遗留 cache.db 已移出工作区，Python 字节码已清理并加入忽略规则。
- 未进行真实 Android Keystore/Windows 凭据库/Linux Secret Service 的多设备迁移验收。仅编译和模拟存储测试不能替代这些验证。
- 尚需真机 Android 慢启动/立刻停止/连续重载/撤销 VPN/进程重建、至少 100 轮连接循环，以及 2–8 小时 native 内存/FD 测量。
- Android 停止不再阻塞主线程，但仍需等待正在执行的 Go 调用返回；没有宣称能够强制中断任意 native I/O。
- R8 继续保持可选；Gradle 资源实验及默认 JVM 限额已完成，远端内存/耗时仍需持续观察。规则集签名清单、受限权限 helper、固定 Arch 镜像等仍未实施。
- Linux 文件 capability 依然属于整个可执行文件，首次授权不等于仅向本 GUI 授权。多用户隔离需要后续受控 helper/服务方案。
- 远端构建结果以提交对应的 GitHub Actions 为准。生产 environment 规则、默认核心 Go 告警、候选协议验收和跨平台真机验收仍是发布前待办。
