# 核心安全补丁候选（未启用）

`security-2026-11-10.patch` 是针对当前固定核心的可复现候选补丁。
**构建脚本和 CI 尚不应用它，也未替换仓库中的本地产物。**
Hysteria2 回归仍有未解释的超时，正式核心升级和发布阻断继续保留。

## 来源和固定输入

- 基础：SagerNet/sing-box `v1.13.19`，提交 `b5ebaa1fc0f2b94256180b95468e73ef53caa27d`。
- HTTP/2 兼容文件：上游 `v1.14.4`，提交 `c005f35300ce76427dc285481ec5695f5b179cd2`，
  `transport/v2rayhttp/force_close{,_go127,_go127_stub,_legacy}.go` 原样回移。
  四个文件已与该提交的原始文件逐字节核对。
- 验证工具链：Go **1.27.3**、`GOEXPERIMENT=nojsonv2`，JDK 17、NDK 28.2.13676358；
  gomobile 提交仍为 `b2c30f47825831593d6980af8191527490f9c968`。
- 补丁 SHA-256：`c82b65cb83b3966322df1f35303151b5d93f01e726a254e882929fea75d805d6`。

上游代码 Copyright (C) 2022 nekohasekai，GPL-3.0-or-later，附加条件为未经许可不得使用
上游应用名称或暗示关联。此补丁中的上游代码保留这些许可条件；完整许可见基础源码的
`LICENSE` 和 `COPYING`（若存在）。此候选不是官方 sing-box 发行版。

直接升级 brotli 1.2.7、chi 5.4.0、compress 1.20.2、x/net 0.62.0、grpc 1.85.0、
edwards25519 1.2.0、DHCP `v0.0.0-20261014062924-c6bb46ad3f3a`、
x/crypto `v0.58.1-0.20261009181718-2f1f834330b2`；间接依赖由 Go MVS 选择后固定在补丁中。
其中 x/crypto 0.58.0 和 chi 5.3.0 仍命中公告，故不能用这两个较早版本替代。

升级后的 x/net 在 Go 1.27 下切换 HTTP/2 实现，旧核心的私有 `connPool` linkname 无法链接；
上游兼容文件解决了编译问题，但仍使用私有结构/符号，工具链升级必须重新验证。

## 重现候选

在独立目录中执行，勿覆盖本地运行中的核心：

```sh
git clone --depth 1 --branch v1.13.19 https://github.com/SagerNet/sing-box core-candidate
cd core-candidate
test "$(git rev-parse HEAD)" = b5ebaa1fc0f2b94256180b95468e73ef53caa27d
git apply /absolute/path/to/ferry/patches/sing-box/security-2026-11-10.patch
export GOEXPERIMENT=nojsonv2
tags=with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,badlinkname,tfogo_checklinkname0
go build -trimpath -tags="$tags" -ldflags='-s -w -checklinkname=0' -o sing-box-candidate ./cmd/sing-box
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -tags="$tags" \
  -ldflags='-s -w -checklinkname=0' -o sing-box-candidate.exe ./cmd/sing-box
go test -tags="$tags" -ldflags=-checklinkname=0 ./common/... ./route/... ./dns/... ./experimental/libbox
go version -m -json sing-box-candidate > linux-build-info.json
go version -m -json sing-box-candidate.exe > windows-build-info.json
```

Android 在上述目录、已有固定 gomobile/gobind、JDK/SDK/NDK 环境下构建：

```sh
gomobile bind -o libbox-candidate.aar -target android/arm64 -androidapi 23 \
  -javapkg=io.nekohasekai -libname=box -trimpath -buildvcs=false \
  -ldflags='-X github.com/sagernet/sing-box/constant.Version=v1.13.19-ferry.1 -X internal/godebug.defaultGODEBUG=multipathtcp=0 -s -w -buildid= -checklinkname=0' \
  -tags="$tags" ./experimental/libbox
unzip -p libbox-candidate.aar jni/arm64-v8a/libbox.so > libbox-candidate.so
go version -m -json libbox-candidate.so > android-build-info.json
```

回到 Ferry 根目录，使用 `scripts/dependency-audit.py --go-build-info <对应清单> --core-version v1.13.19 --scan`
分别复扫；Android 再提供 `--maven build/app/reports/release-runtime-dependencies.json`。
不要把候选清单当作默认发行产物清单。

## 2026-11-10 验证与剩余工作

- Linux / Windows amd64 编译、Android arm64 AAR 构建、上述核心单元测试通过。
- AAR 14,114,757 字节；与现有 AAR 的 `classes.jar` 逐字节一致，SHA-256
  `3de3266efb85764b23dd21bca49aea906f9f4d9ef98ca0053cfca995fd4c1b6f`。
- OSV 未返回已知公告：Linux + Pub 152 项、Windows + Pub 149 项、Android + Pub + Maven 278 项。
  这是版本查询，不是漏洞函数可达性或长期稳定性证明。
- 上游独立 `test` 模块用相同标签和 `-mod=mod -count=1 -timeout=5m` 运行
  `TestHTTPSelf`、`TestTrojanSelf`、`TestTrojanPlainSelf`、`TestV2RayHTTPSelf`、
  `TestV2RayHTTPPlainSelf`、`TestHysteria2Self`、`TestTUICSelf`。
  实验只把这些测试的监听地址及 TCP/UDP 测试端点收敛到 127.0.0.1，没有开启真实 VPN/TUN。
  HTTP、Trojan、V2Ray HTTP/HTTP2 和 TUIC 无测试失败；Hysteria2 四种子场景在大数据 TCP 阶段超时。
- 原始固定核心、同一 Go 工具链及回环设置下的 Hysteria2 四种子场景同样超时。
  因而不能证明补丁引入此问题，也不能把该协议标为验收通过。
- 必须继续定位 Hysteria2 失败，补 gRPC/WireGuard/DNS、Android 生命周期/真实协议、Windows 实机回归。
  再决定是否将补丁接入两平台构建、将 CI Go 从 1.25.14 升到经过验证的版本、更新缓存键和来源记录。
  Windows 也需从同一补丁源码构建，不能继续分发带告警的原始官方二进制。

候选以补丁保存便于复核及后续重现；未来采用兼容上游版本时，应删除此候选和过期说明。
