# 优化待办

更新：2026-11-10。本文只保留当前剩余工作；本轮改动、性能/体积基线及验证结果见
[优化实施记录](optimization-implementation-2026-11-10.md)，历史设计与已完成计划可从 Git 历史查看。

## 发布前必须处理

| 优先级 | 工作 | 完成标准 |
| --- | --- | --- |
| P0 | 生产签名隔离 | 配置 GitHub `release` environment 的允许 refs/审批，把 FERRY_KEY* 从仓库级迁入该环境；验证非发布构建无法取得生产密钥 |
| P1 | 正式发布验收 | 补丁核心 `8981ed1` 的 verify、deb/APK、Windows、Arch 已全部成功，运行 `42768295287`；正式 tag 的生产证书、发布摘要与来源证明仍需受保护发布验收 |
| P1 | 真实凭据库迁移 | Android Keystore、Windows 凭据库、Linux Secret Service 分别验证旧数据迁移、锁定/解锁、部分失败重试、密钥丢失、升级和备份/设备迁移行为 |
| P1 | Android 生命周期与协议 | 本地 HTTP/2、gRPC、WebSocket、Hysteria2、TUIC、DNS 回归已通过；仍须实机验证慢启动后立即停止、连续重载、VPN 撤销、服务重建及部分初始化失败，至少 100 轮连接循环，检查 QUIC/WireGuard/TUN/DNS 和 JNI 绑定 |
| P1 | Windows 实机回归 | UAC 接管成功/拒绝/超时、第二实例激活、Job Object 清理、TUN 创建、核心异常退出和 WinINet 恢复；单元测试不能代替系统验收 |
| P1 | 长时内存验证 | 固定负载和构建，分别记录 GUI/core 的 RSS、PSS、Private_Dirty、FD、线程数；可见/日志页/托盘场景运行 2–8 小时，必要时做 Dart heap diff 和 native 分配追踪 |

版本告警不是漏洞函数可达性结论。不得仅把扫描改成警告或移除检查来满足发布条件。
历史未修补产物的告警快照见 [security-advisories-2026-11-10.json](security-advisories-2026-11-10.json)。
当前 1.14.4 补丁核心的 Windows+Pub 171 项、Android+Pub+Maven 314 项本地复扫均未返回公告；
两平台普通分支与正式 tag 均阻断告警和扫描失败，后续依赖变更仍需持续扫描。

## 后续优化与兼容性

| 优先级 | 工作 | 当前边界 / 验收 |
| --- | --- | --- |
| P1 | 代理鉴权外部应用兼容矩阵 | 组合设置提示、中英文说明及大字体/横竖屏测试已完成；继续验证实际浏览器/客户端的认证支持。Android 默认鉴权、系统 HTTP 代理默认关闭；桌面鉴权默认关闭 |
| P1 | 依赖审计深化 | 已覆盖 Pub、实际链接 Go 与 Gradle releaseRuntimeClasspath 的 126 个 Maven 模块；本轮 Pub+Maven 219 项未命中公告，仍需漏洞函数可达性分析和持续复扫 |
| P2 | R8 正式启用 | 实验 APK 约 64.97 MiB，已有 JNI keep 规则；真机扫码、绑定和协议矩阵通过后再改默认值，目前保留 `FERRY_R8=1` 实验入口 |
| P2 | 大连接量开销 | 隐藏时已停止构建连接明细，但仍需解码完整 JSON；比较 1k/10k 活跃连接时的 CPU、堆、消息频率，再决定降低采样或改协议 |
| P2 | runner 资源与镜像 | 本机已完成 Gradle 进程树采样对比，采用 4 GiB heap、1 GiB metaspace、Kotlin 进程内编译及默认 workers；继续观测远端冷/热缓存，固定 Arch 镜像并建立定期更新流程 |
| P1 | Linux 发行版实机验收 | 工具依赖、错误分类、授权复查、NixOS 包装器和模拟流程测试已完成；仍需在 GNOME/KDE/精简窗口管理器、NixOS、受限文件系统验证真实认证和 TUN |
| P2 | 1.14 核心包体分析 | 新 APK 89.31 MiB，较 1.13 版本增加约 19 MiB，主要为 native；评估上游新增能力的链接开销，保持已支持协议和安全检查 |
| P2 | Linux 权限隔离 | 当前检查真实路径、root 所有权和父目录权限，安装包不自动 setcap；文件 capability 仍对整个可执行文件生效，多用户隔离需受控 helper/服务 |
| P2 | 规则集可信来源 | 现有长度/魔数和 HTTPS 校验不能代替签名；设计受信清单、签名/摘要校验和更新策略 |
| P2 | Windows 共享 API 层 | 已接入有界 HTTP；仍有单独的控制 API/轮询实现。合并前验证轮询与 WebSocket 行为差异，避免仅为减少代码而改变功能 |
| P2 | 其他体积实验 | 评估扫码依赖和字体子集，保留离线/无 GMS 扫码及语言覆盖；收益低于已经完成的 libbox 裁剪 |

Android 后台串行化消除了主线程等待，但停止仍需等待正在执行的 Go 调用返回；
不保证能强制中断任意 native I/O。内存采样脚本见 `scripts/sample-memory.py`，
历史测量与不能据此下的结论见[内存调查](memory-investigation-2026-10.md)。

## 已完成，不再列为待办

- AppState/运行时串行队列、会话代号、展示设置不触发核心重载、Android 与桌面退出语义区分。
- ConfigFacts、动态端口、链式代理及环路校验、Clash YAML 导入、策略组规则集。
- Windows Named Mutex、UAC ready 确认及 WinINet journal 已有实现；上表保留的是实机验证。
- 有界 HTTP/取消、Linux 轮询去重、隐藏窗口明细降负载、订阅后台解析和 QR 解码前预算。
- 凭据库迁移、随机代理密码、Android 备份排除、更新链接限制、Linux 提权路径校验。
- 核心裁剪、Dart 符号分离、工具链/源码固定、签名/对齐检查、SBOM/OSV 与发布门槛。
- 代理鉴权与系统代理组合提示、凭据持久性说明；实际 Maven 依赖清单导出和 CI 审计。
- Gradle JVM 限额与进程树采样；2 workers 本机耗时回退，未设为默认。
- 内置核心升级至 1.14.4、Android 平台接口适配、原生依赖安全升级、Go 1.27 HTTP/2 兼容、Hysteria2 低 RTT 窗口修复；Android/Windows 同源构建、补丁来源和 APK 摘要校验。见[核心补丁说明](../patches/sing-box/README.md)。

- Linux 授权工具依赖、具体恢复提示、授权复查、NixOS 声明式包装器发现和说明。

OpenVPN、新桌面代理后端等属于独立功能评估，不作为本轮缺陷修复的未完成项。
