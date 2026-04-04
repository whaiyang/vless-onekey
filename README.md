# vless-onekey

一键安装 `Xray + VLESS + Reality`，并自动导出 `clashverge.yaml`、`shadowrocket.conf`、`node.vless.txt` 和 `shadowrocket-node.png`。

## 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y --sni www.cloudflare.com --node-name my-vps
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

## 说明

- 默认发现已有 `xray` 配置时会拒绝覆盖，只有显式加 `--force-overwrite` 才会替换并先备份。
- `shadowrocket-node.png` 适合直接给 `Shadowrocket` 扫码。
- `clashverge.yaml` 适合 `Clash Verge / Clash Mi / Karing` 导入。
