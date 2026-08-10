#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import ipaddress
import json
import re
import sys
import urllib.parse
from pathlib import Path

try:
    import qrcode
except ImportError:  # pragma: no cover - optional dependency
    qrcode = None


VERSION = "1.6.0"
DEFAULT_NODE_NAME = "vless-reality"
DEFAULT_TROJAN_NODE_NAME = "trojan-tls"
DEFAULT_FINGERPRINT = "chrome"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export a VLESS Reality or Trojan TLS link to client assets."
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--node-url",
        "--vless-url",
        dest="node_url",
        help="Full vless:// or trojan:// URL",
    )
    source.add_argument(
        "--node-url-file",
        type=Path,
        help="Read the node URL from a file instead of the process command line",
    )
    parser.add_argument(
        "--output-dir",
        default=".",
        help="Directory for generated files. Default: current directory",
    )
    parser.add_argument(
        "--mixed-port",
        type=int,
        default=7890,
        help="Mixed port written into the Clash YAML. Default: 7890",
    )
    parser.add_argument(
        "--controller",
        default="127.0.0.1:9090",
        help="external-controller value for the Clash YAML. Default: 127.0.0.1:9090",
    )
    parser.add_argument(
        "--skip-qr",
        action="store_true",
        help="Skip PNG QR generation even if qrcode is installed",
    )
    parser.add_argument("-V", "--version", action="version", version=VERSION)
    return parser.parse_args()


def parse_node_link(link: str) -> dict[str, str | int]:
    link = link.strip()
    scheme = urllib.parse.urlparse(link).scheme.lower()
    if scheme not in {"vless", "trojan"}:
        raise ValueError("Input is not a vless:// or trojan:// URL")

    default_name = DEFAULT_NODE_NAME if scheme == "vless" else DEFAULT_TROJAN_NODE_NAME
    if "#" in link:
        base, fragment = link.split("#", 1)
        name = urllib.parse.unquote(fragment) or default_name
    else:
        base = link
        name = default_name

    parsed = urllib.parse.urlparse(base)
    query = urllib.parse.parse_qs(parsed.query)

    def q1(key: str, default: str = "") -> str:
        return query.get(key, [default])[0]

    server = parsed.hostname or ""
    port = parsed.port or 0
    if not server or not port:
        raise ValueError("Missing server or port")
    sni = q1("sni", q1("servername", ""))
    if scheme == "vless":
        uuid = urllib.parse.unquote(parsed.username or "")
        network = q1("type", q1("network", "tcp")).lower()
        security = q1("security", "reality").lower()
        fingerprint = q1("fp", DEFAULT_FINGERPRINT)
        public_key = q1("pbk", q1("public-key", ""))
        short_id = q1("sid", q1("short-id", ""))
        flow = q1("flow", "xtls-rprx-vision")
        if not uuid or not sni or not public_key or not short_id:
            raise ValueError("The VLESS URL is missing required Reality fields")
        if network != "tcp" or security != "reality":
            raise ValueError("Only VLESS Reality over TCP is supported")
        return {
            "name": name,
            "protocol": "vless",
            "uuid": uuid,
            "server": server,
            "port": port,
            "network": network,
            "security": security,
            "sni": sni,
            "fingerprint": fingerprint,
            "public_key": public_key,
            "short_id": short_id,
            "flow": flow,
        }

    password = urllib.parse.unquote(parsed.username or "")
    if not password or not sni:
        raise ValueError("The Trojan URL is missing password or sni")
    return {
        "name": name,
        "protocol": "trojan",
        "password": password,
        "server": server,
        "port": port,
        "sni": sni,
        "fingerprint": q1("fp", DEFAULT_FINGERPRINT),
    }


def build_node_url(node: dict[str, str | int]) -> str:
    if node["protocol"] == "vless":
        scheme = "vless"
        userinfo = str(node["uuid"])
        query_values = {
            "encryption": "none",
            "type": node["network"],
            "security": node["security"],
            "sni": node["sni"],
            "fp": node["fingerprint"],
            "flow": node["flow"],
            "pbk": node["public_key"],
            "sid": node["short_id"],
        }
    else:
        scheme = "trojan"
        userinfo = urllib.parse.quote(str(node["password"]), safe="")
        query_values = {
            "security": "tls",
            "sni": node["sni"],
            "type": "tcp",
            "fp": node["fingerprint"],
        }
    query = urllib.parse.urlencode(query_values)
    fragment = urllib.parse.quote(str(node["name"]), safe="")
    server = str(node["server"])
    try:
        address = ipaddress.ip_address(server)
    except ValueError:
        url_server = server
    else:
        url_server = f"[{server}]" if address.version == 6 else server
    return (
        f"{scheme}://{userinfo}@{url_server}:{node['port']}?{query}#{fragment}"
    )


def build_clash_server_direct_rule(server: str) -> str:
    try:
        address = ipaddress.ip_address(server)
    except ValueError:
        return f"  - DOMAIN,{server},DIRECT"
    if address.version == 6:
        return f"  - IP-CIDR6,{server}/128,DIRECT,no-resolve"
    return f"  - IP-CIDR,{server}/32,DIRECT,no-resolve"


def build_clash_route_exclude(server: str) -> str:
    try:
        address = ipaddress.ip_address(server)
    except ValueError:
        return ""
    prefix = 128 if address.version == 6 else 32
    return f"  route-exclude-address:\n    - {server}/{prefix}\n"


def build_clashverge_yaml(node: dict[str, str | int], mixed_port: int, controller: str) -> str:
    name = str(node["name"])
    server_direct_rule = build_clash_server_direct_rule(str(node["server"]))
    route_exclude_block = build_clash_route_exclude(str(node["server"]))
    if node["protocol"] == "vless":
        proxy = f'''    type: vless
    server: "{node["server"]}"
    port: {node["port"]}
    uuid: {node["uuid"]}
    network: tcp
    tls: true
    udp: true
    servername: "{node["sni"]}"
    client-fingerprint: "{node["fingerprint"]}"
    flow: "{node["flow"]}"
    reality-opts:
      public-key: "{node["public_key"]}"
      short-id: "{node["short_id"]}"'''
    else:
        proxy = f'''    type: trojan
    server: "{node["server"]}"
    port: {node["port"]}
    password: "{node["password"]}"
    sni: "{node["sni"]}"
    client-fingerprint: "{node["fingerprint"]}"
    tls: true
    udp: true
    alpn:
      - http/1.1
    skip-cert-verify: false'''
    return f"""# Generated by vless_export_assets.py
mixed-port: {mixed_port}
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: info
ipv6: true
external-controller: {controller}
unified-delay: true

tun:
  enable: true
  stack: gvisor
  dns-hijack:
    - any:53
    - tcp://any:53
  auto-route: true
  auto-detect-interface: true
{route_exclude_block}  strict-route: true

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: true
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - '*.localdomain'
    - localhost
    - time.*.com
    - ntp.*.com
    - '+.pool.ntp.org'
    - '+.msftconnecttest.com'
    - '+.msftncsi.com'
    - 'stun.*.*'
    - '+.stun.*.*'
    - 'xbox.*.microsoft.com'
    - '+.srv.nintendo.net'
    - '+.stun.playstation.net'

  nameserver:
    - https://223.5.5.5/dns-query
    - https://doh.pub/dns-query
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query

rule-providers:
  proxy:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt"
    path: ./ruleset/proxy.yaml
    interval: 86400

  direct:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt"
    path: ./ruleset/direct.yaml
    interval: 86400

proxies:
  - name: "{name}"
{proxy}

proxy-groups:
  - name: "节点选择"
    type: select
    proxies:
      - "{name}"
      - DIRECT
  - name: "AI"
    type: select
    proxies:
      - "节点选择"
      - "{name}"
      - DIRECT
  - name: "Telegram"
    type: select
    proxies:
      - "节点选择"
      - "{name}"
  - name: "Streaming"
    type: select
    proxies:
      - "节点选择"
      - "{name}"
      - DIRECT

rules:
{server_direct_rule}
  - DOMAIN-SUFFIX,freemodel.dev,DIRECT
  - DOMAIN-SUFFIX,local,DIRECT
  - DOMAIN-SUFFIX,localhost,DIRECT
  - DOMAIN-SUFFIX,lan,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,169.254.0.0/16,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,224.0.0.0/4,DIRECT,no-resolve
  - IP-CIDR6,::1/128,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve
  - DOMAIN-SUFFIX,api.openai.com,AI
  - DOMAIN-SUFFIX,auth0.openai.com,AI
  - DOMAIN-SUFFIX,auth.openai.com,AI
  - DOMAIN-SUFFIX,openai.com,AI
  - DOMAIN-SUFFIX,openaiapi-site.azureedge.net,AI
  - DOMAIN-SUFFIX,openaicom-api-bdcpf8c6d2e9atf6.z01.azurefd.net,AI
  - DOMAIN-SUFFIX,openaicomproductionae4b.blob.core.windows.net,AI
  - DOMAIN-SUFFIX,production-openaicom-storage.azureedge.net,AI
  - DOMAIN-SUFFIX,openai.com.cdn.cloudflare.net,AI
  - DOMAIN-SUFFIX,openaicom.imgix.net,AI
  - DOMAIN-KEYWORD,openaicom-api,AI
  - DOMAIN-SUFFIX,chatgpt.com,AI
  - DOMAIN-SUFFIX,chat.com,AI
  - DOMAIN-SUFFIX,oaistatic.com,AI
  - DOMAIN-SUFFIX,oaiusercontent.com,AI
  - DOMAIN-SUFFIX,sora.com,AI
  - DOMAIN-SUFFIX,openai-api.arkoselabs.com,AI
  - DOMAIN-SUFFIX,client-api.arkoselabs.com,AI
  - DOMAIN-SUFFIX,chatgpt.livekit.cloud,AI
  - DOMAIN-SUFFIX,host.livekit.cloud,AI
  - DOMAIN-SUFFIX,turn.livekit.cloud,AI
  - DOMAIN-SUFFIX,challenges.cloudflare.com,AI
  - DOMAIN-SUFFIX,identrust.com,AI
  - DOMAIN-SUFFIX,status.openai.com,AI
  - DOMAIN-SUFFIX,browser-intake-datadoghq.com,AI
  - DOMAIN-SUFFIX,o33249.ingest.sentry.io,AI
  - DOMAIN-SUFFIX,gemini.google.com,AI
  - DOMAIN-SUFFIX,gemini.google,AI
  - DOMAIN-SUFFIX,generativeai.google,AI
  - DOMAIN-SUFFIX,generativelanguage.googleapis.com,AI
  - DOMAIN-SUFFIX,aistudio.google.com,AI
  - DOMAIN-SUFFIX,notebooklm.google.com,AI
  - DOMAIN-SUFFIX,copilot.microsoft.com,AI
  - DOMAIN-SUFFIX,githubcopilot.com,AI
  - DOMAIN-SUFFIX,telegram.org,Telegram
  - DOMAIN-SUFFIX,t.me,Telegram
  - DOMAIN-SUFFIX,telegram.me,Telegram
  - DOMAIN-SUFFIX,tdesktop.com,Telegram
  - GEOIP,telegram,Telegram,no-resolve
  - DOMAIN-SUFFIX,netflix.com,Streaming
  - DOMAIN-SUFFIX,netflix.net,Streaming
  - DOMAIN-SUFFIX,nflxvideo.net,Streaming
  - DOMAIN-SUFFIX,nflximg.net,Streaming
  - DOMAIN-SUFFIX,youtube.com,Streaming
  - DOMAIN-SUFFIX,googlevideo.com,Streaming
  - DOMAIN-SUFFIX,ytimg.com,Streaming
  - RULE-SET,proxy,节点选择
  - RULE-SET,direct,DIRECT
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
"""


def build_shadowrocket_conf(node: dict[str, str | int]) -> str:
    name = str(node["name"])
    if node["protocol"] == "vless":
        proxy = f"{name} = vless, {node['server']}, {node['port']}, username={node['uuid']}, tls=true, sni={node['sni']}, xtls=1, public-key={node['public_key']}, short-id={node['short_id']}, flow={node['flow']}, fingerprint={node['fingerprint']}"
    else:
        proxy = f"{name} = trojan, {node['server']}, {node['port']}, password={node['password']}, sni={node['sni']}, tls=true, skip-cert-verify=false, udp-relay=true, fingerprint={node['fingerprint']}"
    return f"""[General]
bypass-system = true
skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, localhost, *.local
bypass-tun = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4
dns-server = 223.5.5.5, 119.29.29.29, 1.1.1.1, 8.8.8.8
ipv6 = true

[Proxy]
{proxy}

[Proxy Group]
PROXY = select, {name}, DIRECT

[Rule]
FINAL,PROXY
"""


def slugify(value: str) -> str:
    cleaned = re.sub(r"[^\w.-]+", "_", value.strip(), flags=re.ASCII)
    return cleaned or "node"


def clash_filename(node: dict[str, str | int]) -> str:
    return f"{slugify(str(node['server']))}.yaml"


def write_qr_png(data: str, target: Path) -> None:
    if qrcode is None:
        return
    image = qrcode.make(data)
    image.save(target)


def main() -> int:
    args = parse_args()
    node_url = (
        args.node_url_file.read_text(encoding="utf-8")
        if args.node_url_file
        else args.node_url
    )
    node = parse_node_link(node_url)
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    normalized_link = build_node_url(node)
    clash = build_clashverge_yaml(node, args.mixed_port, args.controller)
    shadowrocket = build_shadowrocket_conf(node)
    named_clash = clash_filename(node)
    node_link_filename = f"node.{node['protocol']}.txt"
    metadata = dict(node)
    metadata["clash_yaml"] = named_clash
    metadata["node_link"] = node_link_filename

    files = {
        node_link_filename: normalized_link,
        named_clash: clash,
        "shadowrocket.conf": shadowrocket,
        "metadata.json": json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
    }

    for filename, content in files.items():
        (output_dir / filename).write_text(content, encoding="utf-8")

    if not args.skip_qr and qrcode is not None:
        write_qr_png(normalized_link, output_dir / "shadowrocket-node.png")

    print(f"Generated assets in: {output_dir}")
    print(f"  - {output_dir / node_link_filename}")
    print(f"  - {output_dir / named_clash}")
    print(f"  - {output_dir / 'shadowrocket.conf'}")
    print(f"  - {output_dir / 'metadata.json'}")
    if not args.skip_qr and qrcode is not None:
        print(f"  - {output_dir / 'shadowrocket-node.png'}")
    elif not args.skip_qr:
        print("Skipped QR generation because the qrcode package is not installed.")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - CLI guard
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
