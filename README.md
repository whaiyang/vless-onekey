# Xray VLESS Reality One-Click Installer

One-click install Xray VLESS Reality on Debian and Ubuntu. Automatically export Clash Verge config, Shadowrocket QR, VLESS node link, and support IPv4/IPv6 auto-detect.

## 一键安装

先选择一个与服务器同 ASN、支持 TLS 1.3、证书包含该域名且不是 Apple/iCloud 或免费 CDN 的目标站。脚本不会再随机猜测 SNI，并会在写配置前验证 TLS 1.3 和证书。

```bash
TARGET_DOMAIN="your-verified-target.example.com"
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y --sni "${TARGET_DOMAIN}"
```

查看参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) --help
```

默认安装或升级到 Xray 最新稳定版，但关闭无人值守自动更新。需要显式启用每日自动更新时：

```bash
TARGET_DOMAIN="your-verified-target.example.com"
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y --sni "${TARGET_DOMAIN}" --auto-update-xray
```

## 生成结果

默认输出目录：

```bash
/root/vless-export
```

- `<服务器IP>.yaml`
  给 `Clash Verge / Clash Mi / Karing` 导入的配置文件。
  默认只监听本机，不开放局域网访问，并内置 `AI`、`Telegram`、`Streaming` 单节点策略组。
  Clash Verge 的配置卡片会显示服务器 IP，而不是通用文件名。
- `shadowrocket-node.png`
  给 `Shadowrocket` 直接扫码导入的二维码。
- `node.vless.txt`
  单节点 `vless://` 链接文本。
- `shadowrocket.conf`
  `Shadowrocket` 配置文件。
- `metadata.json`
  节点参数明细，方便手工排查。
- `README.txt`
  服务器端生成结果说明。

## 下载到本地

脚本会安装 `lrzsz`，执行完成后默认自动运行：

也可以手动用 `sz` 下载：

```bash
sz /root/vless-export/*
```

只下载并导入 IP 命名的配置文件：

```bash
sz /root/vless-export/<服务器IP>.yaml
```

只下载二维码：

```bash
sz /root/vless-export/shadowrocket-node.png
```

## 说明

- 默认发现已有 `xray` 配置时会保留配置，只检查/更新 Xray 和自动更新设置；只有显式加 `--force-overwrite` 才会替换并先备份。
- 默认会安装/更新 `Xray-core` 最新稳定版；如果服务器已有 `xray`，会通过官方安装器检查并升级。
- 如果需要保留服务器上已有的 `xray` 二进制，可以传 `--skip-xray-upgrade`。
- 默认监听 `443/tcp`。最新 Xray 会对 REALITY 使用非 443 端口发出封锁风险警告；如确需其它端口，必须同时传 `--allow-non-443`。
- `--sni` 为必填；`dest-host` 默认与 SNI 相同。脚本会验证目标支持 TLS 1.3 且证书匹配 SNI。
- 默认关闭每日自动更新；可以传 `--auto-update-xray` 启用，默认时间为服务器本地时间 `03:30:00`。
- Xray 默认以独立的非特权系统用户 `xray` 运行，并通过 systemd 仅保留绑定低端口所需的能力，同时限制文件系统、设备和内核访问。
- 默认将 REALITY 最大握手时差限制为 `60000` 毫秒，服务器和客户端应保持时间同步。
- 服务端默认阻断代理访问私网、链路本地地址和云元数据地址。
- Xray 配置、节点链接、二维码和导出文件会使用最小读取权限；分享链接等同访问凭据，不要公开。
- 默认安装结束会自动执行 `sz /root/vless-export/<服务器IP>.yaml`，如果终端不支持 ZMODEM，可以传 `--skip-sz`。
- 自动更新由 `systemd` 管理：`xray-auto-update.timer` 和 `xray-auto-update.service`。
- 可以传 `--xray-beta` 使用 Xray 最新预发布版本；如果同时启用自动更新，后续自动更新也会跟随预发布通道。
- 会自动优先使用公网 IPv4；如果服务器只有 IPv6，会自动回落到 IPv6 并导出对应配置。
- `shadowrocket-node.png` 适合直接给 `Shadowrocket` 扫码。
- `<服务器IP>.yaml` 适合 `Clash Verge / Clash Mi / Karing` 导入。

查看自动更新状态：

```bash
systemctl status xray-auto-update.timer
journalctl -u xray-auto-update.service --no-pager
```

检查目标站是否适合 REALITY：

```bash
xray tls ping your-verified-target.example.com:443
```

安装成功后仍应从外部网络验证 `443/tcp` 可达，并用实际客户端完成一次代理请求。脚本的配置检查和服务状态检查不能替代端到端验证。
