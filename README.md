# Xray VLESS Reality / sing-box Trojan TLS 一键安装

Debian / Ubuntu 一键安装 Xray VLESS Reality 或 sing-box Trojan TLS。

## 安装

**Reality（默认，无需域名）：**

自动选择 SNI：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y
```

手动指定 SNI：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y --sni www.nvidia.com
```

**Trojan TLS（需要域名，DNS 直接指向本机，关闭 CDN）：**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) -y \
  --protocol trojan --domain proxy.example.com --acme-email you@example.com
```

查看全部参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/install.sh) --help
```

## 生成文件

安装完成后导出到 `/root/vless-export/`：

| 文件 | 用途 |
|------|------|
| `<IP或域名>.yaml` | Clash Verge / Clash Mi / Karing 配置 |
| `shadowrocket-node.png` | Shadowrocket 扫码导入 |
| `node.vless.txt` / `node.trojan.txt` | 节点链接 |
| `shadowrocket.conf` | Shadowrocket 配置文件 |
| `subscription-url.txt`（Trojan） | Clash Verge 远程订阅地址 |

安装结束自动用 `sz` 下载 Clash YAML，不支持 ZMODEM 时加 `--skip-sz`。

## 说明

- **Reality** 使用 Xray，`--sni` 可选，不填自动从内置列表探测第一个可用的 TLS 1.3 站点
- **Trojan** 使用 sing-box，需要 `--domain`，自动申请 Let's Encrypt 证书并配置续签
- 已有配置默认保留，`--force-overwrite` 才覆盖（先备份）
- 默认启用 BBR + 32MB TCP 缓冲 + TCP Fast Open
- Xray / sing-box 以非特权用户运行，systemd 最小化能力
- 服务端默认阻断私网、链路本地、云元数据地址出站
