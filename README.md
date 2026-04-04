# vless-onekey

一键安装 `Xray + VLESS + Reality`，并自动导出 `clashverge.yaml`、`shadowrocket.conf`、`node.vless.txt` 和 `shadowrocket-node.png`。

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y
```

查看参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) --help
```

## 生成结果

默认输出目录：

```bash
/root/vless-export
```

- `clashverge.yaml`
  给 `Clash Verge / Clash Mi / Karing` 导入的配置文件。
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

脚本会安装 `lrzsz`，支持直接用 `sz` 下载：

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

- 默认发现已有 `xray` 配置时会拒绝覆盖，只有显式加 `--force-overwrite` 才会替换并先备份。
- 默认会随机选择一个常见国内 HTTPS 域名作为 `SNI`，也可以手动传 `--sni` 指定。
- `shadowrocket-node.png` 适合直接给 `Shadowrocket` 扫码。
- `clashverge.yaml` 适合 `Clash Verge / Clash Mi / Karing` 导入。
