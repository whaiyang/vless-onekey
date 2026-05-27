# Xray VLESS Reality One-Click Installer

One-click install Xray VLESS Reality on Debian and Ubuntu. Automatically export Clash Verge config, Shadowrocket QR, VLESS node link, and support IPv4/IPv6 auto-detect.

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y
```

查看参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) --help
```

默认会启用 Xray 自动更新，无需额外参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y
```

## 生成结果

默认输出目录：

```bash
/root/vless-export
```

- `clashverge.yaml`
  给 `Clash Verge / Clash Mi / Karing` 导入的配置文件。
  默认只监听本机，不开放局域网访问，并内置 `AI`、`Telegram`、`Streaming` 单节点策略组。
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

```bash
sz /root/vless-export/clashverge.yaml
```

也可以手动用 `sz` 下载：

```bash
sz /root/vless-export/*
```

只下载 `clashverge.yaml`：

```bash
sz /root/vless-export/clashverge.yaml
```

只下载二维码：

```bash
sz /root/vless-export/shadowrocket-node.png
```

## 说明

- 默认发现已有 `xray` 配置时会保留配置，只检查/更新 Xray 和自动更新设置；只有显式加 `--force-overwrite` 才会替换并先备份。
- 默认会安装/更新 `Xray-core` 最新稳定版；如果服务器已有 `xray`，会通过官方安装器检查并升级。
- 如果需要保留服务器上已有的 `xray` 二进制，可以传 `--skip-xray-upgrade`。
- 默认启用每日自动更新，默认时间为服务器本地时间 `03:30:00`，也可以用 `--auto-update-time HH:MM` 指定。
- 如果不想启用自动更新，可以传 `--skip-auto-update-xray`。
- 默认安装结束会自动执行 `sz /root/vless-export/clashverge.yaml`，如果终端不支持 ZMODEM，可以传 `--skip-sz`。
- 自动更新由 `systemd` 管理：`xray-auto-update.timer` 和 `xray-auto-update.service`。
- 可以传 `--xray-beta` 使用 Xray 最新预发布版本；如果同时启用自动更新，后续自动更新也会跟随预发布通道。
- 默认会随机选择一个常见国内 HTTPS 域名作为 `SNI`，也可以手动传 `--sni` 指定。
- 会自动优先使用公网 IPv4；如果服务器只有 IPv6，会自动回落到 IPv6 并导出对应配置。
- `shadowrocket-node.png` 适合直接给 `Shadowrocket` 扫码。
- `clashverge.yaml` 适合 `Clash Verge / Clash Mi / Karing` 导入。

查看自动更新状态：

```bash
systemctl status xray-auto-update.timer
journalctl -u xray-auto-update.service --no-pager
```
