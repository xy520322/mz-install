#!/bin/bash
#===============================================================================
#  Marzban 一键安装脚本 v3.0 (最终优化版)
#
#  架构:
#    Nginx :443  — TLS 终结, 反代面板 + WS + gRPC
#    Xray  :2053 — VLESS + TCP + REALITY (独立端口)
#    Xray  :1080 — Shadowsocks
#    Xray  :600x — WS/gRPC 后端 (仅本地, Nginx 反代)
#    MySQL :3306 — 数据库 (仅本地)
#
#  协议: VLESS(REALITY/WS/gRPC), VMess(WS), Trojan(WS), Shadowsocks
#  数据库: MySQL 8.0
#  网络: 全部容器使用 host 网络模式, 避免容器间通信问题
#  系统: Ubuntu 20.04+ / Debian 11+
#===============================================================================

#=========================== 颜色 ===========================#
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
PURPLE='\033[0;35m'
NC='\033[0m'

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

die() { error "$1"; echo ""; echo "查看完整日志: cat ${LOG_FILE}"; exit 1; }

# 安全密码: 仅字母数字, 避免破坏YAML/SQL/URL
generate_password() {
    local len="${1:-24}"
    local result=""
    result=$(cat /dev/urandom 2>/dev/null | tr -dc 'A-Za-z0-9' | fold -w "$len" | head -n 1) || true
    if [[ -z "$result" || ${#result} -lt "$len" ]]; then
        result=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9' | fold -w "$len" | head -n 1) || true
    fi
    if [[ -z "$result" || ${#result} -lt "$len" ]]; then
        result=$(date +%s%N%s | sha256sum | tr -dc 'A-Za-z0-9' | head -c "$len")
    fi
    echo "$result"
}

generate_short_id() {
    openssl rand -hex 8 2>/dev/null || echo "$(date +%s%N | md5sum | head -c 16)"
}

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'BANNER'
 ╔═══════════════════════════════════════════════════════════════╗
 ║        __  __                 _                              ║
 ║       |  \/  | __ _ _ __ ___| |__   __ _ _ __               ║
 ║       | |\/| |/ _` | '__/_  | '_ \ / _` | '_ \             ║
 ║       | |  | | (_| | |  / / | |_) | (_| | | | |            ║
 ║       |_|  |_|\__,_|_| /___||_.__/ \__,_|_| |_|            ║
 ║                                                              ║
 ║    一键安装脚本 v3.0 — MySQL + 全协议 + Nginx 反代            ║
 ╚═══════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

#=========================== 预检 ===========================#
preflight() {
    # Root 检查
    if [[ $EUID -ne 0 ]]; then
        die "请用 root 运行: sudo bash $0"
    fi

    # 系统检查
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID; OS_VER=$VERSION_ID
    else
        die "无法检测操作系统"
    fi
    log "系统: ${OS} ${OS_VER}"

    # IP
    SERVER_IP=$(curl -4s --connect-timeout 5 ifconfig.me 2>/dev/null || \
                curl -4s --connect-timeout 5 icanhazip.com 2>/dev/null || \
                curl -4s --connect-timeout 5 ip.sb 2>/dev/null)
    [[ -z "$SERVER_IP" ]] && die "无法获取公网IP"
    log "服务器IP: ${SERVER_IP}"
}

#=========================== 用户输入 ===========================#
collect_input() {
    echo ""
    echo -e "${WHITE}════════════════════ 配置信息 ════════════════════${NC}"
    echo ""

    # 域名
    while true; do
        read -rp "$(echo -e "${CYAN}请输入域名 (例: panel.example.com): ${NC}")" DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            error "域名不能为空"; continue
        fi
        RESOLVED_IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1)
        if [[ "$RESOLVED_IP" == "$SERVER_IP" ]]; then
            log "域名 ${DOMAIN} → ${SERVER_IP} ✓"
            break
        else
            warn "域名解析到 ${RESOLVED_IP:-无}，服务器是 ${SERVER_IP}"
            read -rp "$(echo -e "${YELLOW}继续? (y/n): ${NC}")" yn
            [[ "$yn" =~ ^[Yy]$ ]] && break
        fi
    done

    # 管理员
    read -rp "$(echo -e "${CYAN}管理员用户名 [admin]: ${NC}")" ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-admin}

    while true; do
        read -rp "$(echo -e "${CYAN}管理员密码 [留空自动生成]: ${NC}")" ADMIN_PASS
        if [[ -z "$ADMIN_PASS" ]]; then
            ADMIN_PASS=$(generate_password 16)
            log "自动生成密码: ${ADMIN_PASS}"
            break
        elif [[ ${#ADMIN_PASS} -ge 6 ]]; then
            break
        else
            error "至少6位"
        fi
    done

    # 面板端口
    read -rp "$(echo -e "${CYAN}面板端口 [8000]: ${NC}")" PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8000}

    # Dashboard 路径
    read -rp "$(echo -e "${CYAN}Dashboard路径 [dashboard]: ${NC}")" DASH_PATH
    DASH_PATH=${DASH_PATH:-dashboard}

    # REALITY
    read -rp "$(echo -e "${CYAN}REALITY伪装域名 [www.google.com]: ${NC}")" REALITY_DEST
    REALITY_DEST=${REALITY_DEST:-www.google.com}

    # 固定参数
    REALITY_PORT=2053
    SS_PORT=1080
    VLESS_WS_PATH="/vlessws"
    VMESS_WS_PATH="/vmessws"
    TROJAN_WS_PATH="/trojanws"
    GRPC_SERVICE="vlessgrpc"
    REALITY_SHORT_ID=$(generate_short_id)

    # MySQL 密码 (纯字母数字, 避免 YAML/SQL 解析问题)
    MYSQL_ROOT_PASS=$(generate_password 24)
    MYSQL_DB="marzban"
    MYSQL_USER="marzban"
    MYSQL_PASS=$(generate_password 24)

    echo ""
    echo -e "${WHITE}════════════════════ 配置确认 ════════════════════${NC}"
    echo -e "  域名:        ${GREEN}${DOMAIN}${NC}"
    echo -e "  管理员:      ${GREEN}${ADMIN_USER}${NC}"
    echo -e "  管理密码:    ${GREEN}${ADMIN_PASS}${NC}"
    echo -e "  面板:        ${GREEN}https://${DOMAIN}/${DASH_PATH}/${NC}"
    echo -e "  数据库:      ${GREEN}MySQL 8.0 (host网络)${NC}"
    echo ""
    echo -e "  ${WHITE}端口分配:${NC}"
    echo -e "    ${CYAN}443${NC}   Nginx TLS  → 面板 + WS + gRPC"
    echo -e "    ${CYAN}${REALITY_PORT}${NC}  Xray       → VLESS + REALITY"
    echo -e "    ${CYAN}${SS_PORT}${NC}  Xray       → Shadowsocks"
    echo ""
    echo -e "  ${WHITE}协议 (共6个):${NC}"
    echo -e "    ${PURPLE}●${NC} VLESS + TCP + REALITY      端口 ${REALITY_PORT}"
    echo -e "    ${PURPLE}●${NC} VLESS + WebSocket + TLS    端口 443  路径 ${VLESS_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} VLESS + gRPC + TLS         端口 443  服务 ${GRPC_SERVICE}"
    echo -e "    ${PURPLE}●${NC} VMess + WebSocket + TLS    端口 443  路径 ${VMESS_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} Trojan + WebSocket + TLS   端口 443  路径 ${TROJAN_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} Shadowsocks + TCP          端口 ${SS_PORT}"
    echo ""
    read -rp "$(echo -e "${YELLOW}确认开始安装? (y/n): ${NC}")" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        error "已取消"
        exit 0
    fi
    log "用户已确认，开始安装..."
}

#=========================== [1] 系统优化 ===========================#
step_optimize() {
    log "[1/13] 系统优化..."

    # BBR
    if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        cat >> /etc/sysctl.conf << 'EOF'

# === Marzban 网络优化 ===
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.ip_forward=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_keepalive_time=300
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
        sysctl -p >> "$LOG_FILE" 2>&1 || true
        log "BBR 已启用"
    else
        log "BBR 已存在"
    fi

    # ulimit
    grep -q "* soft nofile 65535" /etc/security/limits.conf 2>/dev/null || \
        echo -e "* soft nofile 65535\n* hard nofile 65535" >> /etc/security/limits.conf
    ulimit -n 65535 2>/dev/null || true
}

#=========================== [2] 安装依赖 ===========================#
step_deps() {
    log "[2/13] 安装依赖..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >> "$LOG_FILE" 2>&1 || die "apt update 失败"
    apt-get install -y curl wget git unzip jq socat cron dnsutils \
        lsof net-tools ca-certificates gnupg >> "$LOG_FILE" 2>&1 || die "依赖安装失败"
    log "依赖完成"
}

#=========================== [3] Docker ===========================#
step_docker() {
    log "[3/13] 安装 Docker..."
    if ! command -v docker &>/dev/null; then
        curl -fsSL https://get.docker.com | bash >> "$LOG_FILE" 2>&1 || die "Docker 安装失败"
        systemctl enable --now docker >> "$LOG_FILE" 2>&1 || true
    fi
    if ! docker compose version &>/dev/null 2>&1; then
        mkdir -p /usr/local/lib/docker/cli-plugins
        local ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest 2>/dev/null | jq -r .tag_name 2>/dev/null)
        ver=${ver:-v2.29.2}
        curl -SL "https://github.com/docker/compose/releases/download/${ver}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/lib/docker/cli-plugins/docker-compose >> "$LOG_FILE" 2>&1 || die "Compose 安装失败"
        chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
    fi
    log "Docker 就绪"
}

#=========================== [4] Nginx ===========================#
step_nginx_install() {
    log "[4/13] 安装 Nginx..."
    if ! command -v nginx &>/dev/null; then
        apt-get install -y nginx >> "$LOG_FILE" 2>&1 || die "Nginx 安装失败"
    fi
    systemctl stop nginx 2>/dev/null || true
    systemctl enable nginx 2>/dev/null || true
    log "Nginx 就绪"
}

#=========================== [5] SSL ===========================#
step_ssl() {
    log "[5/13] SSL 证书..."

    # 释放 80 端口
    systemctl stop nginx 2>/dev/null || true
    fuser -k 80/tcp 2>/dev/null || true
    sleep 1

    # acme.sh
    if [[ ! -f /root/.acme.sh/acme.sh ]]; then
        curl -sL https://get.acme.sh | sh -s email=acme@"${DOMAIN}" >> "$LOG_FILE" 2>&1 || die "acme.sh 安装失败"
    fi
    source /root/.acme.sh/acme.sh.env 2>/dev/null || true

    mkdir -p "$CERT_DIR"

    # 申请
    /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --keylength ec-256 >> "$LOG_FILE" 2>&1 || {
        warn "Let's Encrypt 失败, 尝试 ZeroSSL..."
        /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force --keylength ec-256 --server zerossl >> "$LOG_FILE" 2>&1 || \
            die "SSL 申请失败! 请确认域名已解析且80端口可达"
    }

    # 安装到指定目录
    /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --ecc \
        --fullchain-file "${CERT_DIR}/fullchain.pem" \
        --key-file "${CERT_DIR}/key.pem" \
        --reloadcmd "nginx -s reload 2>/dev/null || true" >> "$LOG_FILE" 2>&1 || die "证书安装失败"

    chmod 644 "${CERT_DIR}/fullchain.pem"
    chmod 600 "${CERT_DIR}/key.pem"
    log "SSL 证书完成"
}

#=========================== [6] REALITY 密钥 ===========================#
step_reality_keys() {
    log "[6/13] REALITY 密钥..."

    local keys=$(docker run --rm ghcr.io/xtls/xray-core:latest xray x25519 2>/dev/null) || true

    if [[ -n "$keys" ]]; then
        REALITY_PRIV=$(echo "$keys" | grep -i "private" | awk '{print $NF}')
        REALITY_PUB=$(echo "$keys" | grep -i "public" | awk '{print $NF}')
    fi

    if [[ -z "$REALITY_PRIV" || -z "$REALITY_PUB" ]]; then
        warn "自动生成失败，需要手动配置"
        warn "面板启动后执行: docker run --rm ghcr.io/xtls/xray-core:latest xray x25519"
        REALITY_PRIV="YOUR_PRIVATE_KEY"
        REALITY_PUB="YOUR_PUBLIC_KEY"
        REALITY_PLACEHOLDER=true
    else
        log "REALITY 密钥成功"
        REALITY_PLACEHOLDER=false
    fi
}

#=========================== [7] Xray 配置 ===========================#
# 关键: REALITY 用 2053, WS/gRPC 用 6001-6004 本地端口
step_xray_config() {
    log "[7/13] Xray 配置..."
    mkdir -p "$MARZBAN_DATA"

    cat > "$XRAY_CONFIG" << XEOF
{
  "log": { "loglevel": "warning" },
  "api": {
    "tag": "api",
    "services": ["HandlerService", "StatsService", "LoggerService"]
  },
  "stats": {},
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": {
      "statsInboundUplink": true, "statsInboundDownlink": true,
      "statsOutboundUplink": true, "statsOutboundDownlink": true
    }
  },
  "dns": {
    "servers": ["https+local://1.1.1.1/dns-query", "1.1.1.1", "8.8.8.8", "localhost"]
  },
  "inbounds": [
    {
      "tag": "API",
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    },
    {
      "tag": "VLESS-TCP-REALITY",
      "listen": "0.0.0.0",
      "port": ${REALITY_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "tcpSettings": {},
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}:443",
          "xver": 0,
          "serverNames": ["${REALITY_DEST}"],
          "privateKey": "${REALITY_PRIV}",
          "shortIds": ["", "${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VLESS-WS",
      "listen": "127.0.0.1",
      "port": 6001,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "${VLESS_WS_PATH}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VLESS-GRPC",
      "listen": "127.0.0.1",
      "port": 6002,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "grpc", "security": "none",
        "grpcSettings": { "serviceName": "${GRPC_SERVICE}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "VMESS-WS",
      "listen": "127.0.0.1",
      "port": 6003,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "${VMESS_WS_PATH}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "TROJAN-WS",
      "listen": "127.0.0.1",
      "port": 6004,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws", "security": "none",
        "wsSettings": { "path": "${TROJAN_WS_PATH}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    },
    {
      "tag": "SHADOWSOCKS",
      "listen": "0.0.0.0",
      "port": ${SS_PORT},
      "protocol": "shadowsocks",
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

    log "Xray 配置完成 (6入站, REALITY:${REALITY_PORT})"
}

#=========================== [8] Docker Compose ===========================#
# 关键: 全部使用 network_mode: host, 避免容器网络隔离问题
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

    log "Compose 完成 (全 host 网络)"
}

#=========================== [9] .env ===========================#
step_env() {
    log "[9/13] 环境变量..."

    cat > "$ENV_FILE" << EEOF
# Marzban v3.0
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

    chmod 600 "$ENV_FILE"
    log "环境变量完成"
}

#=========================== [10] Nginx ===========================#
# 核心: Nginx 占 443 做 TLS 终结, 反代到各本地端口
step_nginx_config() {
    log "[10/13] Nginx 配置..."

    rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf 2>/dev/null || true

    # 主配置
    cat > /etc/nginx/nginx.conf << 'NEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
worker_rlimit_nofile 65535;

events {
    worker_connections 65535;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 100m;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    include /etc/nginx/conf.d/*.conf;
}
NEOF

    # 站点配置
    cat > "$NGINX_CONF" << SEOF
# HTTP → HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

# HTTPS — Nginx 监听 443 做 TLS 终结
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Dashboard
    location /${DASH_PATH}/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # API + 订阅 + 静态
    location ~ ^/(api|sub|statics|docs|redoc|openapi.json) {
        proxy_pass http://127.0.0.1:${PANEL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # VLESS WebSocket → :6001
    location ${VLESS_WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:6001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # VMess WebSocket → :6003
    location ${VMESS_WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:6003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # Trojan WebSocket → :6004
    location ${TROJAN_WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:6004;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # VLESS gRPC → :6002
    location /${GRPC_SERVICE} {
        grpc_pass grpc://127.0.0.1:6002;
        grpc_set_header Host \$host;
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
    }

    # phpMyAdmin → :8888
    location /phpmyadmin/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }

    # 根路径 → Dashboard
    location / {
        return 301 https://\$host/${DASH_PATH}/;
    }
}
SEOF

    nginx -t >> "$LOG_FILE" 2>&1 || { error "Nginx 配置错误:"; nginx -t 2>&1; die "请检查配置"; }
    log "Nginx 配置完成"
}

#=========================== [11] 防火墙 ===========================#
step_firewall() {
    log "[11/13] 防火墙..."
    if command -v ufw &>/dev/null; then
        for port in 22/tcp 80/tcp 443/tcp ${REALITY_PORT}/tcp ${SS_PORT}/tcp ${SS_PORT}/udp; do
            ufw allow $port >> "$LOG_FILE" 2>&1 || true
        done
        echo "y" | ufw enable >> "$LOG_FILE" 2>&1 || true
        log "UFW 已配置"
    else
        warn "无 UFW，请手动开放: 80 443 ${REALITY_PORT} ${SS_PORT}"
    fi
}

#=========================== [12] 启动服务 ===========================#
step_start() {
    log "[12/13] 启动服务..."
    cd "$MARZBAN_DIR"

    # 拉取镜像
    info "拉取 Docker 镜像 (首次较慢)..."
    docker compose pull >> "$LOG_FILE" 2>&1 || die "镜像拉取失败"

    # ── 启动 MySQL ──
    log "启动 MySQL..."
    docker compose up -d mysql >> "$LOG_FILE" 2>&1 || die "MySQL 容器启动失败"

    info "等待 MySQL 就绪 (首次初始化约30-60秒)..."
    local i=0
    while true; do
        if docker exec marzban-mysql mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SELECT 1" &>/dev/null; then
            break
        fi
        i=$((i + 1))
        [[ $i -ge 90 ]] && { error "MySQL 超时"; docker compose logs --tail=20 mysql 2>&1; die "MySQL 无法启动"; }
        sleep 2
        printf "\r  MySQL 启动中... %d/90" "$i"
    done
    echo ""
    log "MySQL 就绪"

    # 验证数据库
    docker exec marzban-mysql mysql -u root -p"${MYSQL_ROOT_PASS}" -e "
        CREATE DATABASE IF NOT EXISTS ${MYSQL_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
        GRANT ALL PRIVILEGES ON ${MYSQL_DB}.* TO '${MYSQL_USER}'@'%';
        FLUSH PRIVILEGES;
    " >> "$LOG_FILE" 2>&1 || warn "数据库初始化有警告(可能已存在)"

    # 测试应用用户
    if docker exec marzban-mysql mysql -u "${MYSQL_USER}" -p"${MYSQL_PASS}" -e "USE ${MYSQL_DB}; SELECT 1" &>/dev/null; then
        log "数据库用户连接验证通过"
    else
        warn "用户连接失败，重置密码..."
        docker exec marzban-mysql mysql -u root -p"${MYSQL_ROOT_PASS}" -e "
            ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
            FLUSH PRIVILEGES;
        " >> "$LOG_FILE" 2>&1 || true
    fi

    # ── 启动 Marzban ──
    log "启动 Marzban..."
    docker compose up -d marzban >> "$LOG_FILE" 2>&1 || die "Marzban 启动失败"

    info "等待 Marzban 面板响应..."
    i=0
    while true; do
        # 检查容器是否在运行
        local status=$(docker inspect --format='{{.State.Status}}' marzban 2>/dev/null)
        if [[ "$status" == "exited" ]]; then
            warn "Marzban 异常退出，重启中..."
            docker compose logs --tail=5 marzban 2>&1
            docker compose restart marzban >> "$LOG_FILE" 2>&1 || true
        fi
        if curl -sf "http://127.0.0.1:${PANEL_PORT}/${DASH_PATH}/" -o /dev/null 2>/dev/null; then
            break
        fi
        i=$((i + 1))
        [[ $i -ge 40 ]] && { warn "Marzban 仍在初始化, 继续..."; break; }
        sleep 3
        printf "\r  Marzban 启动中... %d/40" "$i"
    done
    echo ""

    # ── 启动 phpMyAdmin ──
    docker compose up -d phpmyadmin >> "$LOG_FILE" 2>&1 || true

    # ── 启动 Nginx ──
    # 关键: 确保 443 端口没被其他进程占用
    sleep 2
    if ss -tlnp 2>/dev/null | grep -q ":443.*xray"; then
        error "443 被 Xray 占用! Xray 配置可能有误"
        die "请检查 ${XRAY_CONFIG} 中 REALITY 端口是否为 ${REALITY_PORT}"
    fi

    log "启动 Nginx..."
    systemctl start nginx >> "$LOG_FILE" 2>&1 || { error "Nginx 启动失败"; systemctl status nginx --no-pager 2>&1; die "Nginx"; }

    log "全部服务启动完成"
}

#=========================== [13] 收尾 ===========================#
step_finalize() {
    log "[13/13] 收尾..."

    # ── 保存安装信息 ──
    cat > "$INFO_FILE" << IEOF
═══════════════════════════════════════════════════
    Marzban 安装信息  $(date '+%Y-%m-%d %H:%M')
═══════════════════════════════════════════════════

面板:       https://${DOMAIN}/${DASH_PATH}/
管理员:     ${ADMIN_USER}
密码:       ${ADMIN_PASS}
phpMyAdmin: https://${DOMAIN}/phpmyadmin/

MySQL:
  Root密码:  ${MYSQL_ROOT_PASS}
  用户:      ${MYSQL_USER}
  密码:      ${MYSQL_PASS}
  数据库:    ${MYSQL_DB}

协议:
  [1] VLESS+REALITY  端口:${REALITY_PORT}  伪装:${REALITY_DEST}
      公钥: ${REALITY_PUB}
      ShortID: ${REALITY_SHORT_ID}
  [2] VLESS+WS+TLS   端口:443  路径:${VLESS_WS_PATH}
  [3] VLESS+gRPC+TLS  端口:443  服务:${GRPC_SERVICE}
  [4] VMess+WS+TLS   端口:443  路径:${VMESS_WS_PATH}
  [5] Trojan+WS+TLS  端口:443  路径:${TROJAN_WS_PATH}
  [6] Shadowsocks    端口:${SS_PORT}

文件:
  配置: /opt/marzban/.env
  Xray: ${XRAY_CONFIG}
  Nginx: ${NGINX_CONF}
  证书: ${CERT_DIR}/
  日志: ${LOG_FILE}

命令: mzb {status|logs|restart|update|backup|info}
IEOF
    chmod 600 "$INFO_FILE"

    # ── 管理脚本 ──
    cat > /usr/local/bin/mzb << 'MZB'
#!/bin/bash
G='\033[0;32m'; Y='\033[0;33m'; C='\033[0;36m'; N='\033[0m'
D="/opt/marzban"
case "$1" in
    start)   cd $D && docker compose up -d; systemctl start nginx ;;
    stop)    cd $D && docker compose down; systemctl stop nginx ;;
    restart) cd $D && docker compose restart; systemctl reload nginx ;;
    status)
        echo -e "${C}容器:${N}"; cd $D && docker compose ps
        echo -e "\n${C}端口:${N}"; ss -tlnp | grep -E ':(80|443|2053|1080|8000|3306|8888) '
        ;;
    logs)    cd $D && docker compose logs -f --tail=100 ${2:-marzban} ;;
    update)  cd $D && docker compose pull && docker compose up -d && echo -e "${G}更新完成${N}" ;;
    backup)
        BD="/root/marzban-backups"; mkdir -p "$BD"; T=$(date +%Y%m%d_%H%M%S)
        P=$(grep 'MYSQL_ROOT_PASSWORD' $D/docker-compose.yml | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
        docker exec marzban-mysql mysqldump -u root -p"$P" marzban > "$BD/db_${T}.sql" 2>/dev/null
        tar -czf "$BD/cfg_${T}.tar.gz" $D/.env /var/lib/marzban/xray_config.json /var/lib/marzban/certs/ 2>/dev/null
        echo -e "${G}备份完成:${N}"; ls -lh "$BD"/*${T}* 2>/dev/null
        ;;
    info)    cat /root/marzban-install-info.txt 2>/dev/null || echo "文件不存在" ;;
    *)       echo "用法: mzb {start|stop|restart|status|logs|update|backup|info}" ;;
esac
MZB
    chmod +x /usr/local/bin/mzb

    # ── 自动备份 (每天03:00) ──
    mkdir -p /root/marzban-backups
    cat > /usr/local/bin/marzban-backup.sh << 'BKS'
#!/bin/bash
BD="/root/marzban-backups"; T=$(date +%Y%m%d_%H%M%S); mkdir -p "$BD"
P=$(grep 'MYSQL_ROOT_PASSWORD' /opt/marzban/docker-compose.yml | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
docker exec marzban-mysql mysqldump -u root -p"$P" marzban > "$BD/db_${T}.sql" 2>/dev/null
tar -czf "$BD/cfg_${T}.tar.gz" /opt/marzban/.env /var/lib/marzban/xray_config.json /var/lib/marzban/certs/ 2>/dev/null
find "$BD" -mtime +7 -delete 2>/dev/null
BKS
    chmod +x /usr/local/bin/marzban-backup.sh
    (crontab -l 2>/dev/null | grep -v "marzban-backup"; echo "0 3 * * * /usr/local/bin/marzban-backup.sh") | crontab -

    # ── 验证 ──
    echo ""
    info "最终验证..."
    sleep 3

    local panel_ok=false nginx_ok=false

    # 本地面板
    local code=$(curl -so /dev/null -w "%{http_code}" "http://127.0.0.1:${PANEL_PORT}/${DASH_PATH}/" 2>/dev/null)
    if [[ "$code" =~ ^(200|301|307|302)$ ]]; then
        log "面板本地: HTTP ${code} ✓"
        panel_ok=true
    else
        warn "面板本地: HTTP ${code}"
    fi

    # HTTPS
    local hcode=$(curl -sko /dev/null -w "%{http_code}" "https://${DOMAIN}/${DASH_PATH}/" 2>/dev/null)
    if [[ "$hcode" =~ ^(200|301|307|302)$ ]]; then
        log "HTTPS: ${hcode} ✓"
        nginx_ok=true
    else
        warn "HTTPS: ${hcode}"
    fi

    # 端口
    echo ""
    info "端口监听:"
    ss -tlnp 2>/dev/null | grep -E ":(80|443|${REALITY_PORT}|${SS_PORT}|${PANEL_PORT}|3306|8888) " | while read line; do
        echo -e "  ${GREEN}✓${NC} $line"
    done

    # ── 完成输出 ──
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   ✅ Marzban 安装完成!                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}面板:${NC}       ${GREEN}https://${DOMAIN}/${DASH_PATH}/${NC}"
    echo -e "  ${WHITE}账号:${NC}       ${GREEN}${ADMIN_USER}${NC}"
    echo -e "  ${WHITE}密码:${NC}       ${GREEN}${ADMIN_PASS}${NC}"
    echo -e "  ${WHITE}phpMyAdmin:${NC} ${GREEN}https://${DOMAIN}/phpmyadmin/${NC}"
    echo ""
    echo -e "  ${WHITE}协议:${NC}"
    echo -e "    ${PURPLE}●${NC} VLESS+REALITY       → 端口 ${CYAN}${REALITY_PORT}${NC}"
    echo -e "    ${PURPLE}●${NC} VLESS+WS+TLS        → 端口 ${CYAN}443${NC}  路径 ${VLESS_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} VLESS+gRPC+TLS      → 端口 ${CYAN}443${NC}  服务 ${GRPC_SERVICE}"
    echo -e "    ${PURPLE}●${NC} VMess+WS+TLS        → 端口 ${CYAN}443${NC}  路径 ${VMESS_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} Trojan+WS+TLS       → 端口 ${CYAN}443${NC}  路径 ${TROJAN_WS_PATH}"
    echo -e "    ${PURPLE}●${NC} Shadowsocks          → 端口 ${CYAN}${SS_PORT}${NC}"
    echo ""
    if [[ "$REALITY_PLACEHOLDER" == "true" ]]; then
        echo -e "  ${RED}⚠ REALITY 密钥需手动配置: 见面板 Core Settings${NC}"
        echo ""
    fi
    echo -e "  ${WHITE}管理:${NC} mzb {status|logs|restart|update|backup|info}"
    echo -e "  ${WHITE}信息:${NC} cat /root/marzban-install-info.txt"
    echo ""
}

#=========================== 卸载 ===========================#
uninstall() {
    print_banner
    echo -e "${RED}⚠ 将删除全部 Marzban 数据和配置!${NC}"
    read -rp "$(echo -e "${RED}输入 YES 确认卸载: ${NC}")" c
    [[ "$c" != "YES" ]] && { echo "已取消"; exit 0; }

    cd /opt/marzban 2>/dev/null && docker compose down -v 2>/dev/null || true
    rm -rf /opt/marzban /var/lib/marzban
    rm -f /etc/nginx/conf.d/marzban.conf /usr/local/bin/mzb /usr/local/bin/marzban-backup.sh "$INFO_FILE"
    systemctl reload nginx 2>/dev/null || true
    (crontab -l 2>/dev/null | grep -v "marzban-backup" | crontab -) 2>/dev/null || true
    log "Marzban 已完全卸载"
}

#=========================== 主流程 ===========================#
main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Marzban Install v3.0 $(date) ===" > "$LOG_FILE"

    print_banner
    preflight
    collect_input

    echo ""
    log "开始安装... (日志: ${LOG_FILE})"
    echo ""

    step_optimize
    step_deps
    step_docker
    step_nginx_install
    step_ssl
    step_reality_keys
    step_xray_config
    step_compose
    step_env
    step_nginx_config
    step_firewall
    step_start
    step_finalize
}

case "${1}" in
    uninstall|remove) uninstall ;;
    *) main ;;
esac
