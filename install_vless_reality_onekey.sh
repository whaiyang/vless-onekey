#!/usr/bin/env bash
set -euo pipefail

PORT=""
SNI=""
DEST_HOST=""
DEST_PORT="443"
NODE_NAME=""
CLIENT_FINGERPRINT="chrome"
ARTIFACT_DIR="/root/vless-export"
PUBLIC_IP=""
PUBLIC_IP_FAMILY=""
XRAY_LISTEN="0.0.0.0"
DEFAULT_SNI_POOL=(
  "www.qq.com"
  "www.taobao.com"
  "www.jd.com"
  "www.bilibili.com"
  "www.zhihu.com"
  "www.sina.com.cn"
  "www.163.com"
  "www.douban.com"
)

usage() {
  cat <<'EOF'
Usage:
  bash install_vless_reality_onekey.sh [options]

Options:
  --port PORT               Listen port for VLESS Reality. Default: random 20000-40000
  --sni HOST                SNI and serverNames value. Default: random common China HTTPS domain
  --dest-host HOST          Reality dest host. Default: same as --sni
  --dest-port PORT          Reality dest port. Default: 443
  --node-name NAME          Exported node name. Default: server hostname
  --fingerprint VALUE       Client fingerprint for exported configs. Default: chrome
  --artifact-dir PATH       Directory for generated files. Default: /root/vless-export
  --public-ip IP            Override detected public IP
  -h, --help                Show this help

Example:
  bash install_vless_reality_onekey.sh
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

has_ipv6_stack() {
  [[ -s /proc/net/if_inet6 ]]
}

detect_ip_family() {
  local value="$1"
  if [[ "${value}" == *:* ]]; then
    printf 'ipv6\n'
  else
    printf 'ipv4\n'
  fi
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run this script as root." >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        PORT="${2:-}"
        shift 2
        ;;
      --sni)
        SNI="${2:-}"
        shift 2
        ;;
      --dest-host)
        DEST_HOST="${2:-}"
        shift 2
        ;;
      --dest-port)
        DEST_PORT="${2:-}"
        shift 2
        ;;
      --node-name)
        NODE_NAME="${2:-}"
        shift 2
        ;;
      --fingerprint)
        CLIENT_FINGERPRINT="${2:-}"
        shift 2
        ;;
      --artifact-dir)
        ARTIFACT_DIR="${2:-}"
        shift 2
        ;;
      --public-ip)
        PUBLIC_IP="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

ensure_defaults() {
  if [[ -z "${PORT}" ]]; then
    PORT="$(shuf -i 20000-40000 -n 1)"
  fi
  if [[ -z "${SNI}" ]]; then
    local index
    index="$(shuf -i 0-$((${#DEFAULT_SNI_POOL[@]} - 1)) -n 1)"
    SNI="${DEFAULT_SNI_POOL[${index}]}"
  fi
  if [[ -z "${DEST_HOST}" ]]; then
    DEST_HOST="${SNI}"
  fi
  if [[ -z "${NODE_NAME}" ]]; then
    NODE_NAME="$(hostname)"
  fi
}

install_dependencies() {
  log "Installing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates \
    curl \
    lrzsz \
    openssl \
    python3 \
    qrencode \
    ufw \
    unzip \
    uuid-runtime
}

install_xray() {
  if command -v xray >/dev/null 2>&1; then
    log "Xray is already installed"
    return
  fi

  log "Installing Xray via the official installer"
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
}

detect_public_ip() {
  if [[ -n "${PUBLIC_IP}" ]]; then
    PUBLIC_IP_FAMILY="$(detect_ip_family "${PUBLIC_IP}")"
  else
    PUBLIC_IP="$(
      curl -4fsSL https://api64.ipify.org 2>/dev/null ||
      curl -4fsSL https://ifconfig.me 2>/dev/null ||
      ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
    )"

    if [[ -n "${PUBLIC_IP}" ]]; then
      PUBLIC_IP_FAMILY="ipv4"
    else
      PUBLIC_IP="$(
        curl -6fsSL https://api64.ipify.org 2>/dev/null ||
        curl -6fsSL https://ifconfig.me 2>/dev/null ||
        ip -6 route get 2606:4700:4700::1111 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}'
      )"
      if [[ -z "${PUBLIC_IP}" ]]; then
        echo "Unable to detect public IP. Re-run with --public-ip." >&2
        exit 1
      fi
      PUBLIC_IP_FAMILY="ipv6"
    fi
  fi

  if has_ipv6_stack; then
    XRAY_LISTEN="::"
  else
    XRAY_LISTEN="0.0.0.0"
  fi
}

generate_reality_material() {
  log "Generating VLESS Reality credentials"
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SHORT_ID="$(openssl rand -hex 8)"
  XRAY_BIN="$(command -v xray || true)"
  if [[ -z "${XRAY_BIN}" ]]; then
    XRAY_BIN="/usr/local/bin/xray"
  fi

  X25519_OUTPUT="$("${XRAY_BIN}" x25519)"
  PRIVATE_KEY="$(awk -F': ' '/Private key/ {print $2}' <<<"${X25519_OUTPUT}")"
  PUBLIC_KEY="$(awk -F': ' '/Public key/ {print $2}' <<<"${X25519_OUTPUT}")"

  if [[ -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" ]]; then
    echo "Failed to generate Reality keys." >&2
    exit 1
  fi
}

write_xray_config() {
  local config_dir="/usr/local/etc/xray"
  local config_file="${config_dir}/config.json"
  local backup_file=""

  mkdir -p "${config_dir}"
  if [[ -f "${config_file}" ]]; then
    backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${config_file}" "${backup_file}"
    log "Existing Xray config backed up to ${backup_file}"
  fi

  log "Writing Xray Reality config"
  cat > "${config_file}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "${XRAY_LISTEN}",
      "port": ${PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST_HOST}:${DEST_PORT}",
          "xver": 0,
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

  systemctl enable xray
  systemctl restart xray
  systemctl is-active --quiet xray
}

configure_firewall() {
  log "Opening firewall ports"
  ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
}

write_export_tool() {
  mkdir -p "${ARTIFACT_DIR}"
  cat > "${ARTIFACT_DIR}/vless_export_assets.py" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ipaddress
import json
import re
import sys
import urllib.parse
from pathlib import Path


DEFAULT_NODE_NAME = "vless-reality"
DEFAULT_FINGERPRINT = "chrome"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vless-url", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--mixed-port", type=int, default=7890)
    parser.add_argument("--controller", default="127.0.0.1:9090")
    return parser.parse_args()


def parse_vless_link(link: str) -> dict[str, str | int]:
    link = link.strip()
    if not link.lower().startswith("vless://"):
        raise ValueError("Input is not a vless:// URL")

    if "#" in link:
        base, fragment = link.split("#", 1)
        name = urllib.parse.unquote(fragment) or DEFAULT_NODE_NAME
    else:
        base = link
        name = DEFAULT_NODE_NAME

    parsed = urllib.parse.urlparse(base)
    query = urllib.parse.parse_qs(parsed.query)

    def q1(key: str, default: str = "") -> str:
        return query.get(key, [default])[0]

    uuid = parsed.username or ""
    server = parsed.hostname or ""
    port = parsed.port or 0
    sni = q1("sni", q1("servername", ""))
    fingerprint = q1("fp", DEFAULT_FINGERPRINT)
    public_key = q1("pbk", q1("public-key", ""))
    short_id = q1("sid", q1("short-id", ""))
    flow = q1("flow", "xtls-rprx-vision")

    if not uuid or not server or not port or not sni or not public_key or not short_id:
        raise ValueError("The VLESS URL is missing required Reality fields")

    return {
        "name": name,
        "uuid": uuid,
        "server": server,
        "port": port,
        "sni": sni,
        "fingerprint": fingerprint,
        "public_key": public_key,
        "short_id": short_id,
        "flow": flow,
    }


def format_url_host(server: str) -> str:
    try:
        address = ipaddress.ip_address(server)
    except ValueError:
        return server
    if address.version == 6:
        return f"[{server}]"
    return server


def build_clashverge_yaml(node: dict[str, str | int], mixed_port: int, controller: str) -> str:
    name = str(node["name"])
    return f"""# Generated by install_vless_reality_onekey.sh
mixed-port: {mixed_port}
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
ipv6: true
external-controller: {controller}
unified-delay: true

tun:
  enable: true
  stack: system
  dns-hijack:
    - any:53
  auto-route: true
  auto-detect-interface: true

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16

  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - https://223.5.5.5/dns-query

rule-providers:
  reject:
    type: http
    behavior: domain
    url: "https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt"
    path: ./ruleset/reject.yaml
    interval: 86400

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
    type: vless
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
      short-id: "{node["short_id"]}"

proxy-groups:
  - name: "节点选择"
    type: select
    proxies:
      - "{name}"
      - DIRECT

rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - DOMAIN-SUFFIX,localhost,DIRECT
  - DOMAIN-SUFFIX,lan,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - RULE-SET,proxy,节点选择
  - RULE-SET,direct,DIRECT
  - GEOIP,LAN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,节点选择
"""


def build_shadowrocket_conf(node: dict[str, str | int]) -> str:
    name = str(node["name"])
    return f"""[General]
bypass-system = true
skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, localhost, *.local
bypass-tun = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4
dns-server = 223.5.5.5, 119.29.29.29, 1.1.1.1, 8.8.8.8
ipv6 = true

[Proxy]
{name} = vless, {node["server"]}, {node["port"]}, username={node["uuid"]}, tls=true, sni={node["sni"]}, xtls=1, public-key={node["public_key"]}, short-id={node["short_id"]}, flow={node["flow"]}, fingerprint={node["fingerprint"]}

[Proxy Group]
PROXY = select, {name}, DIRECT

[Rule]
FINAL,PROXY
"""


def main() -> int:
    args = parse_args()
    node = parse_vless_link(args.vless_url)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    (output_dir / "node.vless.txt").write_text(args.vless_url + "\n", encoding="utf-8")
    (output_dir / "clashverge.yaml").write_text(
        build_clashverge_yaml(node, args.mixed_port, args.controller), encoding="utf-8"
    )
    (output_dir / "shadowrocket.conf").write_text(
        build_shadowrocket_conf(node), encoding="utf-8"
    )
    (output_dir / "metadata.json").write_text(
        json.dumps(node, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
PY
  chmod +x "${ARTIFACT_DIR}/vless_export_assets.py"
}

build_vless_url() {
  VLESS_URL="$(
    UUID="${UUID}" \
    SERVER="${PUBLIC_IP}" \
    PORT="${PORT}" \
    SNI="${SNI}" \
    FINGERPRINT="${CLIENT_FINGERPRINT}" \
    FLOW="xtls-rprx-vision" \
    PBK="${PUBLIC_KEY}" \
    SID="${SHORT_ID}" \
    NODE_NAME="${NODE_NAME}" \
    python3 - <<'PY'
import ipaddress
import os
import urllib.parse

server = os.environ["SERVER"]
try:
    address = ipaddress.ip_address(server)
except ValueError:
    url_server = server
else:
    url_server = f"[{server}]" if address.version == 6 else server

params = {
    "encryption": "none",
    "type": "tcp",
    "security": "reality",
    "sni": os.environ["SNI"],
    "fp": os.environ["FINGERPRINT"],
    "flow": os.environ["FLOW"],
    "pbk": os.environ["PBK"],
    "sid": os.environ["SID"],
}
query = urllib.parse.urlencode(params)
fragment = urllib.parse.quote(os.environ["NODE_NAME"], safe="")
print(
    f"vless://{os.environ['UUID']}@{url_server}:{os.environ['PORT']}?{query}#{fragment}"
)
PY
  )"
}

generate_assets() {
  log "Generating export files"
  mkdir -p "${ARTIFACT_DIR}"
  build_vless_url
  write_export_tool
  python3 "${ARTIFACT_DIR}/vless_export_assets.py" \
    --vless-url "${VLESS_URL}" \
    --output-dir "${ARTIFACT_DIR}"

  printf '%s\n' "${VLESS_URL}" > "${ARTIFACT_DIR}/node.vless.txt"
  qrencode -o "${ARTIFACT_DIR}/shadowrocket-node.png" "${VLESS_URL}"

  cat > "${ARTIFACT_DIR}/README.txt" <<EOF
VLESS Reality is ready.

Server endpoint: ${PUBLIC_IP}
Endpoint family: ${PUBLIC_IP_FAMILY}
Port: ${PORT}
Node name: ${NODE_NAME}
SNI: ${SNI}
Public key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}

Generated files:
  ${ARTIFACT_DIR}/node.vless.txt
  ${ARTIFACT_DIR}/clashverge.yaml
  ${ARTIFACT_DIR}/shadowrocket.conf
  ${ARTIFACT_DIR}/shadowrocket-node.png
  ${ARTIFACT_DIR}/metadata.json

Download with sz:
  sz ${ARTIFACT_DIR}/node.vless.txt
  sz ${ARTIFACT_DIR}/clashverge.yaml
  sz ${ARTIFACT_DIR}/shadowrocket.conf
  sz ${ARTIFACT_DIR}/shadowrocket-node.png
  sz ${ARTIFACT_DIR}/*

Notes:
  - sz requires a terminal that supports ZMODEM, such as Xshell, SecureCRT, or MobaXterm.
  - shadowrocket-node.png is a VLESS QR code that Shadowrocket can scan directly.
EOF
}

print_summary() {
  log "Installation complete"
  cat <<EOF
Xray service: $(systemctl is-active xray)
VLESS URL:
${VLESS_URL}

Files saved in:
  ${ARTIFACT_DIR}

Quick download:
  sz ${ARTIFACT_DIR}/*
EOF
}

main() {
  need_root
  parse_args "$@"
  ensure_defaults
  install_dependencies
  install_xray
  detect_public_ip
  generate_reality_material
  write_xray_config
  configure_firewall
  generate_assets
  print_summary
}

main "$@"
