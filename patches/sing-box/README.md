# 固定核心与兼容补丁

Android 和 Windows 统一基于最新稳定版 **sing-box v1.14.4**（2026-10-24 发布，
2026-11-10 核实），构建标记 **1.14.4-ferry.1**。这不是官方二进制发行版。
Linux 使用发行版安装的核心，内置核心补丁不会自动修改系统包。

全部固定输入与 SHA-256 以 [`scripts/core-pins.json`](../../scripts/core-pins.json) 为准。
构建入口：`scripts/build-libbox.sh`、`scripts/build-windows-core.sh`。

## 来源

- sing-box：`v1.14.4`，提交 `c005f35300ce76427dc285481ec5695f5b179cd2`。
- gomobile：`v0.1.13` 对应提交 `9f03b8f25789099c5c8abef4a02085da783ba923`，与上游构建入口一致。
- Go 1.27.4、`GOEXPERIMENT=nojsonv2`，JDK 17、NDK 28.2.13676358。
- sing-quic：`v0.7.2-0.20261020082049-7e0a5869a5f4`，模块校验和
  `h1:QuhAb8QW0pKYmSvfj/nK91libunBwVJiWb852yidlxI=`。
- Hysteria 窗口函数来源：apernet/hysteria（现 HyNetworks/hysteria）提交
  `f2ad1de5da52a1da9622285a1d61553ddaa41f21`（2026-07-12），
  `core/internal/congestion/brutal/brutal.go` 的 `CanSend` 与 `GetCongestionWindow`。
  MIT 许可和 Copyright 2023 Toby 声明见 [HYSTERIA-LICENSE](HYSTERIA-LICENSE)。

## 保留的修改

`core-1.14.4.patch` 升级仍命中历史安全公告的依赖：brotli 1.2.7、chi 5.4.0、
compress 1.20.2、x/net 0.62.0、grpc 1.85.0、edwards25519 1.2.0、
DHCP `v0.0.0-20261014062924-c6bb46ad3f3a`、
x/crypto `v0.58.1-0.20261009181718-2f1f834330b2`；Go MVS 的间接升级也固定在补丁中。
旧版 HTTP/2 回移文件已由 1.14.4 自带，删除了重复回移；私有 Go 符号仍需随工具链升级重新验证。

1.14 删除 `SetMemoryLimit`。旧 Android 调用实际设置的是 GC 百分比 10，并未设置 iOS 的
45 MiB 上限。补丁提供 `ConfigureFerryMemory` 保留该 GC 策略，并有运行时回归断言；
不启用新的 OOM 网络重置服务，也不声称这是硬性内存上限。

`hysteria-window.patch` 仍有必要：1.14.4 的 sing-quic 在极低 RTT 下仍可能产生小于一个
数据报的窗口；严格小于判断又阻碍 ACK 进度。补丁保持窗口至少为一个数据报，并允许
窗口恰好占满时继续发送。未包含后续 ACK-only pacing 等改动，没有减少测试数据或延长时限。

Android 平台实现同步适配多 DNS 迭代器、新回调、Android 10 以下 procfs 查询入口。
未支持的 Shell、SSH agent、bridge 与崩溃注入入口显式拒绝，不开放这些能力。

## 重现与审计

```sh
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=/path/to/sdk \
  ANDROID_NDK_HOME=/path/to/sdk/ndk/28.2.13676358 scripts/build-libbox.sh
scripts/build-windows-core.sh

python3 scripts/prepare-core.py prepare --source /tmp/ferry-core-check
python3 scripts/test-core.py /tmp/ferry-core-check

python3 scripts/dependency-audit.py \
  --go-build-info android/app/libs/libbox.aar.build-info.json \
  --go-provenance android/app/libs/libbox.aar.sources.json \
  --maven build/app/reports/release-runtime-dependencies.json \
  --core-version v1.14.4 --scan
```

源码目录必须为空。补丁在独立副本中应用，不修改 Go 模块缓存。校验核心提交、模块校验和、
补丁摘要及跨平台一致的补丁后文件树摘要；禁用 autocrlf，文件名按大小写敏感 POSIX 顺序排列。
来源清单关联实际 native 二进制与 Go build info 摘要，未声明的本地替换会失败。
APK 内 libbox 字节必须与审计清单完全一致。普通分支和正式 tag 均阻断 OSV 告警或扫描失败。

## 2026-11-10 验证与边界

- Android arm64 AAR、完整 APK、Windows amd64 EXE 构建成功；新版 JNI/Kotlin 编译通过。
- 实际链接清单扫描：Android + Pub + Maven 314 项，Windows + Pub 171 项，未返回已知公告。
- common/route/dns/libbox、HTTP、Trojan、HTTP/2、常规/lite gRPC、WebSocket、Hysteria2、TUIC
  回环回归通过，上游 goleak 保留；独立 DNS 覆盖 UDP/TCP、截断回退、Reset、超时和恢复。
- 1.14 新增的 `TestUnshareNamespace` 需要网络命名空间权限，明确从无特权回环测试中排除；
  未创建真实 TUN、未连接用户 Docker、未修改系统代理，不将该测试计为已通过。
- AAR 20,662,044 字节；libbox.so 59,938,640 字节。最终 APK 93,645,807 字节（89.31 MiB），
  签名、ZIP/ELF 16 KiB 对齐、native 来源摘要验证通过。
- 相对 1.13.19-ferry.2 的 70.31 MiB APK 增大约 19 MiB，主要来自 native 核心增加
  19,899,040 字节；不是体积优化收益。未开启未经真机验证的 R8 或删除已支持协议来抵消增长。
- 本地 APK 使用调试签名，不能覆盖正式签名版本。Android 真机生命周期、Windows UAC/TUN、
  WireGuard 实际传输、长时内存和受保护正式发布仍需设备/环境验收。

完整结果和持续待办见[实施记录](../../docs/optimization-implementation-2026-11-10.md)与
[优化计划](../../docs/optimization-plan.md)。上游含相应修复时移除对应补丁并重新验证。
