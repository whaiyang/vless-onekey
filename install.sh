#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_NAME="install.sh"
SCRIPT_VERSION="1.6.0"
XRAY_INSTALLER_COMMIT="e741a4f56d368afbb9e5be3361b40c4552d3710d"
XRAY_INSTALLER_URL="https://raw.githubusercontent.com/XTLS/Xray-install/${XRAY_INSTALLER_COMMIT}/install-release.sh"
XRAY_AUTO_UPDATE_SCRIPT="/usr/local/sbin/xray-auto-update.sh"
XRAY_AUTO_UPDATE_SERVICE="/etc/systemd/system/xray-auto-update.service"
XRAY_AUTO_UPDATE_TIMER="/etc/systemd/system/xray-auto-update.timer"
XRAY_HARDENING_DROP_IN="/etc/systemd/system/xray.service.d/20-vless-onekey-hardening.conf"

PROTOCOL="reality"
PORT="443"
SNI=""
DEST_HOST=""
DEST_PORT="443"
DOMAIN=""
ACME_EMAIL=""
TROJAN_FALLBACK_PORT="8080"
SING_BOX_VERSION="1.13.18"
SING_BOX_SHA256_AMD64="d34d987ed6ae39ca3760269264fb502b867e5477db45518c829b07776245c495"
SING_BOX_SHA256_ARM64="a894f6152cade4a2c9d062762d54dea0c1aee673ab4759e0829e19cace932719"
SING_BOX_BIN="/usr/local/bin/sing-box"
SING_BOX_CONFIG_DIR="/etc/sing-box"
SING_BOX_CONFIG="${SING_BOX_CONFIG_DIR}/config.json"
SING_BOX_CERT_DIR="${SING_BOX_CONFIG_DIR}/certs"
SING_BOX_SERVICE="/etc/systemd/system/sing-box.service"
SING_BOX_RUN_USER="sing-box"
SING_BOX_RUN_GROUP="sing-box"
TROJAN_CERT_DIR="${SING_BOX_CERT_DIR}"
TROJAN_WEB_ROOT="/var/www/vless-onekey"
TROJAN_NGINX_CONFIG="/etc/nginx/conf.d/vless-onekey-fallback.conf"
NGINX_DEFAULT_SITE="/etc/nginx/sites-enabled/default"
TROJAN_RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/vless-onekey-sing-box-cert.sh"
LEGACY_TROJAN_RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/vless-onekey-xray-cert.sh"
NODE_NAME=""
CLIENT_FINGERPRINT="chrome"
MAX_TIME_DIFF_MS="60000"
ARTIFACT_DIR="/root/vless-export"
PUBLIC_IP=""
PUBLIC_IP_FAMILY=""

ASSUME_YES="0"
FORCE_OVERWRITE="0"
SKIP_FIREWALL="0"
SKIP_PACKAGES="0"
SKIP_QR="0"
SKIP_SZ="0"
SKIP_XRAY_UPGRADE="0"
XRAY_BETA="0"
AUTO_UPDATE_XRAY="0"
AUTO_UPDATE_TIME="03:30:00"
ALLOW_NON_443="0"

OS_ID=""
OS_VERSION_ID=""
XRAY_CONFIG="/usr/local/etc/xray/config.json"
CONFIG_FILE="${XRAY_CONFIG}"
CONFIG_BACKUP_FILE=""
CONFIG_WAS_BACKED_UP="0"
CONFIG_REPLACED="0"
HARDENING_BACKUP_FILE=""
HARDENING_CHANGED="0"
KEEP_EXISTING_CONFIG="0"
XRAY_BIN=""
XRAY_RUN_USER="xray"
XRAY_RUN_GROUP=""
XRAY_LISTEN="0.0.0.0"
CLASH_YAML_NAME=""
OLD_XRAY_PORT=""
NODE_URL=""
NODE_LINK_NAME=""
NODE_URL_TEMP_CREATED="0"
NODE_URL_TEMP_FILE=""
EXPORT_SERVER=""
NGINX_PREEXISTING="0"
NGINX_CONFIG_BACKUP_FILE=""
NGINX_CONFIG_CHANGED="0"
NGINX_DEFAULT_REMOVED="0"
RENEW_HOOK_BACKUP_FILE=""
RENEW_HOOK_CHANGED="0"
SING_BOX_CONFIG_WAS_BACKED_UP="0"
SING_BOX_CONFIG_BACKUP_FILE=""
SING_BOX_CONFIG_REPLACED="0"
SING_BOX_CHANGED="0"
SING_BOX_SERVICE_WAS_BACKED_UP="0"
SING_BOX_SERVICE_BACKUP_FILE=""
SING_BOX_BIN_CHANGED="0"
SING_BOX_BIN_BACKUP_FILE=""
SING_BOX_WAS_ACTIVE="0"
XRAY_STOPPED_FOR_TROJAN="0"

usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

One-command installer for Xray VLESS Reality or sing-box Trojan TLS with local export assets.

Usage:
  bash ${SCRIPT_NAME} [options]

Options:
  --protocol VALUE          Deployment protocol: reality or trojan. Default: ${PROTOCOL}
  --port PORT               Public proxy listen port. Default: 443
  --sni HOST                Required SNI and Reality serverNames; choose a verified same-ASN TLS 1.3 site
  --dest-host HOST          Reality dest host. Default: same as --sni
  --dest-port PORT          Reality dest port. Default: ${DEST_PORT}
  --max-time-diff-ms MS     Reject stale Reality handshakes beyond this clock skew. Default: ${MAX_TIME_DIFF_MS}
  --domain HOST             Trojan TLS certificate domain; DNS must point directly to this server
  --acme-email EMAIL        Optional Let's Encrypt ACME account email for Trojan TLS
  --allow-non-443           Explicitly allow a non-443 listen or target port
  --node-name NAME          Exported node name. Default: server hostname
  --fingerprint VALUE       Client fingerprint for exports. Default: ${CLIENT_FINGERPRINT}
  --artifact-dir PATH       Directory for generated files. Default: ${ARTIFACT_DIR}
  --public-ip IP            Override auto-detected public IP
  --force-overwrite         Replace an existing backend config after creating a timestamped backup
  --upgrade-xray            Reality only: update Xray to latest stable release. This is the default
  --skip-xray-upgrade       Reality only: keep the installed Xray binary
  --xray-beta               Reality only: install/update latest Xray pre-release
  --auto-update-xray        Reality only: enable a daily Xray update timer
  --skip-auto-update-xray   Reality only: disable the Xray update timer. This is the default
  --auto-update-time TIME   Daily auto-update time in HH:MM or HH:MM:SS. Default: ${AUTO_UPDATE_TIME}
  --skip-firewall           Do not change UFW rules
  --skip-packages           Skip apt package installation
  --skip-qr                 Do not generate Shadowrocket QR PNG
  --skip-sz                 Do not auto-download the server-named Clash YAML with sz at the end
  -y, --yes                 Run non-interactively
  -V, --version             Show script version
  -h, --help                Show this help

Examples:
  bash ${SCRIPT_NAME} -y --sni www.example.com
  bash ${SCRIPT_NAME} -y --sni www.example.com --node-name my-vps --force-overwrite
  bash ${SCRIPT_NAME} -y --protocol trojan --domain proxy.example.com

GitHub Raw example:
  bash <(curl -fsSL https://raw.githubusercontent.com/whaiyang/vless-onekey/main/${SCRIPT_NAME}) -y --sni www.example.com
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
  local restart_xray="0"
  local restart_sing_box="0"
  if [[ "${exit_code}" -eq 0 ]]; then
    return
  fi

  set +e
  warn "Installer exited with code ${exit_code}."
  if [[ "${NODE_URL_TEMP_CREATED}" == "1" && -n "${NODE_URL_TEMP_FILE}" ]]; then
    rm -f "${NODE_URL_TEMP_FILE}"
  fi
  if [[ "${CONFIG_REPLACED}" == "1" && "${CONFIG_WAS_BACKED_UP}" == "1" && -f "${CONFIG_BACKUP_FILE}" ]]; then
    cp "${CONFIG_BACKUP_FILE}" "${CONFIG_FILE}"
    warn "Restored the previous Xray config from: ${CONFIG_BACKUP_FILE}"
    restart_xray="1"
  fi
  if [[ "${SING_BOX_CONFIG_REPLACED}" == "1" ]]; then
    systemctl stop sing-box >/dev/null 2>&1 || true
    if [[ "${SING_BOX_CONFIG_WAS_BACKED_UP}" == "1" && -f "${SING_BOX_CONFIG_BACKUP_FILE}" ]]; then
      cp "${SING_BOX_CONFIG_BACKUP_FILE}" "${SING_BOX_CONFIG}"
      warn "Restored the previous sing-box config from: ${SING_BOX_CONFIG_BACKUP_FILE}"
      if [[ "${SING_BOX_WAS_ACTIVE}" == "1" ]]; then
        restart_sing_box="1"
      fi
    else
      rm -f "${SING_BOX_CONFIG}"
    fi
  fi
  if [[ "${HARDENING_CHANGED}" == "1" ]]; then
    if [[ -n "${HARDENING_BACKUP_FILE}" && -f "${HARDENING_BACKUP_FILE}" ]]; then
      cp "${HARDENING_BACKUP_FILE}" "${XRAY_HARDENING_DROP_IN}"
    else
      rm -f "${XRAY_HARDENING_DROP_IN}"
    fi
    systemctl daemon-reload
    warn "Restored the previous Xray systemd hardening configuration."
    restart_xray="1"
  fi
  if [[ "${SING_BOX_CHANGED}" == "1" ]]; then
    if [[ "${SING_BOX_SERVICE_WAS_BACKED_UP}" == "1" && -f "${SING_BOX_SERVICE_BACKUP_FILE}" ]]; then
      cp "${SING_BOX_SERVICE_BACKUP_FILE}" "${SING_BOX_SERVICE}"
    else
      rm -f "${SING_BOX_SERVICE}"
    fi
    systemctl daemon-reload
    warn "Restored the previous sing-box systemd service definition."
  fi
  if [[ "${SING_BOX_BIN_CHANGED}" == "1" ]]; then
    if [[ -n "${SING_BOX_BIN_BACKUP_FILE}" && -f "${SING_BOX_BIN_BACKUP_FILE}" ]]; then
      cp "${SING_BOX_BIN_BACKUP_FILE}" "${SING_BOX_BIN}"
      chmod 755 "${SING_BOX_BIN}"
      warn "Restored the previous sing-box binary."
    else
      rm -f "${SING_BOX_BIN}"
    fi
  fi
  if [[ "${RENEW_HOOK_CHANGED}" == "1" ]]; then
    if [[ -n "${RENEW_HOOK_BACKUP_FILE}" && -f "${RENEW_HOOK_BACKUP_FILE}" ]]; then
      cp "${RENEW_HOOK_BACKUP_FILE}" "${TROJAN_RENEW_HOOK}"
    else
      rm -f "${TROJAN_RENEW_HOOK}"
    fi
    warn "Restored the previous Certbot deploy hook."
  fi
  if [[ "${NGINX_CONFIG_CHANGED}" == "1" ]]; then
    if [[ -n "${NGINX_CONFIG_BACKUP_FILE}" && -f "${NGINX_CONFIG_BACKUP_FILE}" ]]; then
      cp "${NGINX_CONFIG_BACKUP_FILE}" "${TROJAN_NGINX_CONFIG}"
    else
      rm -f "${TROJAN_NGINX_CONFIG}"
    fi
    if [[ "${NGINX_DEFAULT_REMOVED}" == "1" && -f /etc/nginx/sites-available/default ]]; then
      ln -sfn /etc/nginx/sites-available/default "${NGINX_DEFAULT_SITE}"
    fi
    nginx -t >/dev/null 2>&1 && systemctl restart nginx
    warn "Restored the previous Nginx configuration."
  fi
  if [[ "${restart_xray}" == "1" ]]; then
    systemctl restart xray
  fi
  if [[ "${restart_sing_box}" == "1" ]]; then
    systemctl restart sing-box
  elif [[ "${XRAY_STOPPED_FOR_TROJAN}" == "1" ]]; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray >/dev/null 2>&1 || true
    warn "Restored Xray after the sing-box Trojan deployment failed."
  fi
  exit "${exit_code}"
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
      --protocol)
        PROTOCOL="${2:-}"
        shift 2
        ;;
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
      --max-time-diff-ms)
        MAX_TIME_DIFF_MS="${2:-}"
        shift 2
        ;;
      --domain)
        DOMAIN="${2:-}"
        shift 2
        ;;
      --acme-email)
        ACME_EMAIL="${2:-}"
        shift 2
        ;;
      --allow-non-443)
        ALLOW_NON_443="1"
        shift
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
      --upgrade-xray)
        SKIP_XRAY_UPGRADE="0"
        shift
        ;;
      --skip-xray-upgrade)
        SKIP_XRAY_UPGRADE="1"
        shift
        ;;
      --xray-beta)
        XRAY_BETA="1"
        shift
        ;;
      --auto-update-xray)
        AUTO_UPDATE_XRAY="1"
        shift
        ;;
      --skip-auto-update-xray)
        AUTO_UPDATE_XRAY="0"
        shift
        ;;
      --auto-update-time)
        AUTO_UPDATE_TIME="${2:-}"
        shift 2
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
      --skip-sz)
        SKIP_SZ="1"
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
  [[ "${PROTOCOL}" == "reality" || "${PROTOCOL}" == "trojan" ]] || die "--protocol must be exactly reality or trojan"
  [[ "${CLIENT_FINGERPRINT}" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid --fingerprint value: ${CLIENT_FINGERPRINT}"

  [[ "${PORT}" =~ ^[0-9]+$ ]] || die "--port must be a number"
  (( PORT >= 1 && PORT <= 65535 )) || die "--port must be between 1 and 65535"

  if [[ "${PROTOCOL}" == "reality" ]]; then
    [[ -n "${SNI}" ]] || die "--sni is required for Reality. Choose a verified same-ASN TLS 1.3 target."
    [[ "${SNI}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid --sni value: ${SNI}"
    [[ -z "${DEST_HOST}" || "${DEST_HOST}" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid --dest-host value: ${DEST_HOST}"
    [[ -z "${DOMAIN}" ]] || die "--domain is only valid with --protocol trojan"
    [[ -z "${ACME_EMAIL}" ]] || die "--acme-email is only valid with --protocol trojan"
    [[ "${DEST_PORT}" =~ ^[0-9]+$ ]] || die "--dest-port must be a number"
    (( DEST_PORT >= 1 && DEST_PORT <= 65535 )) || die "--dest-port must be between 1 and 65535"
    [[ "${MAX_TIME_DIFF_MS}" =~ ^[0-9]+$ ]] || die "--max-time-diff-ms must be a non-negative number"
    if [[ "${ALLOW_NON_443}" != "1" ]] && { [[ "${PORT}" != "443" ]] || [[ "${DEST_PORT}" != "443" ]]; }; then
      die "REALITY should use port 443. Re-run with --allow-non-443 only after reviewing the blocking risk."
    fi
  else
    [[ -n "${DOMAIN}" ]] || die "--domain is required for Trojan TLS"
    [[ "${DOMAIN}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && "${DOMAIN}" == *.* && "${DOMAIN}" != *..* ]] || die "Invalid --domain value: ${DOMAIN}"
    [[ -z "${SNI}" ]] || die "Use --domain instead of --sni with --protocol trojan"
    [[ -z "${DEST_HOST}" ]] || die "--dest-host is only valid with --protocol reality"
    [[ "${DEST_PORT}" == "443" ]] || die "--dest-port is only valid with --protocol reality"
    if [[ -n "${ACME_EMAIL}" ]]; then
      [[ "${ACME_EMAIL}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Invalid --acme-email value"
    fi
    if [[ "${ALLOW_NON_443}" != "1" && "${PORT}" != "443" ]]; then
      die "Trojan TLS should use port 443. Re-run with --allow-non-443 only after reviewing compatibility."
    fi
    [[ "${XRAY_BETA}" != "1" ]] || die "--xray-beta is only valid with --protocol reality"
    [[ "${AUTO_UPDATE_XRAY}" != "1" ]] || die "--auto-update-xray is only valid with --protocol reality"
  fi

  [[ "${AUTO_UPDATE_TIME}" =~ ^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]] || die "--auto-update-time must be HH:MM or HH:MM:SS"
  if [[ "${AUTO_UPDATE_TIME}" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    AUTO_UPDATE_TIME="${AUTO_UPDATE_TIME}:00"
  fi
}

ensure_defaults() {
  if [[ "${PROTOCOL}" == "reality" && -z "${DEST_HOST}" ]]; then
    DEST_HOST="${SNI}"
  fi
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    SNI="${DOMAIN}"
    CONFIG_FILE="${SING_BOX_CONFIG}"
  fi
  if [[ -z "${NODE_NAME}" ]]; then
    NODE_NAME="$(hostname)"
  fi
}

confirm_plan() {
  local config_action="write new config"
  if [[ -f "${CONFIG_FILE}" && "${FORCE_OVERWRITE}" != "1" ]]; then
    KEEP_EXISTING_CONFIG="1"
    config_action="preserve existing config"
  elif [[ -f "${CONFIG_FILE}" && "${FORCE_OVERWRITE}" == "1" ]]; then
    config_action="backup and replace config"
  fi

  log "Release-ready installer summary"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
OS             : ${OS_ID} ${OS_VERSION_ID}
Protocol       : ${PROTOCOL}
Config action  : ${config_action}
Listen port    : ${PORT}
Node name      : ${NODE_NAME}
Artifact dir   : ${ARTIFACT_DIR}
Skip firewall  : ${SKIP_FIREWALL}
Skip packages  : ${SKIP_PACKAGES}
Skip QR        : ${SKIP_QR}
Auto sz Clash  : $([[ "${SKIP_SZ}" == "1" ]] && printf 'no' || printf 'yes')
EOF

  if [[ "${PROTOCOL}" == "reality" ]]; then
    cat <<EOF
SNI            : ${SNI}
Reality dest   : ${DEST_HOST}:${DEST_PORT}
Fingerprint    : ${CLIENT_FINGERPRINT}
Max time diff  : ${MAX_TIME_DIFF_MS} ms
Backend        : Xray ($([[ "${XRAY_BETA}" == "1" ]] && printf 'pre-release' || printf 'stable'))
Upgrade Xray   : $([[ "${SKIP_XRAY_UPGRADE}" == "1" ]] && printf 'no' || printf 'yes')
Auto update    : ${AUTO_UPDATE_XRAY}
Auto update at : ${AUTO_UPDATE_TIME}
EOF
  else
    cat <<EOF
TLS domain     : ${DOMAIN}
ACME email     : ${ACME_EMAIL:-not provided}
Fallback       : 127.0.0.1:${TROJAN_FALLBACK_PORT}
Certificate    : Let's Encrypt with automatic renewal
Backend        : sing-box ${SING_BOX_VERSION}
Auto update    : disabled; upgrades require a reviewed script release
EOF
  fi

  if [[ "${KEEP_EXISTING_CONFIG}" == "1" ]]; then
    warn "Existing backend config found at ${CONFIG_FILE}; it will be preserved."
    warn "Re-run with --force-overwrite if you really want to replace it and export a new node."
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

detect_existing_nginx() {
  if command_exists nginx; then
    NGINX_PREEXISTING="1"
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
  local packages=(
    ca-certificates \
    curl \
    lrzsz \
    openssl \
    passwd \
    python3 \
    qrencode \
    tar \
    ufw \
    unzip \
    uuid-runtime
  )
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    packages+=(certbot nginx)
  fi
  apt-get install -y "${packages[@]}"
}

ensure_required_commands() {
  local required=(curl openssl python3 awk sed ss timeout useradd mktemp sha256sum)
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
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    command_exists certbot || die "certbot is required for Trojan TLS"
    command_exists nginx || die "nginx is required for the Trojan fallback site"
    command_exists runuser || die "runuser is required to validate sing-box as its service user"
    command_exists tar || die "tar is required to install sing-box"
  fi
}

ensure_xray_run_user() {
  if ! id "${XRAY_RUN_USER}" >/dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/xray --shell /usr/sbin/nologin "${XRAY_RUN_USER}"
  fi
  XRAY_RUN_GROUP="$(id -gn "${XRAY_RUN_USER}")"
  install -d -m 750 -o "${XRAY_RUN_USER}" -g "${XRAY_RUN_GROUP}" /var/lib/xray
  if [[ -f "${CONFIG_FILE}" ]]; then
    chown "root:${XRAY_RUN_GROUP}" "$(dirname "${CONFIG_FILE}")" "${CONFIG_FILE}"
    chmod 750 "$(dirname "${CONFIG_FILE}")"
    chmod 640 "${CONFIG_FILE}"
  fi
}

install_xray() {
  local installer_args=(install -u "${XRAY_RUN_USER}")
  local current_service_user=""
  if [[ "${XRAY_BETA}" == "1" ]]; then
    installer_args+=(--beta)
  fi

  if command_exists xray; then
    XRAY_BIN="$(command -v xray)"
    log "Xray already installed at ${XRAY_BIN}"
    if [[ "${SKIP_XRAY_UPGRADE}" == "1" ]]; then
      log "Skipping Xray update check by request"
      return
    fi
    current_service_user="$(systemctl show xray -p User --value 2>/dev/null || true)"
    if [[ -n "${current_service_user}" && "${current_service_user}" != "${XRAY_RUN_USER}" ]]; then
      [[ "${XRAY_BETA}" != "1" ]] || die "Cannot combine a service-user migration with --xray-beta. Install stable first."
      installer_args+=(--reinstall)
      log "Reinstalling Xray to migrate the service from ${current_service_user} to ${XRAY_RUN_USER}"
    fi
    log "Checking/updating Xray via the official installer"
  else
    log "Installing Xray via the official installer"
  fi

  bash -c "$(curl -fsSL "${XRAY_INSTALLER_URL}")" @ "${installer_args[@]}"

  XRAY_BIN="$(command -v xray || true)"
  [[ -n "${XRAY_BIN}" ]] || XRAY_BIN="/usr/local/bin/xray"
  [[ -x "${XRAY_BIN}" ]] || die "Xray installation completed but xray binary was not found."
}

ensure_sing_box_run_user() {
  if ! id "${SING_BOX_RUN_USER}" >/dev/null 2>&1; then
    useradd --system --user-group --create-home --home-dir /var/lib/sing-box --shell /usr/sbin/nologin "${SING_BOX_RUN_USER}"
  fi
  SING_BOX_RUN_GROUP="$(id -gn "${SING_BOX_RUN_USER}")"
  install -d -m 750 -o "${SING_BOX_RUN_USER}" -g "${SING_BOX_RUN_GROUP}" /var/lib/sing-box
  install -d -m 750 -o root -g "${SING_BOX_RUN_GROUP}" "${SING_BOX_CONFIG_DIR}"
}

install_sing_box() {
  local machine_arch
  local release_arch
  local expected_sha256
  local download_url
  local temp_dir
  local archive
  local extracted_bin

  machine_arch="$(uname -m)"
  case "${machine_arch}" in
    x86_64|amd64)
      release_arch="amd64"
      expected_sha256="${SING_BOX_SHA256_AMD64}"
      ;;
    aarch64|arm64)
      release_arch="arm64"
      expected_sha256="${SING_BOX_SHA256_ARM64}"
      ;;
    *)
      die "Unsupported architecture for sing-box Trojan: ${machine_arch}"
      ;;
  esac

  download_url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${release_arch}.tar.gz"
  temp_dir="$(mktemp -d /tmp/vless-onekey-sing-box.XXXXXX)"
  archive="${temp_dir}/sing-box.tar.gz"
  extracted_bin="${temp_dir}/sing-box-${SING_BOX_VERSION}-linux-${release_arch}/sing-box"

  log "Installing verified sing-box ${SING_BOX_VERSION} for ${release_arch}"
  curl -fsSL --retry 3 --connect-timeout 15 -o "${archive}" "${download_url}" || {
    rm -rf "${temp_dir}"
    die "Failed to download sing-box ${SING_BOX_VERSION}."
  }
  [[ "$(sha256sum "${archive}" | awk '{print $1}')" == "${expected_sha256}" ]] || {
    rm -rf "${temp_dir}"
    die "sing-box archive checksum mismatch."
  }
  tar -xzf "${archive}" -C "${temp_dir}" || {
    rm -rf "${temp_dir}"
    die "Failed to extract the sing-box archive."
  }
  [[ -x "${extracted_bin}" ]] || {
    rm -rf "${temp_dir}"
    die "The sing-box archive did not contain the expected binary."
  }
  if [[ -f "${SING_BOX_BIN}" ]]; then
    SING_BOX_BIN_BACKUP_FILE="${SING_BOX_BIN}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${SING_BOX_BIN}" "${SING_BOX_BIN_BACKUP_FILE}"
    chmod 700 "${SING_BOX_BIN_BACKUP_FILE}"
  fi
  install -m 755 -o root -g root "${extracted_bin}" "${SING_BOX_BIN}"
  SING_BOX_BIN_CHANGED="1"
  rm -rf "${temp_dir}"
  "${SING_BOX_BIN}" version | grep -q "sing-box version ${SING_BOX_VERSION}" || die "Unexpected sing-box version after installation."
}

configure_sing_box_service() {
  if [[ -f "${SING_BOX_SERVICE}" ]]; then
    SING_BOX_SERVICE_BACKUP_FILE="${SING_BOX_SERVICE}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${SING_BOX_SERVICE}" "${SING_BOX_SERVICE_BACKUP_FILE}"
    chmod 600 "${SING_BOX_SERVICE_BACKUP_FILE}"
    SING_BOX_SERVICE_WAS_BACKED_UP="1"
  fi
  cat > "${SING_BOX_SERVICE}" <<EOF
[Unit]
Description=sing-box Trojan TLS Service
Documentation=https://sing-box.sagernet.org/
Wants=network-online.target
After=network-online.target nginx.service

[Service]
Type=simple
User=${SING_BOX_RUN_USER}
Group=${SING_BOX_RUN_GROUP}
ExecStart=${SING_BOX_BIN} run -c ${SING_BOX_CONFIG}
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s
LimitNOFILE=1048576
UMask=0077
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
SystemCallArchitectures=native
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
StateDirectory=sing-box
StateDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "${SING_BOX_SERVICE}"
  SING_BOX_CHANGED="1"
  systemctl daemon-reload
}

configure_xray_service_hardening() {
  mkdir -p "$(dirname "${XRAY_HARDENING_DROP_IN}")"
  if [[ -f "${XRAY_HARDENING_DROP_IN}" ]]; then
    HARDENING_BACKUP_FILE="${XRAY_HARDENING_DROP_IN}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${XRAY_HARDENING_DROP_IN}" "${HARDENING_BACKUP_FILE}"
    chmod 600 "${HARDENING_BACKUP_FILE}"
  fi
  cat > "${XRAY_HARDENING_DROP_IN}" <<EOF
[Service]
User=${XRAY_RUN_USER}
Group=${XRAY_RUN_GROUP}
CapabilityBoundingSet=
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
UMask=0077
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
SystemCallArchitectures=native
EOF
  HARDENING_CHANGED="1"
  chmod 644 "${XRAY_HARDENING_DROP_IN}"
  systemctl daemon-reload
}

configure_xray_auto_update() {
  if [[ "${AUTO_UPDATE_XRAY}" != "1" ]]; then
    if command_exists systemctl; then
      systemctl disable --now xray-auto-update.timer >/dev/null 2>&1 || true
    fi
    return
  fi

  command_exists systemctl || die "systemctl is required to enable Xray auto update."
  log "Enabling Xray automatic updates"

  local beta_arg=""
  local xray_binary="${XRAY_BIN:-/usr/local/bin/xray}"
  if [[ "${XRAY_BETA}" == "1" ]]; then
    beta_arg=" --beta"
  fi

  mkdir -p "$(dirname "${XRAY_AUTO_UPDATE_SCRIPT}")"

  cat > "${XRAY_AUTO_UPDATE_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

XRAY_INSTALLER_URL="${XRAY_INSTALLER_URL}"

bash -c "\$(curl -fsSL "\${XRAY_INSTALLER_URL}")" @ install -u "${XRAY_RUN_USER}" --no-update-service${beta_arg}
EOF
  chmod 700 "${XRAY_AUTO_UPDATE_SCRIPT}"

  cat > "${XRAY_AUTO_UPDATE_SERVICE}" <<EOF
[Unit]
Description=Update Xray-core through the official Xray installer
Documentation=https://github.com/XTLS/Xray-install
Wants=network-online.target
After=network-online.target
ConditionPathExists=${xray_binary}

[Service]
Type=oneshot
ExecStart=${XRAY_AUTO_UPDATE_SCRIPT}
EOF

  cat > "${XRAY_AUTO_UPDATE_TIMER}" <<EOF
[Unit]
Description=Run Xray-core automatic update daily

[Timer]
OnCalendar=*-*-* ${AUTO_UPDATE_TIME}
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now xray-auto-update.timer >/dev/null
  systemctl is-enabled --quiet xray-auto-update.timer || die "Failed to enable xray-auto-update.timer."
}

validate_reality_target() {
  local tls_output
  log "Validating Reality target TLS 1.3 and certificate"
  tls_output="$(
    timeout 20 openssl s_client \
      -connect "${DEST_HOST}:${DEST_PORT}" \
      -servername "${SNI}" \
      -verify_hostname "${SNI}" \
      -tls1_3 </dev/null 2>&1
  )" || die "Unable to complete a TLS 1.3 handshake with ${DEST_HOST}:${DEST_PORT}."

  grep -q "Verify return code: 0 (ok)" <<<"${tls_output}" || die "Reality target certificate does not verify for SNI ${SNI}."
  log "Reality target validation passed: ${SNI} via ${DEST_HOST}:${DEST_PORT}"
}

validate_trojan_domain_dns() {
  local dns_output
  local public_ipv4=""
  local public_ipv6=""
  log "Validating Trojan domain DNS"
  public_ipv4="$(curl -4fsSL https://api64.ipify.org 2>/dev/null || true)"
  public_ipv6="$(curl -6fsSL https://api64.ipify.org 2>/dev/null || true)"
  dns_output="$(python3 - "${DOMAIN}" "${PUBLIC_IP}" "${public_ipv4}" "${public_ipv6}" 2>&1 <<'PY'
import ipaddress
import socket
import sys

domain = sys.argv[1]
expected = {
    ipaddress.ip_address(value)
    for value in sys.argv[2:]
    if value
}
try:
    resolved = {
        ipaddress.ip_address(item[4][0])
        for item in socket.getaddrinfo(domain, None, type=socket.SOCK_STREAM)
    }
except socket.gaierror as exc:
    raise SystemExit(f"DNS lookup failed for {domain}: {exc}")
unexpected = resolved - expected
if not resolved or unexpected:
    resolved_values = ", ".join(sorted(map(str, resolved))) or "no addresses"
    expected_values = ", ".join(sorted(map(str, expected))) or "no detected addresses"
    raise SystemExit(
        f"{domain} resolves to {resolved_values}; this server exposes {expected_values}. "
        "Disable CDN/proxy mode and correct the A/AAAA record first."
    )
PY
  )" || die "${dns_output}"
  log "Domain DNS points only to this server: ${DOMAIN}"
}

configure_trojan_fallback() {
  local ipv6_listen=""
  log "Configuring Nginx fallback and ACME webroot"
  if [[ "${NGINX_PREEXISTING}" == "1" && -e "${NGINX_DEFAULT_SITE}" && ! -f "${TROJAN_NGINX_CONFIG}" ]]; then
    die "Existing Nginx default site detected. Remove or migrate it before using the automated Trojan deployment."
  fi

  install -d -m 755 -o root -g root "${TROJAN_WEB_ROOT}"
  if [[ ! -f "${TROJAN_WEB_ROOT}/index.html" ]]; then
    cat > "${TROJAN_WEB_ROOT}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Welcome</title></head>
<body><h1>Welcome</h1><p>This site is online.</p></body>
</html>
EOF
    chmod 644 "${TROJAN_WEB_ROOT}/index.html"
  fi

  if [[ -f "${TROJAN_NGINX_CONFIG}" ]]; then
    NGINX_CONFIG_BACKUP_FILE="${TROJAN_NGINX_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${TROJAN_NGINX_CONFIG}" "${NGINX_CONFIG_BACKUP_FILE}"
    chmod 600 "${NGINX_CONFIG_BACKUP_FILE}"
  fi
  NGINX_CONFIG_CHANGED="1"

  if [[ -e "${NGINX_DEFAULT_SITE}" ]]; then
    rm -f "${NGINX_DEFAULT_SITE}"
    NGINX_DEFAULT_REMOVED="1"
  fi

  if has_ipv6_stack; then
    ipv6_listen="    listen [::]:80 default_server;"
  fi

  cat > "${TROJAN_NGINX_CONFIG}" <<EOF
server {
    listen 127.0.0.1:${TROJAN_FALLBACK_PORT} default_server;
    server_name _;
    root ${TROJAN_WEB_ROOT};
    index index.html;
    server_tokens off;

    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Frame-Options "DENY" always;

    location = /health {
        default_type text/plain;
        return 200 "ok\\n";
    }
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

server {
    listen 80 default_server;
${ipv6_listen}
    server_name ${DOMAIN};
    root ${TROJAN_WEB_ROOT};

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        try_files \$uri =404;
    }
    location / {
        return 301 https://${DOMAIN}\$request_uri;
    }
}
EOF
  chmod 644 "${TROJAN_NGINX_CONFIG}"
  nginx -t >/dev/null
  systemctl enable nginx >/dev/null
  systemctl restart nginx
  systemctl is-active --quiet nginx || die "Nginx failed to start."
}

issue_trojan_certificate() {
  local contact_args=(--register-unsafely-without-email)
  if [[ -n "${ACME_EMAIL}" ]]; then
    contact_args=(--email "${ACME_EMAIL}")
  fi

  log "Requesting or reusing a Let's Encrypt certificate for ${DOMAIN}"
  certbot certonly \
    --webroot \
    --webroot-path "${TROJAN_WEB_ROOT}" \
    --cert-name "${DOMAIN}" \
    --domain "${DOMAIN}" \
    --non-interactive \
    --agree-tos \
    --keep-until-expiring \
    "${contact_args[@]}"

  local lineage="/etc/letsencrypt/live/${DOMAIN}"
  [[ -s "${lineage}/fullchain.pem" && -s "${lineage}/privkey.pem" ]] || die "Certbot completed without the expected certificate files."
  openssl x509 -in "${lineage}/fullchain.pem" -noout -checkend 2592000 >/dev/null || die "The certificate expires in less than 30 days."
}

install_trojan_certificates() {
  local lineage="/etc/letsencrypt/live/${DOMAIN}"
  install -d -m 750 -o root -g "${SING_BOX_RUN_GROUP}" "${TROJAN_CERT_DIR}"
  install -m 640 -o root -g "${SING_BOX_RUN_GROUP}" "${lineage}/fullchain.pem" "${TROJAN_CERT_DIR}/${DOMAIN}.fullchain.pem"
  install -m 640 -o root -g "${SING_BOX_RUN_GROUP}" "${lineage}/privkey.pem" "${TROJAN_CERT_DIR}/${DOMAIN}.key.pem"
}

configure_trojan_certificate_renewal() {
  log "Configuring and validating automatic certificate renewal"
  install -d -m 755 -o root -g root "$(dirname "${TROJAN_RENEW_HOOK}")"
  if [[ -f "${TROJAN_RENEW_HOOK}" ]]; then
    RENEW_HOOK_BACKUP_FILE="${TROJAN_RENEW_HOOK}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${TROJAN_RENEW_HOOK}" "${RENEW_HOOK_BACKUP_FILE}"
    chmod 600 "${RENEW_HOOK_BACKUP_FILE}"
  fi
  RENEW_HOOK_CHANGED="1"

  cat > "${TROJAN_RENEW_HOOK}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${DOMAIN}"
SING_BOX_GROUP="${SING_BOX_RUN_GROUP}"
SING_BOX_BIN="${SING_BOX_BIN}"
CONFIG_FILE="${SING_BOX_CONFIG}"
CERT_DIR="${TROJAN_CERT_DIR}"

if [[ " \${RENEWED_DOMAINS:-} " != *" \${DOMAIN} "* ]]; then
  exit 0
fi
LINEAGE="\${RENEWED_LINEAGE:-/etc/letsencrypt/live/\${DOMAIN}}"
install -d -m 750 -o root -g "\${SING_BOX_GROUP}" "\${CERT_DIR}"
install -m 640 -o root -g "\${SING_BOX_GROUP}" "\${LINEAGE}/fullchain.pem" "\${CERT_DIR}/\${DOMAIN}.fullchain.pem"
install -m 640 -o root -g "\${SING_BOX_GROUP}" "\${LINEAGE}/privkey.pem" "\${CERT_DIR}/\${DOMAIN}.key.pem"
runuser -u "${SING_BOX_RUN_USER}" -- "\${SING_BOX_BIN}" check -c "\${CONFIG_FILE}" >/dev/null
systemctl restart sing-box
systemctl is-active --quiet sing-box
EOF
  chmod 700 "${TROJAN_RENEW_HOOK}"

  systemctl enable --now certbot.timer >/dev/null
  systemctl is-enabled --quiet certbot.timer || die "Failed to enable certbot.timer."
  certbot renew --cert-name "${DOMAIN}" --dry-run >/dev/null
}

verify_trojan_fallback() {
  local loopback="127.0.0.1"
  if [[ "${XRAY_LISTEN}" == "::" ]]; then
    loopback="[::1]"
  fi
  curl --noproxy '*' --fail --silent --show-error --max-time 10 \
    --resolve "${DOMAIN}:${PORT}:${loopback}" \
    "https://${DOMAIN}:${PORT}/" >/dev/null || die "Trojan TLS fallback HTTPS check failed."
}

check_listen_port_available() {
  local listeners
  listeners="$(ss -H -ltnp "sport = :${PORT}" 2>/dev/null || true)"
  if [[ -n "${listeners}" ]]; then
    if [[ "${PROTOCOL}" == "reality" ]] && ! grep -q 'users:(("xray"' <<<"${listeners}"; then
      die "TCP port ${PORT} is already used by another process: ${listeners}"
    fi
    if [[ "${PROTOCOL}" == "trojan" ]] && ! grep -Eq 'users:\(\("(xray|sing-box)"' <<<"${listeners}"; then
      die "TCP port ${PORT} is already used by another process: ${listeners}"
    fi
  fi
}

wait_for_xray_listener() {
  local attempt
  for attempt in {1..40}; do
    if ss -H -ltnp "sport = :${PORT}" 2>/dev/null | grep -q 'users:(("xray"'; then
      return
    fi
    sleep 0.25
  done
  die "Xray is active but is not listening on TCP port ${PORT}."
}

wait_for_proxy_listener() {
  local process_name="${1}"
  local attempt
  for attempt in {1..40}; do
    if ss -H -ltnp "sport = :${PORT}" 2>/dev/null | grep -q "users:((\"${process_name}\""; then
      return
    fi
    sleep 0.25
  done
  die "${process_name} is active but is not listening on TCP port ${PORT}."
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
  PRIVATE_KEY="$(awk -F': ' '/^Private[Kk]ey/ || /^Private key/ {print $2; exit}' <<<"${x25519_output}")"
  PUBLIC_KEY="$(awk -F': ' '/^Public[Kk]ey/ || /^Public key/ || /^Password \(PublicKey\)/ {print $2; exit}' <<<"${x25519_output}")"

  [[ -n "${PRIVATE_KEY}" && -n "${PUBLIC_KEY}" ]] || die "Failed to generate Reality keys."
}

generate_trojan_material() {
  log "Generating a strong Trojan password"
  TROJAN_PASSWORD="$(openssl rand -hex 32)"
  [[ "${#TROJAN_PASSWORD}" -eq 64 ]] || die "Failed to generate the Trojan password."
}

backup_existing_config() {
  local config_dir
  config_dir="$(dirname "${CONFIG_FILE}")"
  mkdir -p "${config_dir}"

  if [[ -f "${CONFIG_FILE}" ]]; then
    OLD_XRAY_PORT="$(
      python3 - "${CONFIG_FILE}" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    config = json.load(fh)
for inbound in config.get("inbounds", []):
    if inbound.get("protocol") in {"vless", "trojan"} and isinstance(inbound.get("port"), int):
        print(inbound["port"])
        break
PY
    )"
    CONFIG_BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${CONFIG_FILE}" "${CONFIG_BACKUP_FILE}"
    chmod 600 "${CONFIG_BACKUP_FILE}"
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
            "email": "default@vless.local",
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
          "target": "${DEST_HOST}:${DEST_PORT}",
          "xver": 0,
          "serverNames": [
            "${SNI}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "maxTimeDiff": ${MAX_TIME_DIFF_MS},
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
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
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private",
          "169.254.169.254/32",
          "fe80::/10"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

  CONFIG_REPLACED="1"
  chown "root:${XRAY_RUN_GROUP}" "$(dirname "${CONFIG_FILE}")" "${CONFIG_FILE}"
  chmod 750 "$(dirname "${CONFIG_FILE}")"
  chmod 640 "${CONFIG_FILE}"
  "${XRAY_BIN}" run -test -config "${CONFIG_FILE}" >/dev/null
  systemctl enable xray
  systemctl restart xray
  systemctl is-active --quiet xray || die "Xray failed to start."
  wait_for_xray_listener
}

write_trojan_sing_box_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    SING_BOX_CONFIG_BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "${CONFIG_FILE}" "${SING_BOX_CONFIG_BACKUP_FILE}"
    chmod 600 "${SING_BOX_CONFIG_BACKUP_FILE}"
    SING_BOX_CONFIG_WAS_BACKED_UP="1"
    log "Existing sing-box config backed up to ${SING_BOX_CONFIG_BACKUP_FILE}"
  fi
  if [[ -f "${XRAY_CONFIG}" ]]; then
    local legacy_backup="${XRAY_CONFIG}.trojan-backup.$(date +%Y%m%d%H%M%S)"
    cp -p "${XRAY_CONFIG}" "${legacy_backup}"
    chmod 600 "${legacy_backup}"
    OLD_XRAY_PORT="$(
      python3 - "${XRAY_CONFIG}" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    config = json.load(fh)
for inbound in config.get("inbounds", []):
    if isinstance(inbound.get("port"), int):
        print(inbound["port"])
        break
PY
    )"
    log "Legacy Xray config backed up to ${legacy_backup}"
  fi

  install -d -m 750 -o root -g "${SING_BOX_RUN_GROUP}" "${SING_BOX_CONFIG_DIR}"

  log "Writing sing-box Trojan TLS config"
  cat > "${SING_BOX_CONFIG}" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "${XRAY_LISTEN}",
      "listen_port": ${PORT},
      "tcp_keep_alive": "10m",
      "tcp_keep_alive_interval": "30s",
      "users": [
        {
          "name": "${DOMAIN}",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "alpn": ["http/1.1"],
        "min_version": "1.2",
        "max_version": "1.3",
        "certificate_path": "${TROJAN_CERT_DIR}/${DOMAIN}.fullchain.pem",
        "key_path": "${TROJAN_CERT_DIR}/${DOMAIN}.key.pem"
      },
      "fallback": {
        "server": "127.0.0.1",
        "server_port": ${TROJAN_FALLBACK_PORT}
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [
      {
        "source_ip_cidr": ["127.0.0.1/32"],
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "ip_is_private": true,
        "action": "reject"
      },
      {
        "ip_cidr": ["169.254.169.254/32", "fe80::/10"],
        "action": "reject"
      }
    ],
    "final": "direct"
  }
}
EOF

  SING_BOX_CONFIG_REPLACED="1"
  chown "root:${SING_BOX_RUN_GROUP}" "${SING_BOX_CONFIG_DIR}" "${SING_BOX_CONFIG}"
  chmod 750 "${SING_BOX_CONFIG_DIR}"
  chmod 640 "${SING_BOX_CONFIG}"
  runuser -u "${SING_BOX_RUN_USER}" -- "${SING_BOX_BIN}" check -c "${SING_BOX_CONFIG}" >/dev/null

  if systemctl is-active --quiet xray; then
    systemctl stop xray
    XRAY_STOPPED_FOR_TROJAN="1"
  fi
  systemctl enable --now sing-box >/dev/null
  systemctl restart sing-box
  systemctl is-active --quiet sing-box || die "sing-box failed to start."
  wait_for_proxy_listener "sing-box"
  systemctl disable xray >/dev/null 2>&1 || true
  systemctl disable --now xray-auto-update.timer >/dev/null 2>&1 || true
}

secure_existing_sing_box_config() {
  [[ -f "${SING_BOX_CONFIG}" ]] || return
  chown "root:${SING_BOX_RUN_GROUP}" "${SING_BOX_CONFIG_DIR}" "${SING_BOX_CONFIG}"
  chmod 750 "${SING_BOX_CONFIG_DIR}"
  chmod 640 "${SING_BOX_CONFIG}"
  runuser -u "${SING_BOX_RUN_USER}" -- "${SING_BOX_BIN}" check -c "${SING_BOX_CONFIG}" >/dev/null
  if systemctl is-active --quiet xray; then
    systemctl stop xray
    XRAY_STOPPED_FOR_TROJAN="1"
  fi
  systemctl enable --now sing-box >/dev/null
  systemctl restart sing-box
  systemctl is-active --quiet sing-box || die "sing-box failed after applying service hardening."
  wait_for_proxy_listener "sing-box"
  systemctl disable xray >/dev/null 2>&1 || true
}

secure_existing_xray_config() {
  [[ -f "${CONFIG_FILE}" ]] || return
  chown "root:${XRAY_RUN_GROUP}" "$(dirname "${CONFIG_FILE}")" "${CONFIG_FILE}"
  chmod 750 "$(dirname "${CONFIG_FILE}")"
  chmod 640 "${CONFIG_FILE}"
  "${XRAY_BIN}" run -test -config "${CONFIG_FILE}" >/dev/null
  systemctl restart xray
  systemctl is-active --quiet xray || die "Xray failed after switching to the unprivileged service user."
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
  ufw --force delete allow OpenSSH >/dev/null 2>&1 || true
  ufw --force delete allow 22/tcp >/dev/null 2>&1 || true
  ufw limit OpenSSH >/dev/null 2>&1 || ufw limit 22/tcp >/dev/null 2>&1 || die "Failed to protect the SSH firewall rule."
  ufw allow "${PORT}/tcp" >/dev/null 2>&1 || die "Failed to open TCP port ${PORT} in UFW."
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    ufw allow 80/tcp >/dev/null 2>&1 || die "Failed to open TCP port 80 for ACME renewal."
  fi
  ufw --force enable >/dev/null 2>&1 || die "Failed to enable UFW."
  ufw status | grep -Eq "^${PORT}/tcp[[:space:]]+ALLOW" || die "UFW does not show TCP port ${PORT} as allowed."
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    ufw status | grep -Eq '^80/tcp[[:space:]]+ALLOW' || die "UFW does not show TCP port 80 as allowed."
  fi
}

remove_old_firewall_rule() {
  if [[ "${SKIP_FIREWALL}" == "1" || -z "${OLD_XRAY_PORT}" || "${OLD_XRAY_PORT}" == "${PORT}" ]]; then
    return
  fi
  if [[ "${OLD_XRAY_PORT}" =~ ^[0-9]+$ ]]; then
    ufw --force delete allow "${OLD_XRAY_PORT}/tcp" >/dev/null 2>&1 || warn "Could not remove the old UFW rule for TCP ${OLD_XRAY_PORT}."
  fi
}

write_export_tool() {
  mkdir -p "${ARTIFACT_DIR}"
  cat > "${ARTIFACT_DIR}/vless_export_assets.py" <<'PY'
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
PY
  chmod +x "${ARTIFACT_DIR}/vless_export_assets.py"
}

build_node_url() {
  NODE_URL="$(
    PROTOCOL="${PROTOCOL}" \
    UUID="${UUID:-}" \
    PASSWORD="${TROJAN_PASSWORD:-}" \
    SERVER="${EXPORT_SERVER}" \
    PORT="${PORT}" \
    SNI="${SNI}" \
    FINGERPRINT="${CLIENT_FINGERPRINT}" \
    FLOW="xtls-rprx-vision" \
    PBK="${PUBLIC_KEY:-}" \
    SID="${SHORT_ID:-}" \
    NODE_NAME="${NODE_NAME}" \
    python3 - <<'PY'
import ipaddress
import os
import urllib.parse

protocol = os.environ["PROTOCOL"]
server = os.environ["SERVER"]
try:
    address = ipaddress.ip_address(server)
except ValueError:
    url_server = server
else:
    url_server = f"[{server}]" if address.version == 6 else server

if protocol == "reality":
    scheme = "vless"
    userinfo = os.environ["UUID"]
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
else:
    scheme = "trojan"
    userinfo = urllib.parse.quote(os.environ["PASSWORD"], safe="")
    params = {
        "security": "tls",
        "sni": os.environ["SNI"],
        "type": "tcp",
        "fp": os.environ["FINGERPRINT"],
    }
query = urllib.parse.urlencode(params)
fragment = urllib.parse.quote(os.environ["NODE_NAME"], safe="")
print(
    f"{scheme}://{userinfo}@{url_server}:{os.environ['PORT']}?{query}#{fragment}"
)
PY
  )"
}

generate_assets() {
  local node_url_file=""
  log "Generating export files"
  mkdir -p "${ARTIFACT_DIR}"
  chmod 700 "${ARTIFACT_DIR}"
  build_node_url
  write_export_tool
  node_url_file="$(mktemp "${ARTIFACT_DIR}/.node-url.XXXXXX")"
  NODE_URL_TEMP_FILE="${node_url_file}"
  NODE_URL_TEMP_CREATED="1"
  printf '%s\n' "${NODE_URL}" > "${node_url_file}"
  chmod 600 "${node_url_file}"
  python3 "${ARTIFACT_DIR}/vless_export_assets.py" \
    --node-url-file "${node_url_file}" \
    --output-dir "${ARTIFACT_DIR}"
  rm -f "${node_url_file}"
  NODE_URL_TEMP_CREATED="0"
  NODE_URL_TEMP_FILE=""
  CLASH_YAML_NAME="$(
    python3 - "${ARTIFACT_DIR}/metadata.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh)["clash_yaml"])
PY
  )"
  NODE_LINK_NAME="$(
    python3 - "${ARTIFACT_DIR}/metadata.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh)["node_link"])
PY
  )"

  printf '%s\n' "${NODE_URL}" > "${ARTIFACT_DIR}/${NODE_LINK_NAME}"

  if [[ "${SKIP_QR}" != "1" ]] && command_exists qrencode; then
    printf '%s' "${NODE_URL}" | qrencode -o "${ARTIFACT_DIR}/shadowrocket-node.png"
  fi

  chmod 700 "${ARTIFACT_DIR}/vless_export_assets.py"
  chmod 600 \
    "${ARTIFACT_DIR}/${NODE_LINK_NAME}" \
    "${ARTIFACT_DIR}/${CLASH_YAML_NAME}" \
    "${ARTIFACT_DIR}/shadowrocket.conf" \
    "${ARTIFACT_DIR}/metadata.json"
  if [[ -f "${ARTIFACT_DIR}/shadowrocket-node.png" ]]; then
    chmod 600 "${ARTIFACT_DIR}/shadowrocket-node.png"
  fi

  cat > "${ARTIFACT_DIR}/README.txt" <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

${PROTOCOL} deployment is ready.

Server endpoint: ${EXPORT_SERVER}
Public IP: ${PUBLIC_IP}
Endpoint family: ${PUBLIC_IP_FAMILY}
Port: ${PORT}
Node name: ${NODE_NAME}
SNI / TLS domain: ${SNI}
EOF

  if [[ "${PROTOCOL}" == "reality" ]]; then
    cat >> "${ARTIFACT_DIR}/README.txt" <<EOF

Reality dest: ${DEST_HOST}:${DEST_PORT}
Public key: ${PUBLIC_KEY}
Short ID: ${SHORT_ID}
EOF
  else
    cat >> "${ARTIFACT_DIR}/README.txt" <<EOF

Fallback: 127.0.0.1:${TROJAN_FALLBACK_PORT}
Certificate renewal: certbot.timer
EOF
  fi

  cat >> "${ARTIFACT_DIR}/README.txt" <<EOF

Generated files:
  ${ARTIFACT_DIR}/${NODE_LINK_NAME}
  ${ARTIFACT_DIR}/${CLASH_YAML_NAME}
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
  sz ${ARTIFACT_DIR}/${NODE_LINK_NAME}
  sz ${ARTIFACT_DIR}/${CLASH_YAML_NAME}
  sz ${ARTIFACT_DIR}/shadowrocket.conf
  sz ${ARTIFACT_DIR}/metadata.json
  sz ${ARTIFACT_DIR}/*

Notes:
  - sz requires a ZMODEM-capable terminal such as Xshell, SecureCRT, or MobaXterm.
  - shadowrocket-node.png is a ${PROTOCOL} QR code for direct Shadowrocket scanning.
  - ${CLASH_YAML_NAME} is intended for Clash Verge, Clash Mi, or Karing, and Clash Verge displays the server address as the profile name.
  - install.sh automatically runs: sz ${ARTIFACT_DIR}/${CLASH_YAML_NAME}
EOF
}

print_summary() {
  log "Installation complete"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
Protocol       : ${PROTOCOL}
Config file    : ${CONFIG_FILE}
Artifact dir   : ${ARTIFACT_DIR}
Cert renewal   : $([[ "${PROTOCOL}" == "trojan" ]] && printf 'certbot.timer' || printf 'not applicable')
Auto sz Clash  : $([[ "${SKIP_SZ}" == "1" ]] && printf 'disabled' || printf 'enabled')
EOF

  if [[ "${PROTOCOL}" == "reality" ]]; then
    printf 'Xray service   : %s\n' "$(systemctl is-active xray)"
    printf 'Auto update    : %s\n' "$([[ "${AUTO_UPDATE_XRAY}" == "1" ]] && printf 'xray-auto-update.timer at %s' "${AUTO_UPDATE_TIME}" || printf 'disabled')"
  else
    printf 'sing-box service: %s\n' "$(systemctl is-active sing-box)"
    printf 'sing-box version: %s\n' "${SING_BOX_VERSION}"
    printf 'Auto update    : disabled; upgrade through a reviewed release\n'
  fi

  cat <<EOF

Node URL file  : ${ARTIFACT_DIR}/${NODE_LINK_NAME}

Quick download:
  sz ${ARTIFACT_DIR}/*
EOF

  if [[ "${SKIP_QR}" != "1" ]] && [[ -f "${ARTIFACT_DIR}/shadowrocket-node.png" ]]; then
    printf 'Shadowrocket QR: %s\n' "${ARTIFACT_DIR}/shadowrocket-node.png"
  fi
}

send_clashverge_yaml() {
  local target
  if [[ -z "${CLASH_YAML_NAME}" && -f "${ARTIFACT_DIR}/metadata.json" ]]; then
    CLASH_YAML_NAME="$(
      python3 - "${ARTIFACT_DIR}/metadata.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh).get("clash_yaml", ""))
PY
    )"
  fi
  if [[ -z "${CLASH_YAML_NAME}" ]]; then
    CLASH_YAML_NAME="${PUBLIC_IP}.yaml"
  fi
  target="${ARTIFACT_DIR}/${CLASH_YAML_NAME}"

  if [[ "${SKIP_SZ}" == "1" ]]; then
    log "Skipping automatic Clash YAML download by request"
    return
  fi

  if [[ ! -f "${target}" ]]; then
    warn "Clash YAML was not found at ${target}; skipping automatic sz download."
    return
  fi

  if ! command_exists sz; then
    warn "sz is not installed; skipping automatic Clash YAML download."
    warn "Install lrzsz or download manually: ${target}"
    return
  fi

  if [[ ! -t 1 ]]; then
    warn "stdout is not a terminal; skipping automatic sz download."
    warn "Download manually later with: sz ${target}"
    return
  fi

  log "Starting automatic download: sz ${target}"
  sz "${target}" || warn "Automatic sz download failed. You can run manually: sz ${target}"
}

print_maintenance_summary() {
  log "Xray maintenance complete"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
Xray service   : $(systemctl is-active xray 2>/dev/null || true)
Xray binary    : ${XRAY_BIN}
Config file    : ${CONFIG_FILE}
Config action  : preserved existing config
Auto update    : $([[ "${AUTO_UPDATE_XRAY}" == "1" ]] && printf 'xray-auto-update.timer at %s' "${AUTO_UPDATE_TIME}" || printf 'disabled')
Auto sz Clash  : $([[ "${SKIP_SZ}" == "1" ]] && printf 'disabled' || printf 'enabled')

Existing Xray config was not replaced.
Re-run with --force-overwrite to generate a new ${PROTOCOL} config and export assets.
EOF
}

print_sing_box_maintenance_summary() {
  log "sing-box maintenance complete"
  cat <<EOF
Script version : ${SCRIPT_VERSION}
sing-box service: $(systemctl is-active sing-box 2>/dev/null || true)
sing-box binary : ${SING_BOX_BIN}
Config file     : ${SING_BOX_CONFIG}
Config action   : preserved existing config
Auto update     : disabled; upgrade through a reviewed release
Auto sz Clash   : $([[ "${SKIP_SZ}" == "1" ]] && printf 'disabled' || printf 'enabled')

Existing sing-box config was not replaced.
Re-run with --force-overwrite to generate a new Trojan TLS config and export assets.
EOF
}

main() {
  parse_args "$@"
  need_root
  detect_os
  detect_existing_nginx
  validate_args
  ensure_defaults
  confirm_plan
  install_dependencies
  ensure_required_commands
  if [[ "${PROTOCOL}" == "trojan" ]] && systemctl is-active --quiet sing-box; then
    SING_BOX_WAS_ACTIVE="1"
  fi
  if [[ "${PROTOCOL}" == "reality" ]]; then
    ensure_xray_run_user
    install_xray
    configure_xray_service_hardening
  else
    ensure_sing_box_run_user
    install_sing_box
    configure_sing_box_service
  fi
  if [[ "${KEEP_EXISTING_CONFIG}" == "1" ]]; then
    if [[ "${PROTOCOL}" == "reality" ]]; then
      secure_existing_xray_config
      configure_xray_auto_update
      print_maintenance_summary
    else
      secure_existing_sing_box_config
      systemctl disable --now xray-auto-update.timer >/dev/null 2>&1 || true
      print_sing_box_maintenance_summary
    fi
    send_clashverge_yaml
    HARDENING_CHANGED="0"
    SING_BOX_CHANGED="0"
    return
  fi
  detect_public_ip
  EXPORT_SERVER="${PUBLIC_IP}"
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    EXPORT_SERVER="${DOMAIN}"
  fi
  check_listen_port_available
  configure_firewall
  if [[ "${PROTOCOL}" == "reality" ]]; then
    validate_reality_target
    generate_reality_material
    write_xray_config
  else
    validate_trojan_domain_dns
    configure_trojan_fallback
    issue_trojan_certificate
    install_trojan_certificates
    generate_trojan_material
    write_trojan_sing_box_config
    configure_trojan_certificate_renewal
    verify_trojan_fallback
  fi
  if [[ "${PROTOCOL}" == "reality" ]]; then
    configure_xray_auto_update
  else
    systemctl disable --now xray-auto-update.timer >/dev/null 2>&1 || true
  fi
  generate_assets
  print_summary
  send_clashverge_yaml
  remove_old_firewall_rule
  if [[ "${PROTOCOL}" == "trojan" ]]; then
    rm -f "${LEGACY_TROJAN_RENEW_HOOK}"
  fi
  CONFIG_REPLACED="0"
  HARDENING_CHANGED="0"
  SING_BOX_CONFIG_REPLACED="0"
  SING_BOX_CHANGED="0"
  SING_BOX_BIN_CHANGED="0"
  XRAY_STOPPED_FOR_TROJAN="0"
}

main "$@"
