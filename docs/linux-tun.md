# Linux TUN 授权 / authorization

首次启用 TUN **不一定弹出密码框**：Ferry 先检查实际执行文件的 `cap_net_admin` 与
`cap_net_raw`。已经具备权限时直接连接；缺少权限、授权工具齐备且桌面有运行中的 polkit
认证代理时，由系统策略决定是否显示认证框（授权缓存或管理员策略也可能免去输入密码）。
Ferry 本身不以 root 运行，安装包也不自动为核心执行 `setcap`。

On first TUN use, Ferry checks the actual executable's capabilities. Existing
capabilities skip authorization. Otherwise `pkexec` asks the desktop's polkit
agent; system policy and cached authorization determine whether a dialog appears.
The GUI itself never runs as root. System proxy mode does not request capabilities.

## 发行版差异

| 环境 | 工具与认证代理 | Ferry 行为 |
| --- | --- | --- |
| Debian / Ubuntu | `pkexec`（旧系统由 `policykit-1` 提供）、`libcap2-bin`，桌面 polkit 代理 | deb 声明工具依赖，推荐 `polkit-1-auth-agent` 虚拟包；GNOME/KDE 会话或独立代理负责显示认证框 |
| Arch / Manjaro | `polkit`、`libcap`，桌面 polkit 代理 | Arch 包声明工具依赖；无代理的桌面可安装并自动启动 `polkit-gnome`，或使用桌面自带代理 |
| Fedora | `polkit`、`libcap`，桌面 polkit 代理 | 相同的 capability 流程；项目当前未提供 RPM 包 |
| Sway / Hyprland / 精简窗口管理器 | 除工具外，需配置会话启动认证代理 | 仅安装 polkit 服务不会自动得到可见认证框；使用适合该桌面的代理并确认已启动 |
| NixOS | `pkgs.sing-box`、`pkgs.libcap`、声明式 capability 包装器 | 优先使用 `/run/wrappers/bin/sing-box`；不直接修改只读 Nix store |
| 容器 / 受限沙箱 / `nosuid` 文件系统 | 宿主策略可能禁止 TUN 或忽略文件 capability | 文件权限正确仍可能无法创建 TUN；需调整运行环境，或使用系统代理模式 |

桌面代理只负责显示身份认证，最后仍由 polkit 策略决定授权；没有管理员认证资格时不会自动绕过。
`pkexec` 使用 `--disable-internal-agent`，无桌面代理时不会退回不可见的终端密码输入而挂起。

## 授权流程与失败恢复

- 工具缺失：提示安装工具，停止 TUN 启动；不把检查失败当成已有权限。
- 用户取消（pkexec 126）：显示已取消；用户可以重新连接，不自动重试。
- 无法完成认证（pkexec 127）：提示检查认证代理、管理员认证和系统策略；不武断归因于用户取消。
- 不可信路径：仅系统前缀内、名为 `sing-box`、解析后文件和祖先由 root 所有且其他用户不可修改的目标可申请授权。
- 授权失败或复查失败：显示文件 capability / 文件系统排查提示；`setcap` 返回 0 后仍重新读取权限。
- NixOS 未配置包装器：显示声明式配置指引，不对 `/nix/store` 或 wrapper 执行临时修改。

工具只从固定系统目录解析，不经用户 `PATH` 选择 root 命令；所有参数独立传递，没有 shell。
对于 Nix 工具，只允许 root 所有且带 sticky bit、非全局可写的 `/nix/store` 作为组可写祖先；
文件本身和其他祖先仍必须不可由组或其他用户写入。应用提示不拼接可直接执行的任意路径命令。

传统发行版若核心缺少权限，典型授权命令相当于：

```sh
pkexec --disable-internal-agent /usr/sbin/setcap cap_net_admin,cap_net_raw+ep /usr/bin/sing-box
```

实际工具位置按发行版解析，不能照搬示例路径。权限对该可执行文件的所有调用者有效。
核心软件包升级可能替换文件并移除 capability，此时下次 TUN 连接重新请求；发行版已经附带权限时无需弹窗。

## NixOS 配置示例

在系统配置中加入以下设置，将 `yourUser` 换成实际用户名后执行系统重建，并重新登录使附加组生效：

```nix
{ pkgs, ... }: {
  environment.systemPackages = [ pkgs.sing-box pkgs.libcap ];
  security.polkit.enable = true;

  users.groups.ferry-tun = {};
  users.users.yourUser.extraGroups = [ "ferry-tun" ];
  security.wrappers.sing-box = {
    source = "${pkgs.sing-box}/bin/sing-box";
    owner = "root";
    group = "ferry-tun";
    permissions = "u+rx,g+x";
    capabilities = "cap_net_admin,cap_net_raw+ep";
  };
}
```

Ferry 优先使用已校验的 `/run/wrappers/bin/sing-box`，再查找内置位置和 `PATH`。
显式 `SINGBOX_BINARY` 优先级更高：应移除指向 `/nix/store/.../bin/sing-box` 的覆盖，或指向上述包装器。
包装器通过 NixOS 重建生成；正常连接时不需要再次弹窗。限制执行组只约束调用者范围，不把权限限定为 Ferry。

The NixOS wrapper is managed by the system configuration and restricted to the
`ferry-tun` group in this example. Rebuild and log in again, then remove a
`SINGBOX_BINARY` override that bypasses the wrapper. Do not run `setcap` on store files.

## 验证边界与依据

已自动测试参数边界、capability 解析、缺工具/取消/失败、授权复查、NixOS 工具和包装器解析、
不可信路径拒绝，以及启动状态/本地化提示。测试使用模拟授权命令，不弹出真实提权框。
尚未在每种发行版、桌面、NixOS 实机和受限容器中验证；测试不证明任意环境都能显示认证框。

依据：
- polkit 官方 [pkexec 手册](https://www.freedesktop.org/software/polkit/docs/latest/pkexec.1.html)
- Debian 官方 [pkexec 包](https://packages.debian.org/trixie/pkexec) 与 [认证代理虚拟包](https://packages.debian.org/trixie/polkit-1-auth-agent)
- NixOS [security.wrappers 实现](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/security/wrappers/default.nix)
