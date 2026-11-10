# 固定核心安全补丁

Android 和 Windows 使用同一组固定源码、补丁与构建标签，版本标记为 **1.13.19-ferry.2**。
构建入口分别为 `scripts/build-libbox.sh` 和 `scripts/build-windows-core.sh`；
所有输入集中在 [`scripts/core-pins.json`](../../scripts/core-pins.json)。这不是官方 sing-box 发行版。
Linux 仍使用用户安装的核心，下面的内置核心修复不自动更新 Linux 系统软件包。

## 来源和固定输入

- 基础：SagerNet/sing-box `v1.13.19`，提交 `b5ebaa1fc0f2b94256180b95468e73ef53caa27d`。
- HTTP/2 兼容文件：上游 `v1.14.4`，提交 `c005f35300ce76427dc285481ec5695f5b179cd2`，
  `transport/v2rayhttp/force_close{,_go127,_go127_stub,_legacy}.go` 原样回移。
  四个文件已与该提交的原始文件逐字节核对。
- `security-2026-11-10.patch` SHA-256：
  `c82b65cb83b3966322df1f35303151b5d93f01e726a254e882929fea75d805d6`。
- Hysteria Brutal 窗口修复：原项目 apernet/hysteria（现 HyNetworks/hysteria）提交
  `f2ad1de5da52a1da9622285a1d61553ddaa41f21`（2026-07-12），
  `core/internal/congestion/brutal/brutal.go` 中 `CanSend` 和 `GetCongestionWindow` 两个函数原样回移。
  未包含后续 ACK-only pacing 等其他更改。
- 被修补的 sing-quic：`v0.6.4-0.20260803041914-d83826c306d7`，Go 模块校验和
  `h1:D46kmyvKMNVFvL3KXdq3T4vy8r29xCMmSqNuQHJBybE=`。
- `hysteria-window.patch` SHA-256：
  `b224c88281e63645ab451389c8538ad108e1c8135d9e6bc1096d7722926de90a`。
- Go **1.27.3**、`GOEXPERIMENT=nojsonv2`，JDK 17、NDK 28.2.13676358；
  gomobile 提交 `b2c30f47825831593d6980af8191527490f9c968`。

sing-box 回移代码 Copyright (C) 2022 nekohasekai，GPL-3.0-or-later，附加条件为未经许可不得使用
上游应用名称或暗示关联；完整许可见基础源码的 `LICENSE` 和 `COPYING`（若存在）。
Hysteria 两个函数的 MIT 许可及 Copyright 2023 Toby 声明保存在 [HYSTERIA-LICENSE](HYSTERIA-LICENSE)。

安全补丁直接升级 brotli 1.2.7、chi 5.4.0、compress 1.20.2、x/net 0.62.0、grpc 1.85.0、
edwards25519 1.2.0、DHCP `v0.0.0-20261014062924-c6bb46ad3f3a`、
x/crypto `v0.58.1-0.20261009181718-2f1f834330b2`；间接依赖由 Go MVS 选择后固定在补丁中。
x/crypto 0.58.0 和 chi 5.3.0 仍命中当时公告，不可用这两个较早版本替代。

升级后的 x/net 在 Go 1.27 下切换 HTTP/2 实现，旧核心的私有 `connPool` linkname 无法链接；
上游兼容文件解决了编译问题，但仍使用私有结构/符号，工具链升级必须重新验证。

## Hysteria2 超时原因和验收

原始核心与安全候选均在回环大数据 TCP 下载中超时。固定 sing-quic 的 Brutal 窗口仅按
带宽 × RTT 计算，没有报文大小下限，`CanSend` 又使用严格小于。在回环 RTT 很低时，
窗口小于一个数据报，无法维持正常发送和 ACK 进度；切换自动带宽控制可完成原有测试。

回移原项目已有实现：窗口至少为一个数据报，窗口恰好占满时允许继续发送。
没有降低数据量或放宽原测试每次传输的 10 秒时限；普通、salamander、端口跳跃、
跳跃+salamander 四个子场景连续两轮通过。额外边界测试覆盖极低 RTT、两种报文大小、
窗口上限和正常 RTT 下的原有带宽计算。

## 重现和来源记录

在 Ferry 根目录、固定工具链环境下运行：

```sh
# Android：需要 JDK 17、SDK、NDK；自动执行回环协议回归。
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=/path/to/sdk \
  ANDROID_NDK_HOME=/path/to/sdk/ndk/28.2.13676358 scripts/build-libbox.sh

# Windows：Windows Git Bash 本机构建，也可在 Linux 交叉编译。
scripts/build-windows-core.sh

# 只准备源码和运行回归；目标必须是不存在或为空的独立目录。
python3 scripts/prepare-core.py prepare --source /tmp/ferry-core-check
python3 scripts/test-core.py /tmp/ferry-core-check
```

脚本校验核心提交、补丁摘要、Go 版本和 sing-quic 模块校验和。补丁在独立源码副本中应用，
不修改共享 Go 模块缓存。来源清单记录补丁后文件树、实际 native 二进制与 Go build info 的摘要；
二进制的本地替换模块必须与准备的源码一致，未声明的替换会失败。

AAR 和 EXE 旁生成 `.build-info.json`、`.sources.json`。扫描命令必须同时提供两份清单：

```sh
python3 scripts/dependency-audit.py \
  --go-build-info android/app/libs/libbox.aar.build-info.json \
  --go-provenance android/app/libs/libbox.aar.sources.json \
  --maven build/app/reports/release-runtime-dependencies.json \
  --core-version v1.13.19 --scan
```

本地替换仍以原模块/版本保守查询 OSV，并在 SBOM 中记录补丁/源码树摘要，不能用替换路径隐藏告警。
Gradle 保留已由 Go `-s -w` 剥离符号的 libbox 原始字节，CI 检查 APK 中的摘要与来源清单一致。
Android 和 Windows 在普通分支及正式 tag 均执行阻断式扫描；扫描失败仍上传已有报告。

## 2026-11-10 本地验证与边界

- Android arm64 AAR、完整 release APK 与 Windows amd64 EXE 构建成功。
- AAR 14,114,042 字节；`classes.jar` 与旧核心逐字节一致，SHA-256
  `3de3266efb85764b23dd21bca49aea906f9f4d9ef98ca0053cfca995fd4c1b6f`。
- APK 73,722,863 字节（70.31 MiB），签名、原生库 ELF 和 ZIP 16 KiB 对齐、核心摘要检查通过。
- 实际链接清单 OSV 复扫未返回已知公告：Windows + Pub 149 项、Android + Pub + Maven 278 项。
  这是版本查询，不是漏洞函数可达性或长期稳定性证明。
- 回归包含 common/route/dns/libbox、HTTP、Trojan、HTTP/2、常规与 lite gRPC、WebSocket、
  Hysteria2、TUIC；上游测试仍启用 goleak。独立 DNS 测试覆盖 UDP/TCP、截断回退、Reset、超时及恢复。
- 测试只监听回环，禁用上游 Docker 初始化，不拉取测试镜像，不创建真实 TUN 或修改系统代理。
- WireGuard 实际传输、Android 生命周期/真实协议、Windows UAC/TUN 实机及长时内存验证仍待完成；
  此补丁不代替这些发布验收。远端流水线结果见[实施记录](../../docs/optimization-implementation-2026-11-10.md)。

未来采用包含这些修复且兼容的上游版本时，应移除相应回移补丁并重新验证。
