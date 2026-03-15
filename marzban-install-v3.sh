#!/bin/bash
#===============================================================================
#  Marzban 一键安装脚本 v3.1
#
#  架构:
#    Nginx :443  — TLS 终结, 反代面板 + WS + gRPC
#    Xray  :2053 — VLESS + TCP + REALITY (独立端口)
#    Xray  :1080 — Shadowsocks
#    Xray  :600x — WS/gRPC 后端 (仅本地, Nginx 反代)
#    MySQL :3306 — 数据库 (仅本地)
#
#  修复: REALITY密钥5层降级生成 + 启动后自动检测崩溃修复
#  协议: VLESS(REALITY/WS/gRPC), VMess(WS), Trojan(WS), Shadowsocks
#  网络: 全部容器 host 网络模式
#  系统: Ubuntu 20.04+ / Debian 11+
#===============================================================================

#=========================== 颜色 ===========================#
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; PURPLE='\033[0;35m'; NC='\033[0m'

#=========================== 路径 ===========================#
MARZBAN_DIR="/opt/marzban"
MARZBAN_DATA="/var/lib/marzban"
CERT_DIR="${MARZBAN_DATA}/certs"
MYSQL_DATA="${MARZBAN_DATA}/mysql"
XRAY_CONFIG="${MARZBAN_DATA}/xray_config.json"
ENV_FILE="${MARZBAN_DIR}/.env"
COMPOSE_FILE="${MARZBAN_DIR}/docker-compose.yml"
NGINX_CONF="/etc/nginx/conf.d/marzban.conf"
LOG_FILE="/var/log/marzban-install.log"
INFO_FILE="/root/marzban-install-info.txt"

#=========================== 工具 ===========================#
log()   { echo -e "${GREEN}[✓]${NC} $1"; echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[⚠]${NC} $1"; echo "[$(date '+%H:%M:%S')] WARN: $1" >> "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $1"; echo "[$(date '+%H:%M:%S')] ERROR: $1" >> "$LOG_FILE"; }
info()  { echo -e "${CYAN}[ℹ]${NC} $1"; }
die()   { error "$1"; echo "日志: cat ${LOG_FILE}"; exit 1; }

generate_password() {
    local len="${1:-24}"
    local r=""
    r=$(cat /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | fold -w "$len" | head -n 1) || true
    [[ -z "$r" || ${#r} -lt "$len" ]] && r=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | fold -w "$len" | head -n 1) || true
    [[ -z "$r" || ${#r} -lt "$len" ]] && r=$(date +%s%N%s | sha256sum | tr -dc 'A-Za-z0-9' | head -c "$len")
    echo "$r"
}

generate_short_id() { openssl rand -hex 8 2>/dev/null || echo "$(date +%s%N | md5sum | head -c 16)"; }

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'B'
 ╔═══════════════════════════════════════════════════════════════╗
 ║        __  __                 _                              ║
 ║       |  \/  | __ _ _ __ ___| |__   __ _ _ __               ║
 ║       | |\/| |/ _` | '__/_  | '_ \ / _` | '_ \             ║
 ║       | |  | | (_| | |  / / | |_) | (_| | | | |            ║
 ║       |_|  |_|\__,_|_| /___||_.__/ \__,_|_| |_|            ║
 ║                                                              ║
 ║    一键安装脚本 v3.1 — MySQL + 全协议 + Nginx 反代            ║
 ╚═══════════════════════════════════════════════════════════════╝
B
    echo -e "${NC}"
}

#=========================== 预检 ===========================#
preflight() {
    [[ $EUID -ne 0 ]] && die "请用 root 运行: sudo bash $0"
    [[ -f /etc/os-release ]] && source /etc/os-release || die "无法检测系统"
    log "系统: ${ID} ${VERSION_ID}"

    SERVER_IP=$(curl -4s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -4s --connect-timeout 5 icanhazip.com 2>/dev/null || curl -4s --connect-timeout 5 ip.sb 2>/dev/null)
    [[ -z "$SERVER_IP" ]] && die "无法获取公网IP"
    log "服务器IP: ${SERVER_IP}"
}

#=========================== 用户输入 ===========================#
collect_input() {
    echo ""
    echo -e "${WHITE}════════════════════ 配置信息 ════════════════════${NC}"
    echo ""

    while true; do
        read -rp "$(echo -e "${CYAN}请输入域名 (例: panel.example.com): ${NC}")" DOMAIN
        [[ -z "$DOMAIN" ]] && { error "域名不能为空"; continue; }
        local resolved=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)
        if [[ "$resolved" == "$SERVER_IP" ]]; then
            log "域名 ${DOMAIN} → ${SERVER_IP} ✓"; break
        else
            warn "域名解析到 ${resolved:-无}，服务器是 ${SERVER_IP}"
            read -rp "$(echo -e "${YELLOW}继续? (y/n): ${NC}")" yn; [[ "$yn" =~ ^[Yy]$ ]] && break
        fi
    done

    read -rp "$(echo -e "${CYAN}管理员用户名 [admin]: ${NC}")" ADMIN_USER; ADMIN_USER=${ADMIN_USER:-admin}
    while true; do
        read -rp "$(echo -e "${CYAN}管理员密码 [留空自动生成]: ${NC}")" ADMIN_PASS
        if [[ -z "$ADMIN_PASS" ]]; then ADMIN_PASS=$(generate_password 16); log "自动生成密码: ${ADMIN_PASS}"; break
        elif [[ ${#ADMIN_PASS} -ge 6 ]]; then break
        else error "至少6位"; fi
    done

    read -rp "$(echo -e "${CYAN}面板端口 [8000]: ${NC}")" PANEL_PORT; PANEL_PORT=${PANEL_PORT:-8000}
    read -rp "$(echo -e "${CYAN}Dashboard路径 [dashboard]: ${NC}")" DASH_PATH; DASH_PATH=${DASH_PATH:-dashboard}
    read -rp "$(echo -e "${CYAN}REALITY伪装域名 [www.google.com]: ${NC}")" REALITY_DEST; REALITY_DEST=${REALITY_DEST:-www.google.com}

    # 节点名称自定义
    echo ""
    echo -e "${WHITE}════════════ 线路节点命名 ════════════${NC}"
    info "每个协议可自定义显示名称 (客户端中看到的名字)"
    echo ""
    read -rp "$(echo -e "${CYAN}VLESS+REALITY 节点名 [VLESS-REALITY]: ${NC}")" NAME_REALITY; NAME_REALITY=${NAME_REALITY:-VLESS-REALITY}
    read -rp "$(echo -e "${CYAN}VLESS+WS 节点名 [VLESS-WS]: ${NC}")" NAME_VWS; NAME_VWS=${NAME_VWS:-VLESS-WS}
    read -rp "$(echo -e "${CYAN}VLESS+gRPC 节点名 [VLESS-gRPC]: ${NC}")" NAME_VGRPC; NAME_VGRPC=${NAME_VGRPC:-VLESS-gRPC}
    read -rp "$(echo -e "${CYAN}VMess+WS 节点名 [VMess-WS]: ${NC}")" NAME_VMWS; NAME_VMWS=${NAME_VMWS:-VMess-WS}
    read -rp "$(echo -e "${CYAN}Trojan+WS 节点名 [Trojan-WS]: ${NC}")" NAME_TWS; NAME_TWS=${NAME_TWS:-Trojan-WS}
    read -rp "$(echo -e "${CYAN}Shadowsocks 节点名 [Shadowsocks]: ${NC}")" NAME_SS; NAME_SS=${NAME_SS:-Shadowsocks}

    REALITY_PORT=2053; SS_PORT=1080
    VLESS_WS_PATH="/vlessws"; VMESS_WS_PATH="/vmessws"; TROJAN_WS_PATH="/trojanws"; GRPC_SERVICE="vlessgrpc"
    REALITY_SHORT_ID=$(generate_short_id)
    MYSQL_ROOT_PASS=$(generate_password 24); MYSQL_DB="marzban"; MYSQL_USER="marzban"; MYSQL_PASS=$(generate_password 24)

    echo ""
    echo -e "${WHITE}════════════════════ 配置确认 ════════════════════${NC}"
    echo -e "  域名:        ${GREEN}${DOMAIN}${NC}"
    echo -e "  管理员:      ${GREEN}${ADMIN_USER}${NC} / ${GREEN}${ADMIN_PASS}${NC}"
    echo -e "  面板:        ${GREEN}https://${DOMAIN}/${DASH_PATH}/${NC}"
    echo -e "  数据库:      ${GREEN}MySQL 8.0${NC}"
    echo ""
    echo -e "  ${WHITE}端口:${NC} Nginx:${CYAN}443${NC}  REALITY:${CYAN}${REALITY_PORT}${NC}  SS:${CYAN}${SS_PORT}${NC}"
    echo ""
    echo -e "  ${WHITE}协议:${NC}"
    echo -e "    ${PURPLE}●${NC} ${NAME_REALITY} (${REALITY_PORT})  ${PURPLE}●${NC} ${NAME_VWS} (443)"
    echo -e "    ${PURPLE}●${NC} ${NAME_VGRPC} (443)  ${PURPLE}●${NC} ${NAME_VMWS} (443)"
    echo -e "    ${PURPLE}●${NC} ${NAME_TWS} (443)   ${PURPLE}●${NC} ${NAME_SS} (${SS_PORT})"
    echo ""
    read -rp "$(echo -e "${YELLOW}确认安装? (y/n): ${NC}")" c
    [[ ! "$c" =~ ^[Yy]$ ]] && { error "已取消"; exit 0; }
    log "用户已确认"
}

#=========================== [1] 系统优化 ===========================#
step_optimize() {
    log "[1/13] 系统优化..."
    if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        cat >> /etc/sysctl.conf << 'EOF'

net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.ip_forward=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_tw_reuse=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
        sysctl -p >> "$LOG_FILE" 2>&1 || true; log "BBR 已启用"
    else log "BBR 已存在"; fi
    grep -q "* soft nofile 65535" /etc/security/limits.conf 2>/dev/null || echo -e "* soft nofile 65535\n* hard nofile 65535" >> /etc/security/limits.conf
    ulimit -n 65535 2>/dev/null || true
}

#=========================== [2] 依赖 ===========================#
step_deps() {
    log "[2/13] 安装依赖..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >> "$LOG_FILE" 2>&1 || die "apt update 失败"
    apt-get install -y curl wget git unzip jq socat cron dnsutils lsof net-tools \
        ca-certificates gnupg python3 python3-pip python3-cryptography >> "$LOG_FILE" 2>&1 || {
        warn "部分包安装失败，尝试最小安装..."
        apt-get install -y curl wget git unzip jq socat cron dnsutils lsof net-tools \
            ca-certificates gnupg python3 >> "$LOG_FILE" 2>&1 || die "依赖安装失败"
    }
    log "依赖完成"
}

#=========================== [3] Docker ===========================#
step_docker() {
    log "[3/13] Docker..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1 || die "Docker 安装失败"
        systemctl enable --now docker >> "$LOG_FILE" 2>&1 || true
    fi
    if ! docker compose version &>/dev/null 2>&1; then
        mkdir -p /usr/local/lib/docker/cli-plugins
        local ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null | jq -r .tag_name 2>/dev/null); ver=${ver:-v2.29.2}
        curl -SL "https://github.com/docker/compose/releases/download/${ver}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose >> "$LOG_FILE" 2>&1 || die "Compose 安装失败"
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi
    log "Docker 就绪"
}

#=========================== [4] Nginx ===========================#
step_nginx_install() {
    log "[4/13] Nginx..."
    command -v nginx &>/dev/null || apt-get install -y nginx >> "$LOG_FILE" 2>&1 || die "Nginx 安装失败"
    systemctl stop nginx 2>/dev/null || true; systemctl enable nginx 2>/dev/null || true
    log "Nginx 就绪"
}

#=========================== [5] SSL ===========================#
step_ssl() {
    log "[5/13] SSL 证书..."
    systemctl stop nginx 2>/dev/null || true; fuser -k 80/tcp 2>/dev/null || true; sleep 1
    [[ ! -f /root/.acme.sh/acme.sh ]] && { curl -sL https://get.acme.sh | sh -s email=acme@"${DOMAIN}" >> "$LOG_FILE" 2>&1 || die "acme.sh 安装失败"; }
    source /root/.acme.sh/acme.sh.env 2>/dev/null || true
    mkdir -p "$CERT_DIR"
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --keylength ec-256 >> "$LOG_FILE" 2>&1 || {
        warn "LE 失败, 尝试 ZeroSSL..."
        /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --keylength ec-256 --server zerossl >> "$LOG_FILE" 2>&1 || die "SSL 申请失败"
    }
    /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
        --fullchain-file "${CERT_DIR}/fullchain.pem" --key-file "${CERT_DIR}/key.pem" \
        --reloadcmd "nginx -s reload 2>/dev/null || true" >> "$LOG_FILE" 2>&1 || die "证书安装失败"
    chmod 644 "${CERT_DIR}/fullchain.pem"; chmod 600 "${CERT_DIR}/key.pem"
    log "SSL 完成"
}

#=========================== [6] REALITY 密钥 (5层降级) ===========================#
# 顺序: 先本地Python(最快) → pip安装 → xray二进制 → Docker(可能卡住所以放最后)
_parse_py_keys() {
    local output="$1"
    [[ -z "$output" ]] && return 1
    local p=$(echo "$output" | grep "^PK:" | cut -d: -f2)
    local u=$(echo "$output" | grep "^PU:" | cut -d: -f2)
    [[ -n "$p" && -n "$u" ]] && REALITY_PRIV="$p" && REALITY_PUB="$u" && return 0
    return 1
}

_py_gen_code='
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from base64 import urlsafe_b64encode
k=X25519PrivateKey.generate()
print("PK:"+urlsafe_b64encode(k.private_bytes_raw()).decode().rstrip("="))
print("PU:"+urlsafe_b64encode(k.public_key().public_bytes_raw()).decode().rstrip("="))
'

step_reality_keys() {
    log "[6/13] REALITY 密钥生成..."
    REALITY_PRIV=""; REALITY_PUB=""

    # 方法1 (最快): 系统已有 Python cryptography
    info "方法1: 系统 Python cryptography..."
    local keys=$(python3 -c "$_py_gen_code" 2>/dev/null) || true
    _parse_py_keys "$keys" && { log "方法1 成功"; return 0; }

    # 方法2: pip 安装 cryptography 再生成
    info "方法2: pip install cryptography..."
    pip3 install cryptography --break-system-packages -q >> "$LOG_FILE" 2>&1 || \
    pip3 install cryptography -q >> "$LOG_FILE" 2>&1 || true
    keys=$(python3 -c "$_py_gen_code" 2>/dev/null) || true
    _parse_py_keys "$keys" && { log "方法2 成功"; return 0; }

    # 方法3: apt 安装 python3-cryptography
    info "方法3: apt install python3-cryptography..."
    apt-get install -y python3-cryptography >> "$LOG_FILE" 2>&1 || true
    keys=$(python3 -c "$_py_gen_code" 2>/dev/null) || true
    _parse_py_keys "$keys" && { log "方法3 成功"; return 0; }

    # 方法4: 下载 xray 二进制
    info "方法4: 下载 xray 二进制..."
    local xtmp="/tmp/xray-keygen"
    mkdir -p "$xtmp"
    if curl -sL --connect-timeout 10 --max-time 30 \
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
        -o "$xtmp/xray.zip" 2>/dev/null; then
        if unzip -qo "$xtmp/xray.zip" -d "$xtmp" 2>/dev/null; then
            chmod +x "$xtmp/xray" 2>/dev/null || true
            keys=$("$xtmp/xray" x25519 2>/dev/null) || true
            if [[ -n "$keys" ]] && echo "$keys" | grep -qi "private"; then
                REALITY_PRIV=$(echo "$keys" | grep -i "private" | awk '{print $NF}')
                REALITY_PUB=$(echo "$keys" | grep -i "public" | awk '{print $NF}')
            fi
        fi
    fi
    rm -rf "$xtmp" 2>/dev/null
    [[ -n "$REALITY_PRIV" ]] && { log "方法4 成功"; return 0; }

    # 方法5: Docker (加超时，防卡住)
    info "方法5: Docker xray x25519 (15秒超时)..."
    keys=$(timeout 15 docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 2>/dev/null) || true
    if [[ -n "$keys" ]] && echo "$keys" | grep -qi "private"; then
        REALITY_PRIV=$(echo "$keys" | grep -i "private" | awk '{print $NF}')
        REALITY_PUB=$(echo "$keys" | grep -i "public" | awk '{print $NF}')
        log "方法5 成功"; return 0
    fi

    # 全部失败
    if [[ -z "$REALITY_PRIV" || -z "$REALITY_PUB" ]]; then
        die "REALITY 密钥生成失败! 请手动执行: pip3 install cryptography && python3 -c \"$_py_gen_code\""
    fi
}

#=========================== [7] Xray 配置 ===========================#
step_xray_config() {
    log "[7/13] Xray 配置..."
    mkdir -p "$MARZBAN_DATA"

    cat > "$XRAY_CONFIG" << XEOF
{
  "log": { "loglevel": "warning" },
  "api": { "tag": "api", "services": ["HandlerService", "StatsService", "LoggerService"] },
  "stats": {},
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true, "statsOutboundUplink": true, "statsOutboundDownlink": true }
  },
  "dns": { "servers": ["https+local://1.1.1.1/dns-query", "1.1.1.1", "8.8.8.8", "localhost"] },
  "inbounds": [
    { "tag": "API", "listen": "127.0.0.1", "port": 62789, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1" } },
    {
      "tag": "VLESS-TCP-REALITY", "listen": "0.0.0.0", "port": ${REALITY_PORT}, "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "tcpSettings": {},
        "security": "reality",
        "realitySettings": {
          "show": false, "dest": "${REALITY_DEST}:443", "xver": 0,
          "serverNames": ["${REALITY_DEST}"],
          "privateKey": "${REALITY_PRIV}",
          "shortIds": ["", "${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VLESS-WS", "listen": "127.0.0.1", "port": 6001, "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${VLESS_WS_PATH}" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VLESS-GRPC", "listen": "127.0.0.1", "port": 6002, "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "grpc", "security": "none", "grpcSettings": { "serviceName": "${GRPC_SERVICE}" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VMESS-WS", "listen": "127.0.0.1", "port": 6003, "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${VMESS_WS_PATH}" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "TROJAN-WS", "listen": "127.0.0.1", "port": 6004, "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "security": "none", "wsSettings": { "path": "${TROJAN_WS_PATH}" } },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "SHADOWSOCKS", "listen": "0.0.0.0", "port": ${SS_PORT}, "protocol": "shadowsocks",
      "settings": { "clients": [], "network": "tcp,udp" },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } },
    { "tag": "blackhole", "protocol": "blackhole", "settings": {} }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "inboundTag": ["API"], "outboundTag": "api" },
      { "type": "field", "outboundTag": "blackhole", "ip": ["geoip:private"] },
      { "type": "field", "outboundTag": "blackhole", "protocol": ["bittorrent"] }
    ]
  }
}
XEOF
    log "Xray 配置完成 (REALITY:${REALITY_PORT})"
}

#=========================== [8] Docker Compose ===========================#
step_compose() {
    log "[8/13] Docker Compose..."
    mkdir -p "$MARZBAN_DIR" "$MYSQL_DATA"

    cat > "$COMPOSE_FILE" << DEOF
services:
  mysql:
    image: mysql:8.0
    container_name: marzban-mysql
    restart: always
    network_mode: host
    environment:
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASS}"
      MYSQL_DATABASE: "${MYSQL_DB}"
      MYSQL_USER: "${MYSQL_USER}"
      MYSQL_PASSWORD: "${MYSQL_PASS}"
    command:
      - --bind-address=127.0.0.1
      - --port=3306
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --max-connections=256
      - --default-authentication-plugin=mysql_native_password
    volumes:
      - ${MYSQL_DATA}:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "root", "-p${MYSQL_ROOT_PASS}"]
      interval: 5s
      timeout: 5s
      retries: 30
      start_period: 60s

  marzban:
    image: gozargah/marzban:latest
    container_name: marzban
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - ${MARZBAN_DATA}:/var/lib/marzban
    depends_on:
      mysql:
        condition: service_healthy

  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: marzban-phpmyadmin
    restart: always
    network_mode: host
    environment:
      PMA_HOST: 127.0.0.1
      PMA_PORT: 3306
      APACHE_PORT: 8888
      MYSQL_ROOT_PASSWORD: "${MYSQL_ROOT_PASS}"
DEOF
    log "Compose 完成"
}

#=========================== [9] .env ===========================#
step_env() {
    log "[9/13] 环境变量..."
    cat > "$ENV_FILE" << EEOF
SUDO_USERNAME=${ADMIN_USER}
SUDO_PASSWORD=${ADMIN_PASS}
UVICORN_HOST=0.0.0.0
UVICORN_PORT=${PANEL_PORT}
DASHBOARD_PATH=/${DASH_PATH}/
SQLALCHEMY_DATABASE_URL=mysql+pymysql://${MYSQL_USER}:${MYSQL_PASS}@127.0.0.1:3306/${MYSQL_DB}
XRAY_JSON=${XRAY_CONFIG}
XRAY_EXECUTABLE_PATH=/usr/local/bin/xray
XRAY_SUBSCRIPTION_URL=https://${DOMAIN}
SUB_PROFILE_TITLE=Marzban
SUB_UPDATE_INTERVAL=12
DOCS=true
DEBUG=false
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=1440
EEOF
    chmod 600 "$ENV_FILE"; log "环境变量完成"
}

#=========================== [10] Nginx ===========================#
step_nginx_config() {
    log "[10/13] Nginx 配置..."
    rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf 2>/dev/null || true

    cat > /etc/nginx/nginx.conf << 'N'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
worker_rlimit_nofile 65535;
events { worker_connections 65535; multi_accept on; }
http {
    sendfile on; tcp_nopush on; tcp_nodelay on;
    keepalive_timeout 65; types_hash_max_size 2048;
    server_tokens off; client_max_body_size 100m;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on; gzip_vary on; gzip_proxied any; gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    include /etc/nginx/conf.d/*.conf;
}
N

    cat > "$NGINX_CONF" << SEOF
server {
    listen 80; listen [::]:80; server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
server {
    listen 443 ssl http2; listen [::]:443 ssl http2; server_name ${DOMAIN};
    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m; ssl_session_timeout 1d; ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=63072000" always;

    location /${DASH_PATH}/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https;
    }
    location ~ ^/(api|sub|statics|docs|redoc|openapi.json) {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto https;
    }
    location ${VLESS_WS_PATH} {
        proxy_redirect off; proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade"; proxy_set_header Host \$host;
        proxy_read_timeout 300s; proxy_send_timeout 300s;
    }
    location ${VMESS_WS_PATH} {
        proxy_redirect off; proxy_pass http://127.0.0.1:6003;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade"; proxy_set_header Host \$host;
        proxy_read_timeout 300s; proxy_send_timeout 300s;
    }
    location ${TROJAN_WS_PATH} {
        proxy_redirect off; proxy_pass http://127.0.0.1:6004;
        proxy_http_version 1.1; proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade"; proxy_set_header Host \$host;
        proxy_read_timeout 300s; proxy_send_timeout 300s;
    }
    location /${GRPC_SERVICE} {
        grpc_pass grpc://127.0.0.1:6002; grpc_set_header Host \$host;
        grpc_read_timeout 300s; grpc_send_timeout 300s;
    }
    location /phpmyadmin/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
    location / { return 301 https://\$host/${DASH_PATH}/; }
}
SEOF
    nginx -t >> "$LOG_FILE" 2>&1 || { nginx -t 2>&1; die "Nginx 配置错误"; }
    log "Nginx 配置完成"
}

#=========================== [11] 防火墙 ===========================#
step_firewall() {
    log "[11/13] 防火墙..."
    if command -v ufw &>/dev/null; then
        for p in 22/tcp 80/tcp 443/tcp ${REALITY_PORT}/tcp ${SS_PORT}/tcp ${SS_PORT}/udp; do ufw allow $p >> "$LOG_FILE" 2>&1 || true; done
        echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || true; log "UFW 已配置"
    else warn "无 UFW"; fi
}

#=========================== [12] 启动 + 自动修复 ===========================#
step_start() {
    log "[12/13] 启动服务..."
    cd "$MARZBAN_DIR"

    info "拉取镜像..."
    docker compose pull >> "$LOG_FILE" 2>&1 || die "镜像拉取失败"

    # MySQL
    log "启动 MySQL..."
    docker compose up -d mysql >> "$LOG_FILE" 2>&1 || die "MySQL 启动失败"
    info "等待 MySQL..."
    local i=0
    while true; do
        docker exec marzban-mysql mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT 1" &>/dev/null && break
        i=$((i + 1)); [[ $i -ge 90 ]] && die "MySQL 超时"
        sleep 2; printf "\r  MySQL... %d/90" "$i"
    done; echo ""; log "MySQL 就绪"

    docker exec marzban-mysql mysql -u root -p"${MYSQL_ROOT_PASS}" -e "
        CREATE DATABASE IF NOT EXISTS ${MYSQL_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
        GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'%'; FLUSH PRIVILEGES;
    " >> "$LOG_FILE" 2>&1 || true

    # Marzban
    log "启动 Marzban..."
    docker compose up -d marzban >> "$LOG_FILE" 2>&1 || die "Marzban 启动失败"

    # ── 关键: 等待并检测崩溃，自动修复 REALITY 密钥 ──
    info "等待 Marzban (含自动崩溃修复)..."
    i=0
    local crash_fixed=false
    while true; do
        local status=$(docker inspect --format='{{.State.Status}}' marzban 2>/dev/null)

        # 如果已退出且未修复过 → 检查是否是 REALITY 密钥问题
        if [[ "$status" == "exited" && "$crash_fixed" == "false" ]]; then
            local last_log=$(docker compose logs --tail=5 marzban 2>&1)
            if echo "$last_log" | grep -q "x25519\|public_key\|NoneType\|privateKey"; then
                warn "检测到 REALITY 密钥导致崩溃，自动修复..."

                # 用 Marzban 容器内的 Python 生成密钥
                local new_keys=$(docker run --rm gozargah/marzban:latest python3 -c "
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from base64 import urlsafe_b64encode
k=X25519PrivateKey.generate()
print(urlsafe_b64encode(k.private_bytes_raw()).decode().rstrip('='))
print(urlsafe_b64encode(k.public_key().public_bytes_raw()).decode().rstrip('='))
" 2>/dev/null) || true

                if [[ -n "$new_keys" ]]; then
                    local new_priv=$(echo "$new_keys" | head -1)
                    local new_pub=$(echo "$new_keys" | tail -1)

                    # 替换配置文件中的密钥
                    python3 -c "
import json
with open('${XRAY_CONFIG}', 'r') as f:
    cfg = json.load(f)
for ib in cfg.get('inbounds', []):
    rs = ib.get('streamSettings', {}).get('realitySettings')
    if rs:
        rs['privateKey'] = '${new_priv}'
with open('${XRAY_CONFIG}', 'w') as f:
    json.dump(cfg, f, indent=2)
print('OK')
" 2>/dev/null

                    REALITY_PRIV="$new_priv"
                    REALITY_PUB="$new_pub"
                    crash_fixed=true
                    log "REALITY 密钥已自动修复: ${new_pub:0:10}..."
                    docker compose restart marzban >> "$LOG_FILE" 2>&1 || true
                else
                    warn "容器内 Python 生成密钥也失败"
                fi
            else
                warn "Marzban 退出但非密钥问题，重启..."
                docker compose restart marzban >> "$LOG_FILE" 2>&1 || true
            fi
        fi

        if curl -sf "http://127.0.0.1:${PANEL_PORT}/${DASH_PATH}/" -o /dev/null 2>/dev/null; then
            break
        fi
        i=$((i + 1)); [[ $i -ge 60 ]] && { warn "Marzban 仍在初始化..."; break; }
        sleep 3; printf "\r  Marzban... %d/60" "$i"
    done; echo ""

    # 最终确认面板可访问
    local code=$(curl -so /dev/null -w "%{http_code}" "http://127.0.0.1:${PANEL_PORT}/${DASH_PATH}/" 2>/dev/null)
    if [[ "$code" =~ ^(200|301|302|307)$ ]]; then
        log "Marzban 面板运行正常 (HTTP ${code})"
    else
        warn "面板返回 HTTP ${code}，可能仍在启动"
        info "查看日志: cd /opt/marzban && docker compose logs -f marzban"
    fi

    # phpMyAdmin
    docker compose up -d phpmyadmin >> "$LOG_FILE" 2>&1 || true

    # Nginx
    sleep 2
    if ss -tlnp 2>/dev/null | grep -q ":443.*xray"; then
        die "443 被 Xray 占用! 检查 REALITY 端口"
    fi
    log "启动 Nginx..."
    systemctl start nginx >> "$LOG_FILE" 2>&1 || die "Nginx 启动失败"

    log "全部服务启动完成"
}

#=========================== [13] API自动配置Host ===========================#
step_auto_hosts() {
    log "[13/14] 自动配置 Host..."

    # 等待面板API可用 (用实际获取token来检测，而不是GET请求)
    local token=""
    info "等待 API 就绪..."
    for i in $(seq 1 30); do
        local resp=$(curl -s "http://127.0.0.1:${PANEL_PORT}/api/admin/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=${ADMIN_USER}&password=${ADMIN_PASS}" 2>/dev/null)
        token=$(echo "$resp" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null) || true
        if [[ -n "$token" && "$token" != "" ]]; then
            break
        fi
        sleep 3; printf "\r  等待API... %d/30" "$i"
    done; echo ""

    if [[ -z "$token" ]]; then
        warn "API Token 获取失败，跳过自动配置 Host"
        warn "请手动在面板 → 设置 → Host Settings 中配置"
        return 0
    fi
    log "API Token 获取成功"

    # 构建并发送 Host 配置 (直接用 curl + JSON, 已验证有效)
    log "配置 Host..."
    local resp=$(curl -s "http://127.0.0.1:${PANEL_PORT}/api/hosts" \
        -X PUT \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{
  "VLESS-TCP-REALITY": [{"remark":"'"${NAME_REALITY}"'","address":"'"${SERVER_IP}"'","port":'"${REALITY_PORT}"',"sni":"'"${REALITY_DEST}"'","host":"","path":"","security":"inbound_default","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}],
  "VLESS-WS": [{"remark":"'"${NAME_VWS}"'","address":"'"${DOMAIN}"'","port":443,"sni":"'"${DOMAIN}"'","host":"'"${DOMAIN}"'","path":"'"${VLESS_WS_PATH}"'","security":"tls","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}],
  "VLESS-GRPC": [{"remark":"'"${NAME_VGRPC}"'","address":"'"${DOMAIN}"'","port":443,"sni":"'"${DOMAIN}"'","host":"'"${DOMAIN}"'","path":"'"${GRPC_SERVICE}"'","security":"tls","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}],
  "VMESS-WS": [{"remark":"'"${NAME_VMWS}"'","address":"'"${DOMAIN}"'","port":443,"sni":"'"${DOMAIN}"'","host":"'"${DOMAIN}"'","path":"'"${VMESS_WS_PATH}"'","security":"tls","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}],
  "TROJAN-WS": [{"remark":"'"${NAME_TWS}"'","address":"'"${DOMAIN}"'","port":443,"sni":"'"${DOMAIN}"'","host":"'"${DOMAIN}"'","path":"'"${TROJAN_WS_PATH}"'","security":"tls","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}],
  "SHADOWSOCKS": [{"remark":"'"${NAME_SS}"'","address":"'"${SERVER_IP}"'","port":'"${SS_PORT}"',"sni":"","host":"","path":"","security":"inbound_default","alpn":"","fingerprint":"","is_disabled":false,"mux_enable":false,"fragment_setting":"","noise_setting":"","random_user_agent":false}]
}' 2>/dev/null)

    # 检查结果
    if echo "$resp" | python3 -c "import sys,json;d=json.load(sys.stdin);assert 'VLESS-WS' in d" 2>/dev/null; then
        log "Host 自动配置成功!"
        log "  ${NAME_REALITY} → ${SERVER_IP}:${REALITY_PORT} (REALITY)"
        log "  ${NAME_VWS} → ${DOMAIN}:443 (WS+TLS)"
        log "  ${NAME_VGRPC} → ${DOMAIN}:443 (gRPC+TLS)"
        log "  ${NAME_VMWS} → ${DOMAIN}:443 (WS+TLS)"
        log "  ${NAME_TWS} → ${DOMAIN}:443 (WS+TLS)"
        log "  ${NAME_SS} → ${SERVER_IP}:${SS_PORT}"
    else
        warn "Host 配置返回异常，请在面板中手动检查"
        warn "响应: $(echo "$resp" | head -c 200)"
    fi
}
#=========================== [14] 收尾 ===========================#
step_finalize() {
    log "[14/14] 收尾..."

    cat > "$INFO_FILE" << IEOF
═══════════════════════════════════════════════
    Marzban 安装信息  $(date '+%Y-%m-%d %H:%M')
═══════════════════════════════════════════════
面板:       https://${DOMAIN}/${DASH_PATH}/
管理员:     ${ADMIN_USER}
密码:       ${ADMIN_PASS}
phpMyAdmin: https://${DOMAIN}/phpmyadmin/

MySQL Root:  ${MYSQL_ROOT_PASS}
MySQL User:  ${MYSQL_USER} / ${MYSQL_PASS}

协议:
  VLESS+REALITY  端口:${REALITY_PORT}  伪装:${REALITY_DEST}
    公钥: ${REALITY_PUB}
    ShortID: ${REALITY_SHORT_ID}
  VLESS+WS+TLS   端口:443  路径:${VLESS_WS_PATH}
  VLESS+gRPC+TLS  端口:443  服务:${GRPC_SERVICE}
  VMess+WS+TLS   端口:443  路径:${VMESS_WS_PATH}
  Trojan+WS+TLS  端口:443  路径:${TROJAN_WS_PATH}
  Shadowsocks    端口:${SS_PORT}

命令: mzb {status|logs|restart|update|backup|info}
IEOF
    chmod 600 "$INFO_FILE"

    cat > /usr/local/bin/mzb << 'M'
#!/bin/bash
G='\033[0;32m';C='\033[0;36m';N='\033[0m';D="/opt/marzban"
case "$1" in
start)cd $D&&docker compose up -d;systemctl start nginx;;
stop)cd $D&&docker compose down;systemctl stop nginx;;
restart)cd $D&&docker compose restart;systemctl reload nginx;;
status)echo -e "${C}容器:${N}";cd $D&&docker compose ps;echo -e "\n${C}端口:${N}";ss -tlnp|grep -E ':(80|443|2053|1080|8000|3306|8888) ';;
logs)cd $D&&docker compose logs -f --tail=100 ${2:-marzban};;
update)cd $D&&docker compose pull&&docker compose up -d;;
backup)BD="/root/marzban-backups";mkdir -p "$BD";T=$(date +%Y%m%d_%H%M%S);P=$(grep MYSQL_ROOT_PASSWORD $D/docker-compose.yml|head -1|sed 's/.*: *"\([^"]*\)".*/\1/');docker exec marzban-mysql mysqldump -u root -p"$P" marzban>"$BD/db_${T}.sql" 2>/dev/null;tar -czf "$BD/cfg_${T}.tar.gz" $D/.env /var/lib/marzban/xray_config.json /var/lib/marzban/certs/ 2>/dev/null;echo -e "${G}备份完成${N}";ls -lh "$BD"/*${T}*;;
info)cat /root/marzban-install-info.txt 2>/dev/null||echo "文件不存在";;
*)echo "用法: mzb {start|stop|restart|status|logs|update|backup|info}";;
esac
M
    chmod +x /usr/local/bin/mzb

    mkdir -p /root/marzban-backups
    cat > /usr/local/bin/marzban-backup.sh << 'B'
#!/bin/bash
BD="/root/marzban-backups";T=$(date +%Y%m%d_%H%M%S);mkdir -p "$BD"
P=$(grep MYSQL_ROOT_PASSWORD /opt/marzban/docker-compose.yml|head -1|sed 's/.*: *"\([^"]*\)".*/\1/')
docker exec marzban-mysql mysqldump -u root -p"$P" marzban>"$BD/db_${T}.sql" 2>/dev/null
tar -czf "$BD/cfg_${T}.tar.gz" /opt/marzban/.env /var/lib/marzban/xray_config.json /var/lib/marzban/certs/ 2>/dev/null
find "$BD" -mtime +7 -delete 2>/dev/null
B
    chmod +x /usr/local/bin/marzban-backup.sh
    (crontab -l 2>/dev/null|grep -v marzban-backup;echo "0 3 * * * /usr/local/bin/marzban-backup.sh")|crontab -

    # 最终验证
    echo ""; info "最终验证..."; sleep 3
    local hcode=$(curl -sko /dev/null -w "%{http_code}" "https://${DOMAIN}/${DASH_PATH}/" 2>/dev/null)
    echo ""; info "端口:"
    ss -tlnp 2>/dev/null | grep -E ":(80|443|${REALITY_PORT}|${SS_PORT}|${PANEL_PORT}|3306|8888) " | while read l; do echo -e "  ${GREEN}✓${NC} $l"; done

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   ✅ Marzban 安装完成!                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}面板:${NC}       ${GREEN}https://${DOMAIN}/${DASH_PATH}/${NC}"
    echo -e "  ${WHITE}账号:${NC}       ${GREEN}${ADMIN_USER}${NC}"
    echo -e "  ${WHITE}密码:${NC}       ${GREEN}${ADMIN_PASS}${NC}"
    echo -e "  ${WHITE}phpMyAdmin:${NC} ${GREEN}https://${DOMAIN}/phpmyadmin/${NC}"
    echo -e "  ${WHITE}HTTPS:${NC}      ${GREEN}${hcode}${NC}"
    echo ""
    echo -e "  ${WHITE}协议 (Host已自动配置):${NC}"
    echo -e "    ${PURPLE}●${NC} ${NAME_REALITY} → ${CYAN}${REALITY_PORT}${NC}  ${PURPLE}●${NC} ${NAME_VWS} → ${CYAN}443${NC}"
    echo -e "    ${PURPLE}●${NC} ${NAME_VGRPC} → ${CYAN}443${NC}     ${PURPLE}●${NC} ${NAME_VMWS} → ${CYAN}443${NC}"
    echo -e "    ${PURPLE}●${NC} ${NAME_TWS} → ${CYAN}443${NC}     ${PURPLE}●${NC} ${NAME_SS} → ${CYAN}${SS_PORT}${NC}"
    echo ""
    echo -e "  ${WHITE}管理:${NC} mzb {status|logs|restart|update|backup|info}"
    echo -e "  ${WHITE}信息:${NC} cat /root/marzban-install-info.txt"
    echo ""
}

#=========================== 卸载 ===========================#
uninstall() {
    print_banner
    echo -e "${RED}⚠ 删除全部数据!${NC}"
    read -rp "$(echo -e "${RED}输入 YES: ${NC}")" c; [[ "$c" != "YES" ]] && { echo "取消"; exit 0; }
    cd /opt/marzban 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -rf /opt/marzban /var/lib/marzban
    rm -f /etc/nginx/conf.d/marzban.conf /usr/local/bin/mzb /usr/local/bin/marzban-backup.sh "$INFO_FILE"
    systemctl reload nginx 2>/dev/null || true
    (crontab -l 2>/dev/null|grep -v marzban-backup|crontab -) 2>/dev/null || true
    log "已卸载"
}

#=========================== 主流程 ===========================#
main() {
    mkdir -p "$(dirname "$LOG_FILE")"; echo "=== Marzban v3.1 $(date) ===" > "$LOG_FILE"
    print_banner; preflight; collect_input
    echo ""; log "开始安装..."; echo ""
    step_optimize; step_deps; step_docker; step_nginx_install; step_ssl
    step_reality_keys; step_xray_config; step_compose; step_env
    step_nginx_config; step_firewall; step_start; step_auto_hosts; step_finalize
}

case "${1}" in uninstall|remove) uninstall ;; *) main ;; esac
