#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="install.sh"
SCRIPT_VERSION="1.1.0"
XRAY_INSTALLER_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

PORT=""
SNI=""
DEST_HOST=""
DEST_PORT="443"
NODE_NAME=""
CLIENT_FINGERPRINT="chrome"
ARTIFACT_DIR="/root/vless-export"
PUBLIC_IP=""
PUBLIC_IP_FAMILY=""

ASSUME_YES="0"
FORCE_OVERWRITE="0"
SKIP_FIREWALL="0"
SKIP_PACKAGES="0"
SKIP_QR="0"

OS_ID=""
OS_VERSION_ID=""
CONFIG_FILE="/usr/local/etc/xray/config.json"
CONFIG_BACKUP_FILE=""
CONFIG_WAS_BACKED_UP="0"
XRAY_BIN=""
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
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

One-command installer for Xray VLESS + Reality with local export assets.

Usage:
  bash ${SCRIPT_NAME} [options]

Options:
  --port PORT               Listen port for VLESS Reality. Default: random 20000-40000
  --sni HOST                SNI and Reality serverNames. Default: random common China HTTPS domain
  --dest-host HOST          Reality dest host. Default: same as --sni
  --dest-port PORT          Reality dest port. Default: ${DEST_PORT}
  --node-name NAME          Exported node name. Default: server hostname
  --fingerprint VALUE       Client fingerprint for exports. Default: ${CLIENT_FINGERPRINT}
  --artifact-dir PATH       Directory for generated files. Default: ${ARTIFACT_DIR}
  --public-ip IP            Override auto-detected public IP
  --force-overwrite         Replace an existing Xray config after creating a timestamped backup
  --skip-firewall           Do not change UFW rules
  --skip-packages           Skip apt package installation
  --skip-qr                 Do not generate Shadowrocket QR PNG
  -y, --yes                 Run non-interactively
  -V, --version             Show script version
  -h, --help                Show this help

Examples:
  bash ${SCRIPT_NAME} -y
  bash ${SCRIPT_NAME} -y --node-name my-vps --force-overwrite

GitHub Raw example:
  bash <(curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/${SCRIPT_NAME}) -y
EOF
}

log() {
  printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"
}

warn() {
  printf '\n[WARN] %s\n' "$*" >&2
}

die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

cleanup_on_error() {
  local exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    return
  fi

  warn "Installer exited with code ${exit_code}."
  if [[ "${CONFIG_WAS_BACKED_UP}" == "1" && -f "${CONFIG_BACKUP_FILE}" ]]; then
    warn "Existing Xray config was backed up to: ${CONFIG_BACKUP_FILE}"
    warn "If needed, restore it manually with:"
    warn "  cp '${CONFIG_BACKUP_FILE}' '${CONFIG_FILE}' && systemctl restart xray"
  fi
}

trap cleanup_on_error EXIT

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run this script as root."
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
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
      --force-overwrite)
        FORCE_OVERWRITE="1"
        shift
        ;;
      --skip-firewall)
        SKIP_FIREWALL="1"
        shift
        ;;
      --skip-packages)
        SKIP_PACKAGES="1"
        shift
        ;;
      --skip-qr)
        SKIP_QR="1"
        shift
        ;;
      -y|--yes)
        ASSUME_YES="1"
        shift
        ;;
      -V|--version)
        printf '%s\n' "${SCRIPT_VERSION}"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage
        die "Unknown option: $1"
        ;;
    esac
  done
}

detect_os() {
  [[ -r /etc/os-release ]] || die "This installer expects /etc/os-release."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_VERSION_ID="${VERSION_ID:-}"

  case "${OS_ID}" in
    debian|ubuntu)
      ;;
    *)
      die "Unsupported OS: ${OS_ID:-unknown}. This installer currently supports Debian and Ubuntu."
      ;;
  esac
}

validate_args() {
  [[ "${SNI}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid --sni value: ${SNI}"
  [[ -z "${DEST_HOST}" || "${DEST_HOST}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid --dest-host value: ${DEST_HOST}"
  [[ "${CLIENT_FINGERPRINT}" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid --fingerprint value: ${CLIENT_FINGERPRINT}"

  if [[ -n "${PORT}" ]]; then
    [[ "${PORT}" =~ ^[0-9]+$ ]] || die "--port must be a number"
    (( PORT >= 1 && PORT <= 65535 )) || die "--port must be between 1 and 65535"
  fi

  [[ "${DEST_PORT}" =~ ^[0-9]+$ ]] || die "--dest-port must be a number"
  (( DEST_PORT >= 1 && DEST_PORT <= 65535 )) || die "--dest-port must be between 1 and 65535"
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

confirm_plan() {
  log "Release-ready installer summary"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
OS             : ${OS_ID} ${OS_VERSION_ID}
Listen port    : ${PORT}
SNI            : ${SNI}
Reality dest   : ${DEST_HOST}:${DEST_PORT}
Node name      : ${NODE_NAME}
Fingerprint    : ${CLIENT_FINGERPRINT}
Artifact dir   : ${ARTIFACT_DIR}
Skip firewall  : ${SKIP_FIREWALL}
Skip packages  : ${SKIP_PACKAGES}
Skip QR        : ${SKIP_QR}
EOF

  if [[ -f "${CONFIG_FILE}" && "${FORCE_OVERWRITE}" != "1" ]]; then
    die "Existing Xray config found at ${CONFIG_FILE}. Re-run with --force-overwrite if you really want to replace it."
  fi

  if [[ "${ASSUME_YES}" == "1" ]]; then
    return
  fi

  if [[ -t 0 ]]; then
    printf '\nContinue installation? [y/N]: '
    read -r answer
    case "${answer}" in
      y|Y|yes|YES)
        ;;
      *)
        die "Cancelled by user."
        ;;
    esac
  else
    die "Non-interactive shell detected. Re-run with -y or --yes."
  fi
}

install_dependencies() {
  if [[ "${SKIP_PACKAGES}" == "1" ]]; then
    log "Skipping apt package installation by request"
    return
  fi

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

ensure_required_commands() {
  local required=(curl openssl python3 shuf awk sed)
  local missing=()
  local cmd
  for cmd in "${required[@]}"; do
    if ! command_exists "${cmd}"; then
      missing+=("${cmd}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

install_xray() {
  if command_exists xray; then
    XRAY_BIN="$(command -v xray)"
    log "Xray already installed at ${XRAY_BIN}"
    return
  fi

  log "Installing Xray via the official installer"
  bash -c "$(curl -fsSL "${XRAY_INSTALLER_URL}")" @ install -u root

  XRAY_BIN="$(command -v xray || true)"
  [[ -n "${XRAY_BIN}" ]] || XRAY_BIN="/usr/local/bin/xray"
  [[ -x "${XRAY_BIN}" ]] || die "Xray installation completed but xray binary was not found."
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
      [[ -n "${PUBLIC_IP}" ]] || die "Unable to detect public IP. Re-run with --public-ip."
      PUBLIC_IP_FAMILY="ipv6"
    fi
  fi

  if has_ipv6_stack; then
    XRAY_LISTEN="::"
  else
    XRAY_LISTEN="0.0.0.0"
  fi

  if [[ "${PUBLIC_IP_FAMILY}" == "ipv6" ]] && [[ "${XRAY_LISTEN}" != "::" ]]; then
    die "Detected an IPv6-only public endpoint but the system IPv6 stack is unavailable."
  fi

  log "Detected public endpoint: ${PUBLIC_IP_FAMILY} ${PUBLIC_IP}"
}

generate_reality_material() {
  log "Generating VLESS Reality credentials"
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SHORT_ID="$(openssl rand -hex 8)"
  local x25519_output
  x25519_output="$("${XRAY_BIN}" x25519)"
  PRIVATE_KEY="$(awk -F': ' '/Private key/ {print $2}' <<<"${x25519_output}")"
  PUBLIC_KEY="$(awk -F': ' '/Public key/ {print $2}' <<<"${x25519_output}")"

  [[ -n "${PRIVATE_KEY}" && -n "${PUBLIC_KEY}" ]] || die "Failed to generate Reality keys."
}

backup_existing_config() {
  local config_dir
  config_dir="$(dirname "${CONFIG_FILE}")"
  mkdir -p "${config_dir}"

  if [[ -f "${CONFIG_FILE}" ]]; then
    CONFIG_BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "${CONFIG_FILE}" "${CONFIG_BACKUP_FILE}"
    CONFIG_WAS_BACKED_UP="1"
    log "Existing Xray config backed up to ${CONFIG_BACKUP_FILE}"
  fi
}

write_xray_config() {
  backup_existing_config

  log "Writing Xray Reality config"
  cat > "${CONFIG_FILE}" <<EOF
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

  "${XRAY_BIN}" run -test -config "${CONFIG_FILE}" >/dev/null
  systemctl enable xray
  systemctl restart xray
  systemctl is-active --quiet xray || die "Xray failed to start."
}

configure_firewall() {
  if [[ "${SKIP_FIREWALL}" == "1" ]]; then
    log "Skipping firewall changes by request"
    return
  fi

  if ! command_exists ufw; then
    warn "ufw is not installed. Skipping firewall configuration."
    return
  fi

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
import sys
import urllib.parse
from pathlib import Path

VERSION = "1.1.0"
DEFAULT_NODE_NAME = "vless-reality"
DEFAULT_FINGERPRINT = "chrome"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vless-url", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--mixed-port", type=int, default=7890)
    parser.add_argument("--controller", default="127.0.0.1:9090")
    parser.add_argument("-V", "--version", action="version", version=VERSION)
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
    return f"""# Generated by install.sh
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

  if [[ "${SKIP_QR}" != "1" ]] && command_exists qrencode; then
    qrencode -o "${ARTIFACT_DIR}/shadowrocket-node.png" "${VLESS_URL}"
  fi

  cat > "${ARTIFACT_DIR}/README.txt" <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

VLESS Reality is ready.

Server endpoint: ${PUBLIC_IP}
Endpoint family: ${PUBLIC_IP_FAMILY}
Port: ${PORT}
Node name: ${NODE_NAME}
SNI: ${SNI}
Reality dest: ${DEST_HOST}:${DEST_PORT}
Public key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}

Generated files:
  ${ARTIFACT_DIR}/node.vless.txt
  ${ARTIFACT_DIR}/clashverge.yaml
  ${ARTIFACT_DIR}/shadowrocket.conf
  ${ARTIFACT_DIR}/metadata.json
EOF

  if [[ "${SKIP_QR}" != "1" ]] && [[ -f "${ARTIFACT_DIR}/shadowrocket-node.png" ]]; then
    cat >> "${ARTIFACT_DIR}/README.txt" <<EOF
  ${ARTIFACT_DIR}/shadowrocket-node.png
EOF
  fi

  cat >> "${ARTIFACT_DIR}/README.txt" <<EOF

Download with sz:
  sz ${ARTIFACT_DIR}/node.vless.txt
  sz ${ARTIFACT_DIR}/clashverge.yaml
  sz ${ARTIFACT_DIR}/shadowrocket.conf
  sz ${ARTIFACT_DIR}/metadata.json
  sz ${ARTIFACT_DIR}/*

Notes:
  - sz requires a ZMODEM-capable terminal such as Xshell, SecureCRT, or MobaXterm.
  - shadowrocket-node.png is a VLESS QR code for direct Shadowrocket scanning.
  - clashverge.yaml is intended for Clash Verge, Clash Mi, or Karing.
EOF
}

print_summary() {
  log "Installation complete"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
Xray service   : $(systemctl is-active xray)
Config file    : ${CONFIG_FILE}
Artifact dir   : ${ARTIFACT_DIR}

VLESS URL:
${VLESS_URL}

Quick download:
  sz ${ARTIFACT_DIR}/*
EOF

  if [[ "${SKIP_QR}" != "1" ]] && [[ -f "${ARTIFACT_DIR}/shadowrocket-node.png" ]]; then
    printf 'Shadowrocket QR: %s\n' "${ARTIFACT_DIR}/shadowrocket-node.png"
  fi
}

main() {
  parse_args "$@"
  need_root
  detect_os
  validate_args
  ensure_defaults
  confirm_plan
  install_dependencies
  ensure_required_commands
  install_xray
  detect_public_ip
  generate_reality_material
  write_xray_config
  configure_firewall
  generate_assets
  print_summary
}

main "$@"
