# vless-onekey

一键安装 `Xray + VLESS + Reality`，并自动导出：

- `clashverge.yaml`
- `shadowrocket.conf`
- `node.vless.txt`
- `shadowrocket-node.png`

适合全新 `Debian / Ubuntu` 服务器，或你明确知道自己要替换现有 `xray` 配置的场景。

## 一键安装

直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y --sni www.cloudflare.com --node-name my-vps
```

## 常用参数

```bash
--sni HOST
--node-name NAME
--port PORT
--force-overwrite
--skip-firewall
--skip-packages
--skip-qr
-y, --yes
```

查看帮助：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) --help
```

## 生成结果

默认输出目录：

```bash
/root/vless-export
```

生成文件：

- `node.vless.txt`
- `clashverge.yaml`
- `shadowrocket.conf`
- `shadowrocket-node.png`
- `metadata.json`
- `README.txt`

## 下载到本地

脚本会安装 `lrzsz`，支持直接用 `sz` 下载：

```bash
sz /root/vless-export/*
```

如果只想下载二维码：

```bash
sz /root/vless-export/shadowrocket-node.png
```

## 仓库文件

- `install.sh`
  仓库公开发布入口，推荐给用户直接调用。
- `install_vless_reality_onekey.sh`
  兼容旧命名的安装脚本。
- `vless_export_assets.py`
  本地把 `vless://` 链接转换成 `Clash Verge / Shadowrocket` 配置和二维码的工具。

## 说明

- 默认发现已有 `xray` 配置时会拒绝覆盖。
- 只有显式加 `--force-overwrite` 才会替换旧配置，并且会先备份。
- `shadowrocket-node.png` 是单节点二维码，适合直接给 `Shadowrocket` 扫码。
- `clashverge.yaml` 适合 `Clash Verge / Clash Mi / Karing` 导入。
- 当前脚本面向 `TCP + VLESS + Reality + xtls-rprx-vision` 这一种常见组合。
