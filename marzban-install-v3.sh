#!/usr/bin/env bash
# ============================================================
#  Marzban 一键安装管理脚本  v6
#
#  菜单:
#    1 - 安装 Marzban 面板
#    2 - 安装 Marzban-Node 节点
#    3 - 修改 REALITY 伪装域名
#    4 - 诊断/修复 面板
#    5 - 诊断/修复 节点
#    6 - 安装 IP 限制器 + 面板UI插件（含备注显示）
#    7 - 安装 IP 限制器管理面板（Web可视化）
#    8 - 安装 Clash 分流规则 + Nginx UA 自动识别
#    0 - 退出
#
#  集成的所有修复:
#    ✔ REALITY flow=xtls-rprx-vision
#    ✔ TLS allowinsecure=True
#    ✔ SERVICE_PROTOCOL=rest（节点HTTP模式）
#    ✔ 节点证书同步到 /var/lib/marzban/certs/
#    ✔ 日志目录提前创建
#    ✔ /var/lib/marzban 挂载到节点容器
#    ✔ Hosts 追加模式 + 清除垃圾条目
#    ✔ 节点看门狗（每5分钟自动重连）
#    ✔ IP限制器 do_POST 修复（纯文本/JSON分开处理）
#    ✔ 日志正则修复（兼容 from IP 格式）
#    ✔ 节点日志推送 systemd 服务
#    ✔ 用户名下方备注显示（浮动层，不影响流量统计条）
#    ✔ IP限制器 Web 管理面板（选项7，独立鉴权）
#    ✔ Clash 分流规则自动部署（选项8，Semporia规则集）
# ============================================================

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; W='\033[1;37m'
DIM='\033[2m'; BOLD='\033[1m'; NC='\033[0m'

log_ok()   { echo -e "  ${G}✔${NC}  $1"; }
log_warn() { echo -e "  ${Y}⚠${NC}  $1"; }
log_err()  { echo -e "  ${R}✘${NC}  $1"; }
log_info() { echo -e "  ${C}➜${NC}  $1"; }
log_step() { echo -e "\n${B}┌─ ${W}$1 ${B}────────────────────────────${NC}"; }
die()      { echo -e "\n${R}FATAL: $1${NC}\n"; exit 1; }

show_banner() {
  clear
  echo -e "${B}"
  cat << 'BANNER'
 ███╗   ███╗ █████╗ ██████╗ ███████╗██████╗  █████╗ ███╗   ██╗
 ████╗ ████║██╔══██╗██╔══██╗╚══███╔╝██╔══██╗██╔══██╗████╗  ██║
 ██╔████╔██║███████║██████╔╝  ███╔╝ ██████╔╝███████║██╔██╗ ██║
 ██║╚██╔╝██║██╔══██║██╔══██╗ ███╔╝  ██╔══██╗██╔══██║██║╚██╗██║
 ██║ ╚═╝ ██║██║  ██║██║  ██║███████╗██████╔╝██║  ██║██║ ╚████║
 ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝
BANNER
  echo -e "${NC}${DIM}           一键安装管理脚本  v6${NC}"
  echo -e "${B}════════════════════════════════════════════════════════${NC}"
}

show_menu() {
  show_banner
  echo
  echo -e "  ${BOLD}${W}请选择操作：${NC}"
  echo
  echo -e "  ${B}┌─────────────────────────────────────────────────┐${NC}"
  echo -e "  ${B}│${NC}  ${G}1${NC}  安装 Marzban 面板                          ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${G}2${NC}  安装 Marzban-Node 节点                     ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${Y}3${NC}  修改 REALITY 伪装域名                      ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${C}4${NC}  诊断/修复 面板                             ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${C}5${NC}  诊断/修复 节点                             ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${Y}6${NC}  安装 IP限制器 + 面板插件（备注+IP并发）   ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${G}7${NC}  安装 IP限制器管理面板（Web可视化）         ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${G}8${NC}  安装 Clash 分流规则 + Nginx UA 自动识别  ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${R}9${NC}  卸载清空 面板机（彻底删除所有组件）       ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${R}10${NC} 卸载清空 节点机（彻底删除所有组件）      ${B}│${NC}"
  echo -e "  ${B}│${NC}  ${R}0${NC}  退出                                       ${B}│${NC}"
  echo -e "  ${B}└─────────────────────────────────────────────────┘${NC}"
  echo
  read -rp "$(echo -e "  ${Y}输入选项 [0-10]: ${NC}")" CHOICE
}

# ══════════════════════════════════════════════════════════════
#  通用工具函数
# ══════════════════════════════════════════════════════════════
install_deps_common() {
  apt-get update -y 2>&1 | tail -1 || true
  for pkg in curl wget python3 python3-pip ca-certificates gnupg \
             uuid-runtime openssl certbot; do
    dpkg -l "$pkg" &>/dev/null 2>&1 || apt-get install -y -q "$pkg" 2>/dev/null || true
  done
  apt-get install -y -q python3-cryptography 2>/dev/null || \
    pip3 install cryptography --quiet --break-system-packages 2>/dev/null || true
}

install_docker_common() {
  if ! command -v docker &>/dev/null; then
    curl -fsSL --max-time 60 https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null && \
      bash /tmp/get-docker.sh 2>&1 | tail -3 || apt-get install -y docker.io 2>/dev/null
  fi
  systemctl enable docker --now 2>/dev/null || true
  if docker compose version &>/dev/null 2>&1; then COMPOSE_CMD="docker compose"
  elif command -v docker-compose &>/dev/null; then COMPOSE_CMD="docker-compose"
  else
    apt-get install -y -q docker-compose-plugin 2>/dev/null || true
    docker compose version &>/dev/null 2>&1 && COMPOSE_CMD="docker compose" || COMPOSE_CMD="docker-compose"
  fi
  log_ok "Docker Compose: $COMPOSE_CMD"
}

get_xray_version() {
  XRAY_VERSION=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/XTLS/Xray-core/releases/latest" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || echo "")
  [[ -z "$XRAY_VERSION" || "$XRAY_VERSION" == "null" ]] && XRAY_VERSION="v25.3.6"
}

gen_x25519() {
  python3 << 'PYEOF'
import base64
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding,PrivateFormat,PublicFormat,NoEncryption
priv=X25519PrivateKey.generate()
pb=priv.private_bytes(Encoding.Raw,PrivateFormat.Raw,NoEncryption())
qb=priv.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)
print("PRIV:"+base64.urlsafe_b64encode(pb).decode().rstrip('='))
print("PUB:"+base64.urlsafe_b64encode(qb).decode().rstrip('='))
PYEOF
}

setup_ssl_cert() {
  local domain="$1" cert_dir="$2"
  mkdir -p "$cert_dir"
  for d in "/etc/letsencrypt/live/${domain}" "/root/.acme.sh/${domain}_ecc" "/root/.acme.sh/${domain}"; do
    [[ -d "$d" ]] || continue
    local c k
    c=$(find "$d" \( -name 'fullchain*' -o -name '*.cer' \) 2>/dev/null | head -1)
    k=$(find "$d" \( -name 'privkey*' -o -name '*.key' \) 2>/dev/null | grep -v ec | head -1)
    if [[ -n "$c" && -n "$k" ]]; then
      cp "$c" "$cert_dir/fullchain.pem"; cp "$k" "$cert_dir/privkey.pem"
      chmod 644 "$cert_dir/fullchain.pem"; chmod 600 "$cert_dir/privkey.pem"
      log_ok "使用已有证书"; return 0
    fi
  done
  systemctl stop nginx 2>/dev/null || true; fuser -k 80/tcp 2>/dev/null || true; sleep 2
  if certbot certonly --standalone -d "$domain" \
      --non-interactive --agree-tos --email "admin@${domain}" \
      --preferred-challenges http 2>&1; then
    cp "/etc/letsencrypt/live/${domain}/fullchain.pem" "$cert_dir/"
    cp "/etc/letsencrypt/live/${domain}/privkey.pem"   "$cert_dir/"
    chmod 644 "$cert_dir/fullchain.pem"; chmod 600 "$cert_dir/privkey.pem"
    log_ok "证书申请成功"
  else
    log_warn "Certbot 失败 → 自签名证书"
    openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
      -keyout "$cert_dir/privkey.pem" -out "$cert_dir/fullchain.pem" \
      -subj "/CN=${domain}" 2>/dev/null
  fi
}

_get_token() {
  local base="$1" user="$2" pass="$3"
  python3 -c "
import urllib.request,urllib.parse,json
try:
    data=urllib.parse.urlencode({'username':'${user}','password':'${pass}'}).encode()
    r=urllib.request.urlopen(urllib.request.Request('${base}/api/admin/token',
        data=data,headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=10)
    print(json.loads(r.read()).get('access_token',''))
except: pass
" 2>/dev/null
}

_write_hosts() {
  local token="$1" base="$2" nd="$3" pfx="$4"
  local p1="$5" p2="$6" p3="$7" sni="$8"
  local tv="${9:-VLESS-TLS}" tt="${10:-Trojan-TLS}" tr="${11:-VLESS-REALITY}"
  python3 << PYEOF
import urllib.request,json
BASE="${base}"; TOKEN="${token}"
H={"Authorization":f"Bearer {TOKEN}"}
try:
    current=json.loads(urllib.request.urlopen(
        urllib.request.Request(f"{BASE}/api/hosts",headers=H),timeout=10).read())
except: current={}

def mh(remark,addr,port,sni,host,sec,alpn="",fp="chrome",**kw):
    obj={"remark":remark,"address":addr,"port":port,"sni":sni,"host":host,
         "path":"","security":sec,"alpn":alpn,"fingerprint":fp,
         "allowinsecure":True if sec=="tls" else False,
         "is_disabled":False,"mux_enable":False,"fragment_setting":"",
         "noise_setting":"","random_user_agent":False,"use_sni_as_host":False}
    obj.update(kw); return obj

nd="${nd}"; pfx="${pfx}"; p1,p2,p3=${p1},${p2},${p3}; sni="${sni}"
tv,tt,tr="${tv}","${tt}","${tr}"
new_e={tv:mh(f"{pfx}-1",nd,p1,nd,nd,"tls","h2,http/1.1"),
       tt:mh(f"{pfx}-2",nd,p2,nd,nd,"tls","h2,http/1.1"),
       tr:mh(f"{pfx}-3",nd,p3,sni,sni,"inbound_default","")}
merged=dict(current)
for tag,nh in new_e.items():
    ex=[h for h in merged.get(tag,[]) if "{" not in h.get("remark","")]
    seen={h.get("remark",""):h for h in ex}
    seen[nh["remark"]]=nh
    merged[tag]=list(seen.values())
for tag in list(merged.keys()):
    merged[tag]=[h for h in merged[tag] if "{" not in h.get("remark","")]
body=json.dumps(merged).encode()
req=urllib.request.Request(f"{BASE}/api/hosts",data=body,method="PUT",
    headers={**H,"Content-Type":"application/json"})
r=urllib.request.urlopen(req,timeout=15)
print(f"Hosts PUT HTTP {r.status}")
PYEOF
}

_fix_user_flow() {
  local token="$1" base="$2"
  python3 << PYEOF
import urllib.request,json
BASE="${base}"; TOKEN="${token}"
H={"Authorization":f"Bearer {TOKEN}"}
users=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/users?limit=5000",headers=H),timeout=10).read())
fixed=0
for u in users.get("users",[]):
    username=u.get("username",""); proxies=u.get("proxies",{}); changed=False
    if "vless" in proxies and not proxies["vless"].get("flow"):
        proxies["vless"]["flow"]="xtls-rprx-vision"; changed=True
    if not changed: continue
    body=json.dumps({"proxies":proxies}).encode()
    req=urllib.request.Request(f"{BASE}/api/user/{username}",data=body,method="PUT",
        headers={**H,"Content-Type":"application/json"})
    try:
        r=urllib.request.urlopen(req,timeout=10)
        if r.status==200: fixed+=1; print(f"  ✔ {username}: flow=xtls-rprx-vision")
    except Exception as e: print(f"  ✘ {username}: {e}")
print(f"共修复 {fixed} 个用户")
PYEOF
}

_install_watchdog() {
  cat > /usr/local/bin/marzban-watchdog.sh << 'WDEOF'
#!/usr/bin/env bash
BASE="http://127.0.0.1:8000"
[[ -f /opt/marzban/.env ]] || exit 0
U=$(grep -oP 'SUDO_USERNAME=\K\S+' /opt/marzban/.env|head -1)
P=$(grep -oP 'SUDO_PASSWORD=\K\S+' /opt/marzban/.env|head -1)
TOKEN=$(python3 -c "
import urllib.request,urllib.parse,json
try:
    d=urllib.parse.urlencode({'username':'$U','password':'$P'}).encode()
    r=urllib.request.urlopen(urllib.request.Request('$BASE/api/admin/token',
        data=d,headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=10)
    print(json.loads(r.read()).get('access_token',''))
except: pass
" 2>/dev/null)
[[ -z "$TOKEN" ]] && exit 0
python3 -c "
import urllib.request,json
BASE='$BASE'; H={'Authorization':'Bearer $TOKEN'}
try:
    nodes=json.loads(urllib.request.urlopen(
        urllib.request.Request(f'{BASE}/api/nodes',headers=H),timeout=10).read())
    for n in nodes:
        if n.get('status') not in ('connected',):
            req=urllib.request.Request(f'{BASE}/api/node/{n[\"id\"]}/reconnect',
                data=b'',method='POST',headers={**H,'Content-Type':'application/json'})
            r=urllib.request.urlopen(req,timeout=10)
            print(f'[watchdog] reconnect {n[\"name\"]} → HTTP {r.status}')
except Exception as e: print(f'[watchdog] {e}')
" 2>/dev/null
WDEOF
  chmod +x /usr/local/bin/marzban-watchdog.sh
  (crontab -l 2>/dev/null | grep -v marzban-watchdog
   echo "*/5 * * * * /usr/local/bin/marzban-watchdog.sh >> /var/log/marzban-watchdog.log 2>&1") | crontab -
  log_ok "节点看门狗已安装（每5分钟自动重连）"
}

# ── 证书自动续期 ──────────────────────────────────────────────
_setup_cert_renewal() {
  local domain="$1"      # 面板/节点域名
  local mode="$2"        # panel | node
  local cert_dir="$3"    # 证书目标目录

  # 确认 certbot 可用
  command -v certbot &>/dev/null || { log_warn "certbot 未安装，跳过自动续期配置"; return; }

  # 确认证书路径存在
  local le_dir="/etc/letsencrypt/live/${domain}"
  [[ -d "$le_dir" ]] || { log_warn "未找到 ${domain} 的 Let's Encrypt 证书，跳过自动续期"; return; }

  local cron_file="/etc/cron.d/marzban-cert-renew-${mode}"
  local compose_dir log_tag restart_extra

  if [[ "$mode" == "panel" ]]; then
    compose_dir="/opt/marzban"
    log_tag="[面板]"
    restart_extra=""
  else
    compose_dir="/opt/marzban-node"
    log_tag="[节点]"
    # 节点续期后同步到面板兼容路径
    restart_extra="cp ${cert_dir}/fullchain.pem /var/lib/marzban/certs/fullchain.pem && \
cp ${cert_dir}/privkey.pem /var/lib/marzban/certs/privkey.pem && "
  fi

  cat > "$cron_file" << CRONEOF
# Marzban ${mode} 证书自动续期（每天凌晨2点检查，剩余<30天自动续期）
0 2 * * * root certbot renew --quiet --cert-name ${domain} \\
  --pre-hook  "systemctl stop nginx 2>/dev/null || true" \\
  --post-hook "systemctl start nginx 2>/dev/null || true; \\
cp /etc/letsencrypt/live/${domain}/fullchain.pem ${cert_dir}/fullchain.pem && \\
cp /etc/letsencrypt/live/${domain}/privkey.pem ${cert_dir}/privkey.pem && \\
chmod 644 ${cert_dir}/fullchain.pem && chmod 600 ${cert_dir}/privkey.pem && \\
${restart_extra}cd ${compose_dir} && docker compose restart && \\
echo \"\$(date) ${log_tag} 证书已续期并重启\" >> /var/log/marzban-cert-renew.log" 2>/dev/null
CRONEOF
  chmod 644 "$cron_file"

  # 立即测试续期流程（dry-run）
  local test_out; test_out=$(certbot renew --dry-run --cert-name "$domain" 2>&1 | tail -3)
  if echo "$test_out" | grep -q "No renewals were attempted\|Congratulations"; then
    log_ok "证书自动续期已配置（每天02:00检查）"
    log_ok "当前证书到期时间: $(certbot certificates --cert-name "$domain" 2>/dev/null | grep 'Expiry Date' | awk '{print $3,$4}')"
  else
    log_ok "证书自动续期已配置（每天02:00检查）"
    log_warn "dry-run 测试输出: ${test_out}"
  fi
}

_add_node_inbounds() {
  local TOKEN="$1" PANEL_URL="$2" NODE_PREFIX="$3"
  local P1="$4" P2="$5" P3="$6" REALITY_PRIVATE="$7" REALITY_SHORT_ID="$8"
  local cfg_tmp; cfg_tmp=$(mktemp)
  local code; code=$(curl -s -o "$cfg_tmp" -w "%{http_code}" --max-time 10 \
    -X GET "${PANEL_URL}/api/core/config" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "000")
  [[ "$code" != "200" ]] && { log_warn "获取 xray config 失败"; rm -f "$cfg_tmp"; return; }

  local new_cfg; new_cfg=$(python3 << PYEOF
import json
with open("${cfg_tmp}") as f: config=json.load(f)
inbounds=config.get("inbounds",[])
existing={ib.get("tag","") for ib in inbounds}
cert="/var/lib/marzban/certs/fullchain.pem"; key="/var/lib/marzban/certs/privkey.pem"
pfx="${NODE_PREFIX}"
tv=f"NODE-{pfx}-VLESS-TLS"; tt=f"NODE-{pfx}-Trojan-TLS"; tr=f"NODE-{pfx}-VLESS-REALITY"
new_ibs=[]
if tv not in existing:
    new_ibs.append({"tag":tv,"listen":"0.0.0.0","port":${P1},"protocol":"vless",
        "settings":{"clients":[],"decryption":"none"},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"certificates":[{"certificateFile":cert,"keyFile":key}],
                           "alpn":["h2","http/1.1"]}},
        "sniffing":{"enabled":True,"destOverride":["http","tls","quic"]}})
if tt not in existing:
    new_ibs.append({"tag":tt,"listen":"0.0.0.0","port":${P2},"protocol":"trojan",
        "settings":{"clients":[]},
        "streamSettings":{"network":"tcp","security":"tls",
            "tlsSettings":{"certificates":[{"certificateFile":cert,"keyFile":key}],
                           "alpn":["h2","http/1.1"]}},
        "sniffing":{"enabled":True,"destOverride":["http","tls","quic"]}})
if tr not in existing:
    new_ibs.append({"tag":tr,"listen":"0.0.0.0","port":${P3},"protocol":"vless",
        "settings":{"clients":[],"decryption":"none"},
        "streamSettings":{"network":"tcp","security":"reality",
            "realitySettings":{"show":False,"dest":"www.cloudflare.com:443","xver":0,
                "serverNames":["www.cloudflare.com"],
                "privateKey":"${REALITY_PRIVATE}","shortIds":["${REALITY_SHORT_ID}"]}},
        "sniffing":{"enabled":True,"destOverride":["http","tls","quic"]}})
if new_ibs:
    config["inbounds"]=inbounds+new_ibs
    print("OK"); print(json.dumps(config,ensure_ascii=False))
else:
    print("EXISTS")
PYEOF
)
  rm -f "$cfg_tmp"
  local first_line; first_line=$(echo "$new_cfg" | head -1)
  if [[ "$first_line" == "OK" ]]; then
    local json_body; json_body=$(echo "$new_cfg" | tail -n +2)
    local pt; pt=$(mktemp)
    local pc; pc=$(curl -s -o "$pt" -w "%{http_code}" --max-time 15 \
      -X PUT "${PANEL_URL}/api/core/config" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$json_body" 2>/dev/null || echo "000")
    rm -f "$pt"
    [[ "$pc" == "200" ]] && log_ok "节点专属 inbound 注册成功（端口 $P1/$P2/$P3）" || log_warn "inbound 注册 HTTP $pc"
  else
    log_ok "节点 inbound 已存在"
  fi
}

# ══════════════════════════════════════════════════════════════
#  选项 1 - 安装面板
# ══════════════════════════════════════════════════════════════
install_panel() {
  show_banner
  echo -e "\n${B}┌─ ${W}安装 Marzban 面板 ${B}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  while true; do read -rp "$(echo -e "${C}  面板域名: ${NC}")" PANEL_DOMAIN; [[ -n "$PANEL_DOMAIN" ]] && break; done
  read -rp "$(echo -e "${C}  本机节点域名 (留空同面板): ${NC}")" NODE_DOMAIN
  NODE_DOMAIN="${NODE_DOMAIN:-$PANEL_DOMAIN}"
  while true; do read -rp "$(echo -e "${C}  节点名前缀 (e.g. HK): ${NC}")" NODE_PREFIX; [[ -n "$NODE_PREFIX" ]] && break; done
  while true; do
    read -rp "$(echo -e "${C}  端口前缀 (1~4位数字, e.g. 103 → 1031/1032/1033): ${NC}")" PORT_PREFIX
    [[ "$PORT_PREFIX" =~ ^[0-9]{1,4}$ ]] && break
  done
  P1="${PORT_PREFIX}1"; P2="${PORT_PREFIX}2"; P3="${PORT_PREFIX}3"
  while true; do read -rp "$(echo -e "${C}  管理员用户名: ${NC}")" ADMIN_USER; [[ -n "$ADMIN_USER" ]] && break; done
  while true; do read -rsp "$(echo -e "${C}  管理员密码 (≥8位): ${NC}")" ADMIN_PASS; echo; [[ ${#ADMIN_PASS} -ge 8 ]] && break; done
  while true; do read -rsp "$(echo -e "${C}  确认密码: ${NC}")" AP2; echo; [[ "$ADMIN_PASS" == "$AP2" ]] && break; log_err "密码不一致"; done

  echo
  echo -e "  ${BOLD}REALITY 伪装域名：${NC}"
  echo -e "  ${DIM}1) www.cloudflare.com  2) www.google.com  3) www.microsoft.com  4) 自定义${NC}"
  read -rp "$(echo -e "${C}  选择 [1-4] (默认1): ${NC}")" DC
  case "${DC:-1}" in
    2) REALITY_DEST="www.google.com";     REALITY_SNI="www.google.com" ;;
    3) REALITY_DEST="www.microsoft.com";  REALITY_SNI="www.microsoft.com" ;;
    4) read -rp "$(echo -e "${C}  输入域名: ${NC}")" REALITY_DEST; REALITY_SNI="$REALITY_DEST" ;;
    *) REALITY_DEST="www.cloudflare.com"; REALITY_SNI="www.cloudflare.com" ;;
  esac

  echo
  echo -e "${B}  摘要: ${W}$PANEL_DOMAIN${NC} | ${W}$NODE_PREFIX${NC} | :${W}$P1/$P2/$P3${NC} | REALITY:${W}$REALITY_DEST${NC}"
  read -rp "$(echo -e "${Y}  确认安装? [Y/n]: ${NC}")" CONFIRM
  [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && return

  log_step "安装依赖"; install_deps_common; apt-get install -y -q nginx 2>/dev/null || true; log_ok "完成"
  log_step "安装 Docker"; install_docker_common
  log_step "Xray 版本"; get_xray_version; log_ok "$XRAY_VERSION"
  log_step "SSL 证书"; setup_ssl_cert "$PANEL_DOMAIN" "/var/lib/marzban/certs"

  log_step "生成 REALITY 密钥"
  REALITY_SHORT_ID=$(openssl rand -hex 8)
  local keys; keys=$(gen_x25519)
  REALITY_PRIVATE=$(echo "$keys" | grep "^PRIV:" | cut -d: -f2)
  REALITY_PUBLIC=$(echo "$keys"  | grep "^PUB:"  | cut -d: -f2)
  [[ -z "$REALITY_PRIVATE" ]] && die "密钥生成失败，请安装 python3-cryptography"
  log_ok "pubKey: ${REALITY_PUBLIC:0:20}...  shortId: $REALITY_SHORT_ID"

  log_step "生成 Xray config.json"
  mkdir -p /var/lib/marzban/xray /var/lib/marzban/logs
  touch /var/lib/marzban/logs/access.log /var/lib/marzban/logs/error.log
  cat > /var/lib/marzban/xray/config.json << XRAYEOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/lib/marzban/logs/access.log",
    "error":  "/var/lib/marzban/logs/error.log"
  },
  "inbounds": [
    {
      "tag": "VLESS-TLS", "listen": "0.0.0.0", "port": ${P1},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "tls",
        "tlsSettings": {
          "certificates": [{"certificateFile": "/var/lib/marzban/certs/fullchain.pem",
                            "keyFile":         "/var/lib/marzban/certs/privkey.pem"}],
          "alpn": ["h2","http/1.1"]}},
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    },
    {
      "tag": "Trojan-TLS", "listen": "0.0.0.0", "port": ${P2},
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {"network": "tcp", "security": "tls",
        "tlsSettings": {
          "certificates": [{"certificateFile": "/var/lib/marzban/certs/fullchain.pem",
                            "keyFile":         "/var/lib/marzban/certs/privkey.pem"}],
          "alpn": ["h2","http/1.1"]}},
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    },
    {
      "tag": "VLESS-REALITY", "listen": "0.0.0.0", "port": ${P3},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {"network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "dest": "${REALITY_DEST}:443", "xver": 0,
          "serverNames": ["${REALITY_SNI}"],
          "privateKey": "${REALITY_PRIVATE}",
          "shortIds": ["${REALITY_SHORT_ID}"]}},
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    }
  ],
  "outbounds": [
    {"tag": "direct",  "protocol": "freedom"},
    {"tag": "blocked", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","ip":    ["geoip:private"],           "outboundTag":"blocked"},
      {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"blocked"}
    ]
  }
}
XRAYEOF
  python3 -m json.tool /var/lib/marzban/xray/config.json > /dev/null 2>&1 && log_ok "config.json 验证通过" || die "config.json 格式错误"

  log_step "生成 .env"
  mkdir -p /opt/marzban
  local SK; SK=$(openssl rand -hex 32)
  cat > /opt/marzban/.env << ENVEOF
UVICORN_HOST=0.0.0.0
UVICORN_PORT=8000
SQLALCHEMY_DATABASE_URL=sqlite:////var/lib/marzban/db.sqlite3
XRAY_JSON=/var/lib/marzban/xray/config.json
XRAY_ASSETS_PATH=/usr/local/share/xray/
XRAY_EXECUTABLE_PATH=/usr/local/bin/xray
XRAY_SUBSCRIPTION_URL_PREFIX=https://${PANEL_DOMAIN}
SECRET_KEY=${SK}
ACCESS_TOKEN_EXPIRE_MINUTES=1440
SUDO_USERNAME=${ADMIN_USER}
SUDO_PASSWORD=${ADMIN_PASS}
DOCS=True
USERS_AUTODELETE_DAYS=-1
NODE_USAGE_COEFFICIENT=1
ENVEOF

  cat > /opt/marzban/docker-compose.yml << 'COMPOSEEOF'
services:
  marzban:
    image: gozargah/marzban:latest
    container_name: marzban
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
COMPOSEEOF

  log_step "配置 Nginx"
  command -v nginx &>/dev/null && {
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    cat > /etc/nginx/sites-available/marzban << NGINXEOF
server {
    listen 80; server_name ${PANEL_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2; server_name ${PANEL_DOMAIN};
    ssl_certificate     /var/lib/marzban/certs/fullchain.pem;
    ssl_certificate_key /var/lib/marzban/certs/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }
}
NGINXEOF
    ln -sf /etc/nginx/sites-available/marzban /etc/nginx/sites-enabled/marzban
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null && log_ok "Nginx 配置完成"
  }

  log_step "启动 Marzban"
  mkdir -p /var/lib/marzban/{logs,xray,certs,templates}
  touch /var/lib/marzban/logs/access.log /var/lib/marzban/logs/error.log
  cd /opt/marzban
  docker rm -f marzban 2>/dev/null || true
  $COMPOSE_CMD pull 2>&1 | grep -E "Pulled|up to date|Already" || true
  $COMPOSE_CMD up -d || die "启动失败"
  log_info "等待服务就绪..."
  for i in $(seq 1 24); do
    sleep 5; printf "\r  等待 %ds..." $((i*5))
    local hc; hc=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:8000/" 2>/dev/null || echo "000")
    [[ "$hc" == "200" || "$hc" == "301" ]] && break
  done; echo

  log_step "写入 Hosts + 修复 flow"
  local TOKEN=""
  for i in $(seq 1 8); do
    TOKEN=$(_get_token "http://127.0.0.1:8000" "$ADMIN_USER" "$ADMIN_PASS")
    [[ -n "$TOKEN" ]] && break; sleep 5
  done
  if [[ -n "$TOKEN" ]]; then
    log_ok "Token 获取成功"
    _write_hosts "$TOKEN" "http://127.0.0.1:8000" "$NODE_DOMAIN" "$NODE_PREFIX" \
      "$P1" "$P2" "$P3" "$REALITY_SNI" "VLESS-TLS" "Trojan-TLS" "VLESS-REALITY"
  fi

  log_step "安装节点看门狗"
  _install_watchdog

  log_step "配置证书自动续期"
  _setup_cert_renewal "$PANEL_DOMAIN" "panel" "/var/lib/marzban/certs"

  cat > /root/marzban-info.txt << INFOEOF
═══════════════════════════════════════════════
  Marzban 安装信息  $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════
  面板地址   : https://${PANEL_DOMAIN}/dashboard
  管理账号   : ${ADMIN_USER}
  管理密码   : ${ADMIN_PASS}
  节点域名   : ${NODE_DOMAIN}
  节点名     : ${NODE_PREFIX}-1/2/3
  VLESS+TLS      端口 : ${P1}
  Trojan+TLS     端口 : ${P2}
  VLESS+REALITY  端口 : ${P3}
  REALITY 伪装域 : ${REALITY_DEST}
  REALITY Private Key : ${REALITY_PRIVATE}
  REALITY Public  Key : ${REALITY_PUBLIC}
  REALITY Short   ID  : ${REALITY_SHORT_ID}
  常用命令:
    cd /opt/marzban && ${COMPOSE_CMD} restart
    cd /opt/marzban && ${COMPOSE_CMD} logs -f
═══════════════════════════════════════════════
INFOEOF
  chmod 600 /root/marzban-info.txt

  echo; echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  🎉  面板安装完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  地址: ${C}https://${PANEL_DOMAIN}/dashboard${NC}"
  echo -e "  ${DIM}cat /root/marzban-info.txt${NC}"
  echo; read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 2 - 安装节点
# ══════════════════════════════════════════════════════════════
install_node() {
  show_banner
  echo -e "\n${C}┌─ ${W}安装 Marzban-Node 节点 ${C}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  while true; do read -rp "$(echo -e "${C}  面板域名: ${NC}")" PANEL_DOMAIN; [[ -n "$PANEL_DOMAIN" ]] && break; done
  PANEL_URL="https://${PANEL_DOMAIN}"
  while true; do read -rp "$(echo -e "${C}  面板管理员用户名: ${NC}")" ADMIN_USER; [[ -n "$ADMIN_USER" ]] && break; done
  while true; do read -rsp "$(echo -e "${C}  面板管理员密码: ${NC}")" ADMIN_PASS; echo; [[ -n "$ADMIN_PASS" ]] && break; done
  while true; do read -rp "$(echo -e "${C}  本节点域名: ${NC}")" NODE_DOMAIN; [[ -n "$NODE_DOMAIN" ]] && break; done
  while true; do read -rp "$(echo -e "${C}  节点名前缀 (e.g. US/SG): ${NC}")" NODE_PREFIX; [[ -n "$NODE_PREFIX" ]] && break; done
  while true; do
    read -rp "$(echo -e "${C}  对外端口前缀 (1~4位, e.g. 301 → 3011/3012/3013): ${NC}")" PORT_PREFIX
    [[ "$PORT_PREFIX" =~ ^[0-9]{1,4}$ ]] && break
  done
  P1="${PORT_PREFIX}1"; P2="${PORT_PREFIX}2"; P3="${PORT_PREFIX}3"
  read -rp "$(echo -e "${C}  节点服务端口 (默认62050): ${NC}")" NODE_SERVICE_PORT
  NODE_SERVICE_PORT="${NODE_SERVICE_PORT:-62050}"
  read -rp "$(echo -e "${C}  节点API端口 (默认62051): ${NC}")" NODE_API_PORT
  NODE_API_PORT="${NODE_API_PORT:-62051}"

  echo
  echo -e "  ${Y}粘贴面板客户端证书（输入 END 结束，跳过直接输 END）：${NC}"
  CLIENT_CERT=""; HAS_CERT=false
  while IFS= read -r line; do
    [[ "$line" == "END" ]] && break
    CLIENT_CERT="${CLIENT_CERT}${line}\n"
  done
  echo "$CLIENT_CERT" | grep -q "BEGIN CERTIFICATE" && HAS_CERT=true && log_ok "证书验证通过" || log_warn "跳过证书"

  echo
  echo -e "  ${B}摘要: ${W}$NODE_DOMAIN${NC} | ${W}$NODE_PREFIX${NC} | :${W}$P1/$P2/$P3${NC} | 服务:${W}$NODE_SERVICE_PORT${NC}"
  read -rp "$(echo -e "${Y}  确认安装? [Y/n]: ${NC}")" CONFIRM
  [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && return

  log_step "安装依赖"; install_deps_common
  log_step "安装 Docker"; install_docker_common
  log_step "Xray 版本"; get_xray_version

  log_step "配置节点 TLS 证书"
  setup_ssl_cert "$NODE_DOMAIN" "/var/lib/marzban-node/certs"

  log_step "同步证书到面板兼容路径"
  mkdir -p /var/lib/marzban/certs /var/lib/marzban/logs
  cp /var/lib/marzban-node/certs/fullchain.pem /var/lib/marzban/certs/fullchain.pem
  cp /var/lib/marzban-node/certs/privkey.pem   /var/lib/marzban/certs/privkey.pem
  touch /var/lib/marzban/logs/access.log /var/lib/marzban/logs/error.log
  log_ok "/var/lib/marzban/certs/ ✓  /var/lib/marzban/logs/ ✓"

  if [[ "$HAS_CERT" == true ]]; then
    log_step "写入客户端证书"
    printf '%b' "$CLIENT_CERT" > /var/lib/marzban-node/certs/client.pem
    chmod 600 /var/lib/marzban-node/certs/client.pem
    log_ok "client.pem 写入完成"
  fi

  log_step "生成节点 REALITY 密钥"
  REALITY_SHORT_ID=$(openssl rand -hex 8)
  local keys; keys=$(gen_x25519)
  REALITY_PRIVATE=$(echo "$keys" | grep "^PRIV:" | cut -d: -f2)
  REALITY_PUBLIC=$(echo "$keys"  | grep "^PUB:"  | cut -d: -f2)
  log_ok "pubKey: ${REALITY_PUBLIC:0:20}..."

  log_step "准备目录与 docker-compose.yml"
  mkdir -p /opt/marzban-node /var/lib/marzban-node/{certs,logs,xray}
  touch /var/lib/marzban-node/logs/access.log /var/lib/marzban-node/logs/error.log

  local ccl=""
  [[ "$HAS_CERT" == true ]] && ccl="      SSL_CLIENT_CERT_FILE: \"/var/lib/marzban-node/certs/client.pem\""

  cat > /opt/marzban-node/docker-compose.yml << COMPOSEEOF
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    container_name: marzban-node
    restart: always
    network_mode: host
    environment:
      SERVICE_PORT:         "${NODE_SERVICE_PORT}"
      XRAY_API_PORT:        "${NODE_API_PORT}"
      SERVICE_PROTOCOL:     "rest"
      XRAY_EXECUTABLE_PATH: "/usr/local/bin/xray"
${ccl:+$ccl}
    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
      - /var/lib/marzban:/var/lib/marzban
COMPOSEEOF
  log_ok "SERVICE_PROTOCOL=rest（HTTP模式）"
  log_ok "/var/lib/marzban 挂载到容器"

  cat > /etc/cron.d/marzban-cert-sync << 'CRONEOF'
0 3 * * * root cp /var/lib/marzban-node/certs/fullchain.pem /var/lib/marzban/certs/fullchain.pem && cp /var/lib/marzban-node/certs/privkey.pem /var/lib/marzban/certs/privkey.pem
@reboot root sleep 30 && cp /var/lib/marzban-node/certs/fullchain.pem /var/lib/marzban/certs/ && cp /var/lib/marzban-node/certs/privkey.pem /var/lib/marzban/certs/
CRONEOF
  log_ok "证书自动同步 cron 已配置"

  log_step "启动节点"
  cd /opt/marzban-node
  docker rm -f marzban-node 2>/dev/null || true
  $COMPOSE_CMD pull 2>&1 | grep -E "Pulled|up to date|Already" || true
  $COMPOSE_CMD up -d || die "启动失败"
  for i in $(seq 1 9); do
    sleep 5; printf "\r  等待 %ds..." $((i*5))
    docker inspect --format='{{.State.Status}}' marzban-node 2>/dev/null | grep -q running && break
  done; echo
  docker ps | grep -q marzban-node && log_ok "节点运行中 ✓" || log_warn "请检查: docker logs marzban-node"

  log_step "向面板注册节点 + 写入 Hosts + 修复 flow"
  local TOKEN=""
  for i in $(seq 1 6); do
    TOKEN=$(python3 -c "
import urllib.request,urllib.parse,json
try:
    data=urllib.parse.urlencode({'username':'${ADMIN_USER}','password':'${ADMIN_PASS}'}).encode()
    r=urllib.request.urlopen(urllib.request.Request('${PANEL_URL}/api/admin/token',
        data=data,headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=15)
    print(json.loads(r.read()).get('access_token',''))
except: pass
" 2>/dev/null)
    [[ -n "$TOKEN" ]] && break; log_info "连接面板 ($i/6)..."; sleep 5
  done
  [[ -z "$TOKEN" ]] && { log_warn "无法连接面板 API"; echo -e "\n${Y}请手动添加节点: ${W}${NODE_DOMAIN}:${NODE_SERVICE_PORT}${NC}"; return; }
  log_ok "面板 API 连接成功"

  local tmp; tmp=$(mktemp)
  local code; code=$(curl -s -o "$tmp" -w "%{http_code}" --max-time 15 \
    -X POST "${PANEL_URL}/api/node" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"name\":\"${NODE_PREFIX}-Node\",\"address\":\"${NODE_DOMAIN}\",
         \"port\":${NODE_SERVICE_PORT},\"api_port\":${NODE_API_PORT},\"usage_coefficient\":1}" \
    2>/dev/null || echo "000")
  local body; body=$(cat "$tmp" 2>/dev/null); rm -f "$tmp"
  [[ "$code" == "200" || "$code" == "201" ]] && \
    log_ok "节点注册成功 ID: $(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('id',''))" "$body" 2>/dev/null)" || \
    log_warn "HTTP $code（节点可能已存在）"

  _add_node_inbounds "$TOKEN" "$PANEL_URL" "$NODE_PREFIX" "$P1" "$P2" "$P3" \
    "$REALITY_PRIVATE" "$REALITY_SHORT_ID"

  local TAG_V="NODE-${NODE_PREFIX}-VLESS-TLS"
  local TAG_T="NODE-${NODE_PREFIX}-Trojan-TLS"
  local TAG_R="NODE-${NODE_PREFIX}-VLESS-REALITY"
  _write_hosts "$TOKEN" "$PANEL_URL" "$NODE_DOMAIN" "$NODE_PREFIX" \
    "$P1" "$P2" "$P3" "www.cloudflare.com" "$TAG_V" "$TAG_T" "$TAG_R"

  log_step "修复用户 VLESS flow=xtls-rprx-vision"
  _fix_user_flow "$TOKEN" "$PANEL_URL"

  log_step "配置节点证书自动续期"
  _setup_cert_renewal "$NODE_DOMAIN" "node" "/var/lib/marzban-node/certs"

  cat > /root/marzban-node-info.txt << INFOEOF
═══════════════════════════════════════════════
  Marzban-Node 安装信息  $(date '+%Y-%m-%d %H:%M:%S')
═══════════════════════════════════════════════
  面板地址      : ${PANEL_URL}/dashboard
  节点域名      : ${NODE_DOMAIN}
  节点名        : ${NODE_PREFIX}-1/2/3
  VLESS+TLS     : ${P1}
  Trojan+TLS    : ${P2}
  VLESS+REALITY : ${P3}
  节点服务端口  : ${NODE_SERVICE_PORT}
  REALITY Private Key : ${REALITY_PRIVATE}
  REALITY Public  Key : ${REALITY_PUBLIC}
  REALITY Short   ID  : ${REALITY_SHORT_ID}
  常用命令:
    cd /opt/marzban-node && ${COMPOSE_CMD} restart
    cd /opt/marzban-node && ${COMPOSE_CMD} logs -f
═══════════════════════════════════════════════
INFOEOF
  chmod 600 /root/marzban-node-info.txt

  echo; echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  🎉  节点安装完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  节点: ${C}${NODE_DOMAIN}${NC}  服务:${Y}${NODE_SERVICE_PORT}${NC}"
  echo -e "  ${NODE_PREFIX}-1 VLESS+TLS  :${Y}${P1}${NC}  ${NODE_PREFIX}-2 Trojan+TLS :${Y}${P2}${NC}  ${NODE_PREFIX}-3 REALITY :${Y}${P3}${NC}"
  echo; read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 3 - 修改 REALITY 伪装域名
# ══════════════════════════════════════════════════════════════
change_reality_dest() {
  show_banner
  echo -e "\n${Y}┌─ ${W}修改 REALITY 伪装域名 ${Y}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  local BASE="http://127.0.0.1:8000"
  local USER="" PASS=""
  if [[ -f "/opt/marzban/.env" ]]; then
    USER=$(grep -oP 'SUDO_USERNAME=\K\S+' /opt/marzban/.env | head -1)
    PASS=$(grep -oP 'SUDO_PASSWORD=\K\S+' /opt/marzban/.env | head -1)
    log_ok "读取面板账号: $USER"
  else
    read -rp "$(echo -e "${C}  管理员用户名: ${NC}")" USER
    read -rsp "$(echo -e "${C}  管理员密码: ${NC}")" PASS; echo
  fi

  echo
  echo -e "  ${DIM}1) www.cloudflare.com  2) www.google.com  3) www.microsoft.com  4) www.amazon.com  5) 自定义${NC}"
  read -rp "$(echo -e "${C}  选择 [1-5]: ${NC}")" DC
  local NEW_DEST NEW_SNI
  case "$DC" in
    1) NEW_DEST="www.cloudflare.com"; NEW_SNI="www.cloudflare.com" ;;
    2) NEW_DEST="www.google.com";     NEW_SNI="www.google.com" ;;
    3) NEW_DEST="www.microsoft.com";  NEW_SNI="www.microsoft.com" ;;
    4) NEW_DEST="www.amazon.com";     NEW_SNI="www.amazon.com" ;;
    5) read -rp "$(echo -e "${C}  输入域名: ${NC}")" NEW_DEST; NEW_SNI="$NEW_DEST" ;;
    *) log_err "无效选项"; read -rp "  按 Enter..."; return ;;
  esac

  log_info "测试 $NEW_DEST 连通性..."
  local tc; tc=$(curl -sk --max-time 5 "https://${NEW_DEST}" -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
  [[ "$tc" == "200" || "$tc" == "301" || "$tc" == "302" ]] && log_ok "$NEW_DEST 可达 (HTTP $tc)" || log_warn "返回 $tc，继续修改"

  read -rp "$(echo -e "${Y}  确认修改为 $NEW_DEST? [Y/n]: ${NC}")" CONFIRM
  [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && return

  local TOKEN; TOKEN=$(_get_token "$BASE" "$USER" "$PASS")
  [[ -z "$TOKEN" ]] && { log_err "Token 获取失败"; read -rp "  按 Enter..."; return; }

  python3 << PYEOF
import urllib.request,json
BASE="${BASE}"; TOKEN="${TOKEN}"; ND="${NEW_DEST}"; NS="${NEW_SNI}"
H={"Authorization":f"Bearer {TOKEN}"}
cfg=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/core/config",headers=H),timeout=10).read())
for ib in cfg.get("inbounds",[]):
    rs=ib.get("streamSettings",{}).get("realitySettings",{})
    if rs:
        rs["dest"]=f"{ND}:443"; rs["serverNames"]=[NS]
        print(f"  修改 [{ib['tag']}] → {ND}:443")
body=json.dumps(cfg).encode()
req=urllib.request.Request(f"{BASE}/api/core/config",data=body,method="PUT",
    headers={**H,"Content-Type":"application/json"})
r=urllib.request.urlopen(req,timeout=15)
print(f"  ✔ xray config HTTP {r.status}")
hosts=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/hosts",headers=H),timeout=10).read())
for tag,hs in hosts.items():
    for h in hs:
        if h.get("security")=="inbound_default":
            h["sni"]=NS; h["host"]=NS
            print(f"  修改 Hosts [{tag}] {h.get('remark')}: SNI={NS}")
body=json.dumps(hosts).encode()
req=urllib.request.Request(f"{BASE}/api/hosts",data=body,method="PUT",
    headers={**H,"Content-Type":"application/json"})
r=urllib.request.urlopen(req,timeout=15)
print(f"  ✔ Hosts HTTP {r.status}")
PYEOF
  [[ -f "/root/marzban-info.txt" ]] && \
    sed -i "s|REALITY 伪装域.*|REALITY 伪装域 : ${NEW_DEST}|" /root/marzban-info.txt 2>/dev/null

  echo; log_ok "REALITY 伪装域已修改为: $NEW_DEST，请刷新客户端订阅"
  echo; read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 4 - 诊断/修复 面板
# ══════════════════════════════════════════════════════════════
diag_panel() {
  show_banner
  echo -e "\n${C}┌─ ${W}面板诊断修复 ${C}─${NC}\n"

  local BASE="http://127.0.0.1:8000"
  local USER="" PASS=""
  if [[ -f "/opt/marzban/.env" ]]; then
    USER=$(grep -oP 'SUDO_USERNAME=\K\S+' /opt/marzban/.env | head -1)
    PASS=$(grep -oP 'SUDO_PASSWORD=\K\S+' /opt/marzban/.env | head -1)
  else
    read -rp "$(echo -e "${C}  管理员用户名: ${NC}")" USER
    read -rsp "$(echo -e "${C}  管理员密码: ${NC}")" PASS; echo
  fi

  log_step "容器状态"
  local state; state=$(docker inspect --format='{{.State.Status}}' marzban 2>/dev/null || echo "不存在")
  [[ "$state" == "running" ]] && log_ok "marzban: running" || { log_err "marzban: $state"; docker logs marzban --tail=10 2>&1; }

  log_step "获取 Token"
  local TOKEN; TOKEN=$(_get_token "$BASE" "$USER" "$PASS")
  [[ -z "$TOKEN" ]] && { log_err "Token 获取失败"; read -rp "  按 Enter..."; return; }
  log_ok "Token 成功"

  log_step "节点状态"
  python3 << PYEOF
import urllib.request,json
BASE="${BASE}"; H={"Authorization":"Bearer ${TOKEN}"}
nodes=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/nodes",headers=H),timeout=10).read())
for n in nodes:
    s=n.get('status','?')
    c='\033[0;32m' if s=='connected' else '\033[0;31m' if s=='error' else '\033[1;33m'
    print(f"  {c}{'✔' if s=='connected' else '✘'}\033[0m  {n['name']} {n['address']}:{n['port']} [{s}]")
    if n.get('message'): print(f"     {n['message'][:80]}")
PYEOF

  log_step "自动修复"
  python3 << PYEOF
import urllib.request,json
BASE="${BASE}"; H={"Authorization":"Bearer ${TOKEN}"}
hosts=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/hosts",headers=H),timeout=10).read())
cleaned={}; rm=0
for tag,hs in hosts.items():
    good=[h for h in hs if '{' not in h.get('remark','')]
    rm+=len(hs)-len(good)
    if good: cleaned[tag]=good
if rm>0:
    body=json.dumps(cleaned).encode()
    req=urllib.request.Request(f"{BASE}/api/hosts",data=body,method="PUT",
        headers={**H,"Content-Type":"application/json"})
    r=urllib.request.urlopen(req,timeout=15)
    print(f"  ✔ 清除 {rm} 条垃圾 Hosts HTTP {r.status}")
hosts2=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/hosts",headers=H),timeout=10).read())
fx=0
for tag,hs in hosts2.items():
    for h in hs:
        if h.get('security')=='tls' and not h.get('allowinsecure'):
            h['allowinsecure']=True; h['fingerprint']='chrome'; fx+=1
if fx>0:
    body=json.dumps(hosts2).encode()
    req=urllib.request.Request(f"{BASE}/api/hosts",data=body,method="PUT",
        headers={**H,"Content-Type":"application/json"})
    r=urllib.request.urlopen(req,timeout=15)
    print(f"  ✔ 修复 {fx} 条 TLS allowinsecure HTTP {r.status}")
PYEOF

  log_step "修复 flow + 强制重连节点"
  _fix_user_flow "$TOKEN" "$BASE"

  python3 << PYEOF
import urllib.request,json,time
BASE="${BASE}"; H={"Authorization":"Bearer ${TOKEN}"}
nodes=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/nodes",headers=H),timeout=10).read())
for n in nodes:
    try:
        req=urllib.request.Request(f"{BASE}/api/node/{n['id']}/reconnect",
            data=b'',method="POST",headers={**H,"Content-Type":"application/json"})
        r=urllib.request.urlopen(req,timeout=10)
        print(f"  ✔ 重连 {n['name']} HTTP {r.status}")
    except Exception as e: print(f"  ✘ {n['name']}: {e}")
time.sleep(6)
nodes2=json.loads(urllib.request.urlopen(
    urllib.request.Request(f"{BASE}/api/nodes",headers=H),timeout=10).read())
for n in nodes2:
    s=n.get('status','?')
    c='\033[0;32m' if s=='connected' else '\033[1;33m'
    print(f"  {c}●\033[0m {n['name']}: {s}")
PYEOF

  log_step "看门狗检查"
  crontab -l 2>/dev/null | grep -q marzban-watchdog && log_ok "看门狗已安装" || _install_watchdog

  echo; read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 5 - 诊断/修复 节点
# ══════════════════════════════════════════════════════════════
diag_node() {
  show_banner
  echo -e "\n${C}┌─ ${W}节点诊断修复 ${C}─${NC}\n"

  log_step "容器状态"
  local state; state=$(docker inspect --format='{{.State.Status}}' marzban-node 2>/dev/null || echo "不存在")
  [[ "$state" == "running" ]] && log_ok "marzban-node: running" || log_err "marzban-node: $state"

  log_step "docker-compose.yml"
  [[ -f "/opt/marzban-node/docker-compose.yml" ]] && cat /opt/marzban-node/docker-compose.yml || log_err "文件不存在"

  log_step "证书检查"
  for f in "/var/lib/marzban-node/certs/client.pem" \
           "/var/lib/marzban-node/certs/fullchain.pem" \
           "/var/lib/marzban/certs/fullchain.pem" \
           "/var/lib/marzban/logs/access.log"; do
    [[ -f "$f" ]] && log_ok "$f ($(wc -c < "$f") bytes)" || log_err "$f 缺失"
  done

  log_step "SERVICE_PROTOCOL 检查"
  if grep -q "SERVICE_PROTOCOL.*rest" /opt/marzban-node/docker-compose.yml 2>/dev/null; then
    log_ok "SERVICE_PROTOCOL=rest ✓"
  else
    log_warn "未设置 rest，修复中..."
    sed -i '/SERVICE_PORT/a\      SERVICE_PROTOCOL:     "rest"' /opt/marzban-node/docker-compose.yml && log_ok "已添加"
  fi

  log_step "自动修复"
  local FIX=false
  if [[ -f "/var/lib/marzban-node/certs/fullchain.pem" ]]; then
    if [[ ! -f "/var/lib/marzban/certs/fullchain.pem" ]] || \
       [[ "/var/lib/marzban-node/certs/fullchain.pem" -nt "/var/lib/marzban/certs/fullchain.pem" ]]; then
      mkdir -p /var/lib/marzban/certs
      cp /var/lib/marzban-node/certs/fullchain.pem /var/lib/marzban/certs/
      cp /var/lib/marzban-node/certs/privkey.pem   /var/lib/marzban/certs/
      log_ok "证书同步完成"; FIX=true
    else
      log_ok "证书已是最新"
    fi
  fi
  for dir in "/var/lib/marzban-node/logs" "/var/lib/marzban/logs"; do
    mkdir -p "$dir"
    for f in access.log error.log; do
      [[ ! -f "$dir/$f" ]] && touch "$dir/$f" && log_ok "创建: $dir/$f" && FIX=true
    done
  done
  if [[ "$FIX" == true ]]; then
    cd /opt/marzban-node && docker compose restart 2>/dev/null; log_ok "节点已重启"
  fi

  log_step "最新日志"
  docker logs marzban-node --tail=15 2>&1

  echo; read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 6 - 安装 IP 限制器 + 面板UI插件（含备注显示）
# ══════════════════════════════════════════════════════════════
install_ip_limiter() {
  show_banner
  echo -e "\n${Y}┌─ ${W}安装 IP限制器 + 面板插件（IP并发限制UI + 备注显示）${Y}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  local BASE_DIR="/opt/marzban/ip-limiter"
  local CUSTOM_DIR="/opt/marzban/custom"
  local LOG_DIR="/var/lib/marzban/logs"
  local ENV_FILE="/opt/marzban/.env"
  local PANEL_USER="admin" PANEL_PASS="admin" PANEL_PORT="8000"

  if [[ -f "$ENV_FILE" ]]; then
    PANEL_USER=$(grep -oP 'SUDO_USERNAME=\K\S+' "$ENV_FILE" | head -1)
    PANEL_PASS=$(grep -oP 'SUDO_PASSWORD=\K\S+' "$ENV_FILE" | head -1)
    local _PORT; _PORT=$(grep -oP 'UVICORN_PORT=\K\S+' "$ENV_FILE" | head -1)
    [[ -n "$_PORT" ]] && PANEL_PORT="$_PORT"
    log_ok "读取面板账号: $PANEL_USER (端口: $PANEL_PORT)"
  fi

  read -rp "$(echo -e "  ${C}封禁时长（小时，默认 3）: ${NC}")" BAN_HOURS
  BAN_HOURS="${BAN_HOURS:-3}"
  log_ok "封禁时长: ${BAN_HOURS} 小时"

  log_info "安装依赖..."
  apt-get install -y -q python3 python3-pip nginx 2>/dev/null || true
  pip3 install requests --quiet --break-system-packages 2>/dev/null || \
  pip3 install requests --quiet 2>/dev/null || true

  mkdir -p "$BASE_DIR" "$CUSTOM_DIR" "$LOG_DIR/nodes"
  touch "$LOG_DIR/access.log"
  [[ ! -f "$BASE_DIR/user_limits.json" ]] && echo '{}' > "$BASE_DIR/user_limits.json"

  cat > "$BASE_DIR/ip_limiter.py" << 'PYEOF'
#!/usr/bin/env python3
"""Marzban IP 限制器 v8 — 活跃窗口+累计超限版"""
import os,re,sys,time,json,signal,logging,threading
from collections import defaultdict
from http.server import HTTPServer,BaseHTTPRequestHandler
try:
    import requests,urllib3; urllib3.disable_warnings()
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable,"-m","pip","install","requests","--break-system-packages","-q"])
    import requests,urllib3; urllib3.disable_warnings()

LOG_DIR    =os.environ.get("LOG_DIR",    "/var/lib/marzban/logs")
LIMITS_FILE=os.environ.get("LIMITS_FILE","/opt/marzban/ip-limiter/user_limits.json")
PANEL_URL  =os.environ.get("PANEL_URL",  "http://127.0.0.1:8000")
PANEL_USER =os.environ.get("PANEL_USER", "admin")
PANEL_PASS =os.environ.get("PANEL_PASS", "admin")
SCAN       =int(os.environ.get("SCAN_INTERVAL","10"))
IP_TIMEOUT =int(os.environ.get("IP_TIMEOUT",   "600"))
ACTIVE_WIN =int(os.environ.get("ACTIVE_WINDOW","180"))
OVER_MIN   =int(os.environ.get("OVER_MINUTES",  "5"))
BAN_HOURS  =int(os.environ.get("BAN_HOURS",     "3"))
API_PORT   =int(os.environ.get("API_PORT",     "9191"))

os.makedirs(LOG_DIR,exist_ok=True)
os.makedirs(os.path.join(LOG_DIR,"nodes"),exist_ok=True)
logging.basicConfig(level=logging.INFO,
    format="%(asctime)s [IPL] %(levelname)s %(message)s",
    handlers=[logging.StreamHandler(),
              logging.FileHandler(os.path.join(LOG_DIR,"ip_limiter.log"),"a")])
L=logging.getLogger("ipl")

uips=defaultdict(dict); banned_users={}; fpos={}
over_accum={}
was_over={}
_uname_map={}
_lc={};_lm=0; _token=None; _token_exp=0; running=True

def _stop(s,f):
    global running; running=False
signal.signal(signal.SIGTERM,_stop); signal.signal(signal.SIGINT,_stop)

def load_limits():
    global _lc,_lm
    try:
        mt=os.path.getmtime(LIMITS_FILE)
        if mt!=_lm:
            with open(LIMITS_FILE) as f: _lc=json.load(f)
            _lm=mt
    except: pass
    return _lc

def save_limits(d):
    with open(LIMITS_FILE,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False)
    global _lm; _lm=os.path.getmtime(LIMITS_FILE)

def get_limit(u): return int(load_limits().get(u,0))

def _get_token():
    global _token,_token_exp
    if _token and time.time()<_token_exp: return _token
    try:
        r=requests.post(f"{PANEL_URL}/api/admin/token",
            data={"username":PANEL_USER,"password":PANEL_PASS},timeout=10,verify=False)
        r.raise_for_status()
        _token=r.json()["access_token"]; _token_exp=time.time()+3500
        return _token
    except Exception as e: L.error(f"Token: {e}"); return None

def _refresh_uname_cache():
    global _uname_map
    users=get_all_users()
    _uname_map={u.get("username","").lower():u.get("username","") for u in users}

def _get_real_username(u):
    return _uname_map.get(u.lower(), u)

def _set_status(u,status):
    tk=_get_token()
    if not tk: return False
    real_u=_get_real_username(u)
    try:
        r=requests.put(f"{PANEL_URL}/api/user/{real_u}",
            headers={"Authorization":f"Bearer {tk}","Content-Type":"application/json"},
            json={"status":status},timeout=10,verify=False)
        return r.status_code==200
    except Exception as e: L.error(f"set_status {u}={status}: {e}"); return False

def disable_user(u):
    ok=_set_status(u,"disabled")
    L.warning(f"{'⛔ DISABLED' if ok else '❌ FAIL'}  {u}  ({BAN_HOURS}h)")
    return ok

def enable_user(u):
    ok=_set_status(u,"active")
    L.info(f"{'✅ ENABLED' if ok else '❌ FAIL'}  {u}")
    return ok

def get_all_users():
    tk=_get_token()
    if not tk: return []
    try:
        r=requests.get(f"{PANEL_URL}/api/users?limit=5000",
            headers={"Authorization":f"Bearer {tk}"},timeout=15,verify=False)
        if r.status_code==200: return r.json().get("users",[])
    except: pass
    return []

_PAT=re.compile(r'(?:from\s+)?(\d{1,3}(?:\.\d{1,3}){3}):\d+\s+accepted.*?email:\s*(\S+)',re.I)
_PRIV=re.compile(r'^(127\.|10\.|172\.1[6-9]\.|172\.2\d\.|172\.3[01]\.|192\.168\.)')

def _clean_user(raw):
    u=raw.split("@")[0] if "@" in raw else raw
    if "." in u:
        p=u.split(".",1)
        if p[0].isdigit(): u=p[1]
    return u

def _parse_log(fp):
    res=[]
    if not os.path.exists(fp): return res
    try:
        sz=os.path.getsize(fp); pos=fpos.get(fp,0)
        if sz<pos: pos=0
        if sz==pos: return res
        with open(fp,"r",errors="ignore") as f:
            f.seek(pos)
            for line in f:
                if "accepted" not in line or "email:" not in line: continue
                m=_PAT.search(line)
                if m:
                    ip,u=m.group(1),_clean_user(m.group(2))
                    if not _PRIV.match(ip): res.append((ip,u))
            fpos[fp]=f.tell()
    except Exception as e: L.debug(f"parse {fp}: {e}")
    return res

def scan_logs():
    recs=_parse_log(os.path.join(LOG_DIR,"access.log"))
    nd=os.path.join(LOG_DIR,"nodes")
    if os.path.isdir(nd):
        for fn in os.listdir(nd):
            if fn.endswith(".log"):
                recs.extend(_parse_log(os.path.join(nd,fn)))
    return recs

class _H(BaseHTTPRequestHandler):
    def do_GET(self):
        p=self.path.split("?")[0]; now=time.time()
        if p=="/health":
            nd=os.path.join(LOG_DIR,"nodes")
            nl=len([f for f in os.listdir(nd) if f.endswith(".log")]) if os.path.isdir(nd) else 0
            self._j(200,{"ok":True,"online":len(uips),"banned":len(banned_users),"node_logs":nl})
        elif p=="/status":
            self._j(200,{u:{"ip_limit":get_limit(u),"count":len(ips),"banned":u in banned_users,
                "unban_in":max(0,round(banned_users[u]-now)) if u in banned_users else 0,
                "ips":{ip:round(now-ts) for ip,ts in ips.items()}} for u,ips in uips.items()})
        elif p=="/banned":
            self._j(200,{u:{"unban_in_seconds":max(0,round(t-now)),
                "unban_at":time.strftime("%Y-%m-%d %H:%M:%S",time.localtime(t))}
                for u,t in banned_users.items()})
        elif p=="/limits": self._j(200,load_limits())
        elif p=="/users":
            users=get_all_users(); lims=load_limits(); now2=time.time()
            OVER_SEC=OVER_MIN*60
            self._j(200,[{"username":u.get("username",""),"status":u.get("status",""),
                "note":u.get("note","") or "",
                "ip_limit":lims.get(u.get("username",""),0),
                "online":len([ip for ip,ts in uips.get(u.get("username",""),{}).items() if now2-ts<=ACTIVE_WIN]),
                "online_total":len(uips.get(u.get("username",""),{})),
                "banned":u.get("username","") in banned_users,
                "unban_in":max(0,round(banned_users.get(u.get("username",""),0)-now2)),
                "watching":u.get("username","") in over_accum,
                "watch_elapsed":round(over_accum.get(u.get("username",""),0)),
                "watch_total":OVER_SEC,
                "ips":[ip for ip,ts in uips.get(u.get("username",""),{}).items() if now2-ts<=ACTIVE_WIN],
                "ips_recent":list(uips.get(u.get("username",""),{}).keys())} for u in users])
        elif p=="/nodes":
            nd=os.path.join(LOG_DIR,"nodes"); result={}; now2=time.time()
            if os.path.isdir(nd):
                for fn in os.listdir(nd):
                    if fn.endswith(".log"):
                        fp=os.path.join(nd,fn)
                        result[fn]={"size":os.path.getsize(fp),
                            "mtime":round(now2-os.path.getmtime(fp)),"pos":fpos.get(fp,0)}
            self._j(200,result)
        else: self._j(404,{"error":"not found"})

    def do_POST(self):
        n=int(self.headers.get("Content-Length",0))
        raw=self.rfile.read(n) if n else b""
        if self.path=="/limits/set":
            try: body=json.loads(raw) if raw else {}
            except: self._j(400,{"error":"invalid json"}); return
            u=body.get("username",""); lim=int(body.get("ip_limit",0))
            if not u: self._j(400,{"error":"username required"}); return
            d=load_limits()
            if lim<=0: d.pop(u,None)
            else: d[u]=lim
            save_limits(d); L.info(f"SET LIMIT  {u} → {lim}")
            self._j(200,{"username":u,"ip_limit":lim})
        elif self.path=="/unban":
            try: body=json.loads(raw) if raw else {}
            except: self._j(400,{"error":"invalid json"}); return
            u=body.get("username","")
            if not u or u not in banned_users:
                self._j(404,{"error":"not banned"}); return
            enable_user(u); banned_users.pop(u,None); uips.pop(u,None)
            over_accum.pop(u,None); was_over.pop(u,None)
            self._j(200,{"unbanned":u})
        elif self.path=="/upload-log":
            node_name=self.headers.get("X-Node-Name","unknown")
            node_name=re.sub(r'[^a-zA-Z0-9_\-]','_',node_name)
            os.makedirs(os.path.join(LOG_DIR,"nodes"),exist_ok=True)
            log_path=os.path.join(LOG_DIR,"nodes",f"{node_name}.log")
            text=raw.decode("utf-8",errors="ignore")
            if text.strip():
                with open(log_path,"a") as f:
                    f.write(text if text.endswith("\n") else text+"\n")
                L.info(f"节点日志 [{node_name}]: +{text.count(chr(10))+1}行")
            self._j(200,{"ok":True,"node":node_name,"bytes":len(text)})
        else: self._j(404,{"error":"not found"})

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def _j(self,code,data):
        b=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length",str(len(b)))
        self._cors(); self.end_headers(); self.wfile.write(b)

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin","*")
        self.send_header("Access-Control-Allow-Methods","GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers","Content-Type,X-Node-Name")

    def log_message(self,*_): pass

def main():
    OVER_SEC=OVER_MIN*60
    L.info("="*60)
    L.info(f"IP Limiter v8 | scan={SCAN}s track={IP_TIMEOUT}s active={ACTIVE_WIN}s over={OVER_MIN}min ban={BAN_HOURS}h")
    L.info(f"  策略: {ACTIVE_WIN}s内有流量的IP计数，累计超限{OVER_MIN}分钟封禁（累计不清零）")
    L.info("="*60)
    srv=HTTPServer(("0.0.0.0",API_PORT),_H)
    threading.Thread(target=srv.serve_forever,daemon=True).start()
    _refresh_uname_cache()
    cycle=0
    while running:
        try:
            now=time.time()
            recs=scan_logs()
            for ip,user in recs:
                if user not in banned_users: uips[user][ip]=now
            for user in list(uips):
                exp=[ip for ip,ts in uips[user].items() if now-ts>IP_TIMEOUT]
                for ip in exp: del uips[user][ip]
                if not uips[user]: del uips[user]
            for user in list(banned_users):
                if now>=banned_users[user]:
                    if enable_user(user):
                        banned_users.pop(user,None); uips.pop(user,None)
                        over_accum.pop(user,None); was_over.pop(user,None)
            all_tracked=set(uips.keys())|set(over_accum.keys())
            for user in list(all_tracked):
                if user in banned_users: continue
                lim=get_limit(user)
                if lim<=0:
                    over_accum.pop(user,None); was_over.pop(user,None); continue
                active_ips={ip:ts for ip,ts in uips.get(user,{}).items() if now-ts<=ACTIVE_WIN}
                cur=len(active_ips)
                is_over=cur>lim
                if is_over:
                    prev=over_accum.get(user,0)
                    over_accum[user]=prev+SCAN
                    total=over_accum[user]
                    if not was_over.get(user,False):
                        L.warning(f"⚠ OVER {user}: {cur}>{lim} 开始累计 IPs:{','.join(active_ips.keys())}")
                    elif int(total)%60<SCAN:
                        pct=min(100,round(total/OVER_SEC*100))
                        L.info(f"⏳ ACCUM {user}: {cur}>{lim} 累计{total:.0f}s/{OVER_SEC}s ({pct}%) IPs:{','.join(active_ips.keys())}")
                    was_over[user]=True
                    if total>=OVER_SEC:
                        L.warning(f"⛔ BAN {user}: {cur}>{lim} 累计超限{total:.0f}s IPs:{','.join(active_ips.keys())}")
                        if disable_user(user):
                            banned_users[user]=now+BAN_HOURS*3600
                            uips.pop(user,None)
                            over_accum.pop(user,None); was_over.pop(user,None)
                else:
                    if was_over.get(user,False):
                        total=over_accum.get(user,0)
                        L.info(f"✅ NORM {user}: {cur}<={lim} 活跃IP恢复，累计{total:.0f}s保留不清零")
                    was_over[user]=False
            cycle+=1
            if cycle%10==0: _refresh_uname_cache()
            if cycle%6==0:
                if uips:
                    L.info("─── 在线 ───")
                    for u,ips in sorted(uips.items()):
                        lim=get_limit(u)
                        active_cnt=len([ip for ip,ts in ips.items() if now-ts<=ACTIVE_WIN])
                        acc=over_accum.get(u,0)
                        acc_info=f" ⏳累计{acc:.0f}s/{OVER_SEC}s" if acc>0 else ""
                        L.info(f"  {u}[活跃{active_cnt}/追踪{len(ips)}/限{lim}]{acc_info}")
        except Exception as e: L.error(f"Loop: {e}",exc_info=True)
        time.sleep(SCAN)
    for u in list(banned_users): enable_user(u)
    L.info("Stopped")

if __name__=="__main__": main()

if __name__=="__main__": main()
PYEOF
  log_ok "IP 限制器后端已写入"

  cat > "$CUSTOM_DIR/panel-plugin.js" << 'JSEOF'
(function(){
  'use strict';
  const API_IPL='/api-ipl'; const REFRESH_MS=15000;
  let _limits={},_status={},_noteMap={};

  async function iplReq(path,opts){
    try{const r=await fetch(API_IPL+path,opts);return r.ok?r.json():null}catch{return null}
  }
  function getPanelToken(){
    for(const st of[localStorage,sessionStorage]){
      try{
        for(let i=0;i<st.length;i++){
          const v=st.getItem(st.key(i));
          if(v&&v.startsWith('eyJ'))return v;
          try{const p=JSON.parse(v);if(p&&(p.token||p.access_token))return p.token||p.access_token}catch(e){}
        }
      }catch(e){}
    }
    const m=document.cookie.match(/(?:token|access_token)=([^;]+)/);return m?m[1]:null;
  }
  async function refreshIplData(){
    const[lim,st]=await Promise.all([iplReq('/limits'),iplReq('/status')]);
    if(lim&&typeof lim==='object')_limits=lim;
    if(st&&typeof st==='object')_status=st;
  }
  async function saveIpLimit(username,ip_limit){
    const r=await iplReq('/limits/set',{method:'POST',headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username,ip_limit:parseInt(ip_limit)||0})});
    if(r)_limits[username]=parseInt(ip_limit)||0;return r;
  }
  function esc(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
  function injectLimitField(modal,username){
    if(modal.querySelector('#mz-ip-box')||!username)return;
    const limit=_limits[username]||0,st=_status[username]||{};
    const online=st.count||0,banned=!!st.banned,ips=st.ips?Object.keys(st.ips):[];
    const clr=banned?'#ef4444':online>0?'#22c55e':'#6b7280';
    let txt=banned?`🚫 封禁中（${Math.floor((st.unban_in||0)/3600)}时${Math.floor(((st.unban_in||0)%3600)/60)}分后解封）`
      :`当前: ${online} 个IP在线${ips.length?'（'+ips.join(', ')+'）':''}`;
    const box=document.createElement('div');
    box.id='mz-ip-box';
    box.style.cssText='margin:16px 0 12px;padding:14px 16px;background:rgba(255,193,7,0.07);border:1px solid rgba(255,193,7,0.35);border-radius:10px';
    box.innerHTML=`<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">
      <span style="font-weight:600;font-size:14px">🔒 IP 并发限制</span>
      <span style="font-size:12px;color:${clr};font-weight:600" title="${esc(txt)}">${esc(txt)}</span></div>
      <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <input id="mz-ip-val" type="number" min="0" max="99" value="${limit}" placeholder="0"
        style="width:72px;padding:6px 10px;border-radius:6px;border:1px solid #4b5563;background:transparent;color:inherit;font-size:15px;text-align:center;outline:none">
      <span style="font-size:12px;color:#6b7280">0=不限 1=单设备 2+=多设备</span>
      <button id="mz-ip-btn" style="margin-left:auto;padding:6px 18px;border-radius:6px;background:#2563eb;color:#fff;border:none;cursor:pointer;font-size:13px;font-weight:600">保存</button></div>
      <div id="mz-ip-msg" style="font-size:12px;margin-top:8px;min-height:16px"></div>`;
    const fc=modal.querySelector('textarea')?.closest('[class*="FormControl"],[class*="form-control"],.chakra-form-control');
    if(fc)fc.parentNode.insertBefore(box,fc);
    else(modal.querySelector('[class*="body"],[class*="Body"],form')||modal).appendChild(box);
    document.getElementById('mz-ip-btn').onclick=async()=>{
      const val=document.getElementById('mz-ip-val').value;
      const msg=document.getElementById('mz-ip-msg'),btn=document.getElementById('mz-ip-btn');
      btn.disabled=true;btn.textContent='保存中...';
      const r=await saveIpLimit(username,val);
      btn.disabled=false;btn.textContent='保存';
      const n=parseInt(val)||0;
      if(r)msg.innerHTML=`<span style="color:#22c55e">✔ 已保存（${n>0?n+'个IP限制':'无限制'}）</span>`;
      else msg.innerHTML=`<span style="color:#ef4444">✘ 保存失败</span>`;
      setTimeout(()=>{const m2=document.getElementById('mz-ip-msg');if(m2)m2.textContent=''},3000);
    };
  }
  async function fetchNotes(){
    const tk=getPanelToken();if(!tk)return;
    try{
      const r=await fetch('/api/users?limit=500',{headers:{Authorization:'Bearer '+tk}});
      if(!r.ok)return;const d=await r.json();const m={};
      (d.users||[]).forEach(u=>{m[u.username]=(u.note||u.remark||'').trim()});_noteMap=m;
    }catch(e){}
  }
  function getUsername(td){
    const el=td.querySelector('[class*="name"],[class*="user"],b,strong');
    if(el)return el.textContent.trim().split(/\s+/)[0];
    const container=td.querySelector('[class*="flex"]')||td;
    for(let i=0;i<container.childNodes.length;i++){
      const node=container.childNodes[i];
      if(node.nodeType===3){const t=node.textContent.trim();if(t&&t.length<64)return t}
    }
    const clone=container.cloneNode(true);
    clone.querySelectorAll('p,div,span,br').forEach(e=>e.remove());
    return clone.textContent.trim().split(/\s+/)[0]||'';
  }
  let _noteLayer=null;
  function ensureNoteLayer(){
    if(!_noteLayer||!document.body.contains(_noteLayer)){
      _noteLayer=document.createElement('div');_noteLayer.id='mzp-note-layer';
      _noteLayer.style.cssText='position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:8888;overflow:hidden;';
      document.body.appendChild(_noteLayer);
    }
    return _noteLayer;
  }
  if(!document.getElementById('mzp-css')){
    const css=document.createElement('style');css.id='mzp-css';
    css.textContent='#mzp-note-layer .mzp-note{position:absolute;font-size:13px;font-weight:700;color:#3182CE;pointer-events:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;line-height:1.3}';
    document.head.appendChild(css);
  }
  let _redrawTimer=null;
  function redrawNotes(){
    const lyr=ensureNoteLayer();
    if(Object.keys(_noteMap).length===0){lyr.innerHTML='';return}
    const frag=document.createDocumentFragment();
    document.querySelectorAll('tr').forEach(row=>{
      if(row.querySelector('th'))return;
      const cells=row.querySelectorAll('td');if(cells.length<2)return;
      const uname=getUsername(cells[0]);
      if(!uname||!_noteMap.hasOwnProperty(uname))return;
      const note=_noteMap[uname];if(!note)return;
      const rect=cells[0].getBoundingClientRect();
      if(rect.width<1||rect.height<1)return;
      const lbl=document.createElement('div');lbl.className='mzp-note';
      lbl.textContent=note.length>22?note.slice(0,22)+'…':note;lbl.title=note;
      lbl.style.left=(rect.left+40)+'px';lbl.style.top=(rect.top+rect.height*0.60)+'px';
      lbl.style.maxWidth=(rect.width-48)+'px';frag.appendChild(lbl);
    });
    lyr.innerHTML='';lyr.appendChild(frag);
  }
  function scheduleRedraw(d){clearTimeout(_redrawTimer);_redrawTimer=setTimeout(redrawNotes,d||120)}
  const _observer=new MutationObserver(muts=>{
    for(const mut of muts){
      for(const node of mut.addedNodes){
        if(node.nodeType!==1)continue;
        const modal=node.matches?.('[role="dialog"]')?node:node.querySelector?.('[role="dialog"]');
        if(!modal)continue;
        setTimeout(async()=>{
          await refreshIplData();let username='';
          modal.querySelectorAll('input').forEach(inp=>{
            if((inp.readOnly||inp.disabled)&&inp.value?.trim()&&!username)username=inp.value.trim();
          });
          if(!username){const m=location.href.match(/\/users?\/([^/?#]+)/i);if(m)username=decodeURIComponent(m[1])}
          if(!username)modal.querySelectorAll('input').forEach(inp=>{
            if(inp.value?.trim()&&!inp.type?.match(/date|number|checkbox/)&&!username)username=inp.value.trim();
          });
          if(username)injectLimitField(modal,username);
        },500);
      }
    }
    for(const m of muts){
      if(_noteLayer&&(_noteLayer===m.target||_noteLayer.contains(m.target)))return;
    }
    scheduleRedraw(180);
  });
  _observer.observe(document.body,{childList:true,subtree:true});
  window.addEventListener('scroll',()=>scheduleRedraw(60),true);
  window.addEventListener('resize',()=>scheduleRedraw(60));
  async function refresh(){await Promise.all([refreshIplData(),fetchNotes()]);redrawNotes()}
  setTimeout(refresh,1800);setInterval(refresh,REFRESH_MS);
  console.log('[MarzbanPlugin v4] IP并发限制UI + 备注显示 已加载');
})();
JSEOF
  log_ok "面板 UI 插件已写入"

  local NGINX_CONF="/etc/nginx/sites-available/marzban"
  _inject_nginx_ipl() {
    python3 << PYEOF
import re
try:
    with open("${NGINX_CONF}","r") as f: content=f.read()
except: print("NO_CONF"); exit()
changed=False
if 'panel-plugin.js' not in content and 'sub_filter' not in content:
    inject="""
        sub_filter '</body>' '<script src="/mz-plugin/panel-plugin.js"></script></body>';
        sub_filter_once on;
        sub_filter_types text/html;"""
    for marker in ['proxy_read_timeout','proxy_set_header Connection','proxy_pass']:
        pat=rf'({re.escape(marker)}[^\n]+\n)'
        matches=list(re.finditer(pat,content))
        if matches:
            last=matches[-1]
            content=content[:last.end()]+inject+"\n"+content[last.end():]
            changed=True; break
extra="""
    location /api-ipl/ {
        proxy_pass http://127.0.0.1:9191/;
        proxy_set_header Host \$host;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods "GET,POST,OPTIONS";
        add_header Access-Control-Allow-Headers "Content-Type,X-Node-Name";
    }
    location /mz-plugin/ {
        alias /opt/marzban/custom/;
        add_header Access-Control-Allow-Origin *;
    }
"""
if '/api-ipl/' not in content:
    content=content.rstrip().rstrip('}')+"\n"+extra+"}\n"; changed=True
with open("${NGINX_CONF}","w") as f: f.write(content)
print("changed" if changed else "ok")
PYEOF
  }

  if [[ -f "$NGINX_CONF" ]]; then
    RESULT=$(_inject_nginx_ipl)
    [[ "$RESULT" == "changed" ]] && log_ok "Nginx 配置已更新" || log_ok "Nginx 配置已是最新"
  else
    log_warn "未找到 $NGINX_CONF，请手动配置 Nginx sub_filter"
  fi

  apt-get install -y -q nginx-extras 2>/dev/null || true
  nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null && log_ok "Nginx 已重启"

  iptables -I INPUT -p tcp --dport 9191 -j ACCEPT 2>/dev/null || true
  log_ok "iptables 已开放 9191 端口"

  cat > /etc/systemd/system/marzban-ip-limiter.service << SEOF
[Unit]
Description=Marzban IP Limiter v8 (活跃窗口+累计超限)
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
Environment=LOG_DIR=${LOG_DIR}
Environment=LIMITS_FILE=${BASE_DIR}/user_limits.json
Environment=PANEL_URL=http://127.0.0.1:${PANEL_PORT}
Environment=PANEL_USER=${PANEL_USER}
Environment=PANEL_PASS=${PANEL_PASS}
Environment=SCAN_INTERVAL=10
Environment=IP_TIMEOUT=600
Environment=ACTIVE_WINDOW=180
Environment=OVER_MINUTES=5
Environment=BAN_HOURS=${BAN_HOURS}
Environment=API_PORT=9191
ExecStart=/usr/bin/python3 ${BASE_DIR}/ip_limiter.py
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SEOF

  cat > "$BASE_DIR/install-node-push.sh" << 'NPEOF'
#!/usr/bin/env bash
NODE_NAME="${1}"; PANEL_HOST="${2}"
[[ -z "$NODE_NAME" || -z "$PANEL_HOST" ]] && {
    echo "用法: bash install-node-push.sh <节点名> <面板IP:9191>"
    exit 1
}
mkdir -p /opt/marzban-push
cat > /opt/marzban-push/push.sh << PUSHEOF
#!/usr/bin/env bash
NODE_NAME="${NODE_NAME}"; PANEL_HOST="${PANEL_HOST}"
LOG_FILE="/var/lib/marzban/logs/access.log"; INTERVAL=10
POS_FILE="/tmp/mznp_$(echo "${NODE_NAME}"|tr -cd 'a-zA-Z0-9_').pos"
echo "节点日志推送: \${NODE_NAME} → \${PANEL_HOST}"
while true; do
    if [[ -f "\${LOG_FILE}" ]]; then
        SZ=\$(wc -c < "\${LOG_FILE}" 2>/dev/null||echo 0)
        POS=\$(cat "\${POS_FILE}" 2>/dev/null||echo 0)
        [[ \${SZ} -lt \${POS} ]] && POS=0
        if [[ \${SZ} -gt \${POS} ]]; then
            LINES=\$(tail -c +\$((\${POS}+1)) "\${LOG_FILE}" 2>/dev/null|grep -E "accepted.*email:"|head -500)
            if [[ -n "\${LINES}" ]]; then
                RESP=\$(curl -s --max-time 8 -X POST "http://\${PANEL_HOST}/upload-log" \
                    -H "X-Node-Name: \${NODE_NAME}" -H "Content-Type: text/plain" \
                    --data-raw "\${LINES}" 2>/dev/null)
                echo "[\$(date '+%H:%M:%S')] 推送 \$(echo "\${LINES}"|wc -l)行 → \${RESP}"
            fi
            echo "\${SZ}" > "\${POS_FILE}"
        fi
    fi
    sleep "\${INTERVAL}"
done
PUSHEOF
chmod +x /opt/marzban-push/push.sh
SVCNAME="marzban-push-$(echo "$NODE_NAME"|tr '[:upper:]' '[:lower:]'|tr ' ' '-')"
cat > "/etc/systemd/system/${SVCNAME}.service" << SVCEOF
[Unit]
Description=Marzban Node Log Push (${NODE_NAME})
After=network-online.target
[Service]
Type=simple
Restart=always
RestartSec=10
ExecStart=/bin/bash /opt/marzban-push/push.sh
[Install]
WantedBy=multi-user.target
SVCEOF
systemctl daemon-reload
systemctl enable "${SVCNAME}"
systemctl restart "${SVCNAME}"
sleep 3
echo "✅ 节点推送已配置: ${SVCNAME}"
NPEOF
  chmod +x "$BASE_DIR/install-node-push.sh"

  cat > /usr/local/bin/ip-manage << 'MEOF'
#!/usr/bin/env bash
API="http://127.0.0.1:9191"; C="-s --max-time 5"
case "${1:-help}" in
  list) curl $C "$API/limits"|python3 -c "
import sys,json; d=json.load(sys.stdin)
if not d: print('  (无限制)')
else:
  for u,v in sorted(d.items()): print(f'  {u:<25} 限制:{v}个IP')" 2>/dev/null||echo "连接失败";;
  set) [[ -z "$2"||"-z $3" ]]&&{echo "用法: ip-manage set <用户> <N>";exit 1}
    curl $C -X POST "$API/limits/set" -H "Content-Type:application/json" \
      -d "{\"username\":\"$2\",\"ip_limit\":$3}"|python3 -c "
import sys,json; d=json.load(sys.stdin)
print(f'✅ {d[\"username\"]}: 限制{d[\"ip_limit\"]}个IP')" 2>/dev/null||echo "失败";;
  online) curl $C "$API/status"|python3 -c "
import sys,json; d=json.load(sys.stdin)
if not d: print('  (无在线用户)')
for u,i in sorted(d.items()):
  ban='🚫' if i.get('banned') else '✅'
  ips=', '.join(i.get('ips',{}).keys())
  print(f'  {ban} {u:<20}[{i[\"count\"]}/{i[\"ip_limit\"]}] {ips}')" 2>/dev/null||echo "连接失败";;
  banned) curl $C "$API/banned"|python3 -c "
import sys,json; d=json.load(sys.stdin)
if not d: print('  (无封禁用户)')
for u,i in sorted(d.items()):
  s=i.get('unban_in_seconds',0)
  print(f'  🚫 {u:<20} 剩余{int(s//3600)}时{int((s%3600)//60)}分 解封:{i.get(\"unban_at\")}')" 2>/dev/null||echo "连接失败";;
  unban) [[ -z "$2" ]]&&{echo "用法: ip-manage unban <用户>";exit 1}
    curl $C -X POST "$API/unban" -H "Content-Type:application/json" \
      -d "{\"username\":\"$2\"}"|python3 -c "
import sys,json; d=json.load(sys.stdin)
print(f'✅ 已解封:{d[\"unbanned\"]}' if 'unbanned' in d else f'❌ {d.get(\"error\")}')" 2>/dev/null||echo "失败";;
  nodes) curl $C "$API/nodes"|python3 -c "
import sys,json; d=json.load(sys.stdin)
if not d: print('  (无节点日志)')
for fn,i in sorted(d.items()):
  age=i.get('mtime',0); s='✅' if age<60 else '⚠' if age<300 else '❌'
  print(f'  {s} {fn:<22} {i[\"size\"]}B 更新:{age}秒前')" 2>/dev/null||echo "连接失败";;
  status) curl $C "$API/health"|python3 -c "
import sys,json; d=json.load(sys.stdin)
print(f'在线:{d[\"online\"]} 封禁:{d[\"banned\"]} 节点日志:{d.get(\"node_logs\",0)}')" 2>/dev/null||echo "服务未运行";;
  *) cat<<'HELP'
ip-manage list              查看所有用户 IP 限制
ip-manage set <用户> <N>    设置最多 N 个 IP
ip-manage online            查看在线用户
ip-manage banned            查看封禁中用户
ip-manage unban <用户>      手动解封
ip-manage nodes             查看节点日志推送状态
ip-manage status            服务状态
HELP
    ;;
esac
MEOF
  chmod +x /usr/local/bin/ip-manage

  systemctl daemon-reload
  systemctl enable marzban-ip-limiter 2>/dev/null
  systemctl restart marzban-ip-limiter
  sleep 3

  local SVC; SVC=$(systemctl is-active marzban-ip-limiter 2>/dev/null)
  local API_OK=false
  curl -s --max-time 3 http://127.0.0.1:9191/health 2>/dev/null | grep -q '"ok"' && API_OK=true

  echo
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  ✅  IP 限制器安装完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  限制器服务:  $( [[ "$SVC" == "active" ]] && echo "${G}active ✓${NC}" || echo "${R}${SVC}${NC}" )"
  echo -e "  API 接口:    $( $API_OK && echo "${G}正常 ✓${NC}" || echo "${R}异常${NC}" )"
  echo -e "  封禁时长:    ${W}${BAN_HOURS} 小时${NC}"
  echo
  echo -e "  ${C}防误封机制（活跃窗口+累计超限）：${NC}"
  echo -e "  ${DIM}· 活跃窗口 180s → 3分钟内有流量的IP才计数${NC}"
  echo -e "  ${DIM}· 累计超限 5分钟 → 超限时间累计，不因短暂恢复清零${NC}"
  echo -e "  ${DIM}· 多设备轮流规避：累计满5分钟仍封禁${NC}"
  echo
  echo -e "  ${Y}运行选项7可安装 Web 可视化管理面板${NC}"
  echo
  PANEL_IP=$(ip route get 1 2>/dev/null | awk '{print $7;exit}' || echo "面板IP")
  echo -e "  节点推送（在节点服务器执行）:"
  echo -e "  ${DIM}bash /opt/marzban/ip-limiter/install-node-push.sh \"节点名\" \"${PANEL_IP}:9191\"${NC}"
  echo
  read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 7 - 安装 IP 限制器管理面板（Web可视化）
# ══════════════════════════════════════════════════════════════
install_ip_dashboard() {
  show_banner
  echo -e "\n${G}┌─ ${W}安装 IP 限制器管理面板（Web可视化）${G}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  local ENV_FILE="/opt/marzban/.env"
  local NGINX_CONF="/etc/nginx/sites-available/marzban"
  local CUSTOM_DIR="/opt/marzban/custom"
  local HTPASSWD_FILE="/etc/nginx/.ipl_htpasswd"
  local STATIC_PORT=9292
  local PANEL_PORT=8000
  local DASH_PATH="/ipl-admin"

  # ── 自动读取面板配置 ──
  local PANEL_DOMAIN="" USER_DEFAULT="admin"
  if [[ -f "$ENV_FILE" ]]; then
    PANEL_DOMAIN=$(grep -oP 'XRAY_SUBSCRIPTION_URL_PREFIX=https://\K[^/\s]+' "$ENV_FILE" 2>/dev/null | head -1 || true)
    local _U; _U=$(grep -oP 'SUDO_USERNAME=\K\S+' "$ENV_FILE" 2>/dev/null | head -1 || true)
    [[ -n "$_U" ]] && USER_DEFAULT="$_U"
    local _P; _P=$(grep -oP 'UVICORN_PORT=\K\S+' "$ENV_FILE" 2>/dev/null | head -1 || true)
    [[ -n "$_P" ]] && PANEL_PORT="$_P"
    log_ok "读取面板配置：域名=${PANEL_DOMAIN:-未检测} 账号=${USER_DEFAULT}"
  fi

  echo
  echo -e "  ${B}┌─ ${W}第1步：面板域名 ${B}─${NC}"
  read -rp "$(echo -e "  ${C}域名（回车确认：${PANEL_DOMAIN:-留空}）: ${NC}")" INPUT
  [[ -n "$INPUT" ]] && PANEL_DOMAIN="$INPUT"
  [[ -z "$PANEL_DOMAIN" ]] && die "域名不能为空"

  echo
  echo -e "  ${B}┌─ ${W}第2步：访问路径 ${B}─${NC}"
  echo -e "  ${DIM}建议使用不易被猜测的路径，如 /my-ipl-2025${NC}"
  read -rp "$(echo -e "  ${C}访问路径（默认 /ipl-admin）: ${NC}")" INPUT
  [[ -n "$INPUT" ]] && DASH_PATH="$INPUT"
  [[ "$DASH_PATH" != /* ]] && DASH_PATH="/${DASH_PATH}"

  echo
  echo -e "  ${B}┌─ ${W}第3步：登录用户名 ${B}─${NC}"
  read -rp "$(echo -e "  ${C}用户名（默认 ${USER_DEFAULT}）: ${NC}")" DASH_USER
  [[ -z "$DASH_USER" ]] && DASH_USER="$USER_DEFAULT"

  echo
  echo -e "  ${B}┌─ ${W}第4步：登录密码 ${B}─${NC}"
  echo -e "  ${DIM}此密码用于访问 IP 管理面板，与 Marzban 密码无关${NC}"
  local DASH_PASS DASH_PASS2
  while true; do
    read -rsp "$(echo -e "  ${C}密码（至少6位）: ${NC}")" DASH_PASS; echo
    [[ ${#DASH_PASS} -ge 6 ]] && break
    log_err "密码至少需要6位，请重新输入"
  done
  read -rsp "$(echo -e "  ${C}确认密码: ${NC}")" DASH_PASS2; echo
  [[ "$DASH_PASS" != "$DASH_PASS2" ]] && die "两次密码不一致，请重新运行"

  echo
  echo -e "${B}  ─────────────────────────────────────────────${NC}"
  echo -e "  面板域名 : ${W}${PANEL_DOMAIN}${NC}"
  echo -e "  访问地址 : ${W}https://${PANEL_DOMAIN}${DASH_PATH}/${NC}"
  echo -e "  用户名   : ${W}${DASH_USER}${NC}"
  echo -e "  密  码   : ${W}$(printf '*%.0s' $(seq 1 ${#DASH_PASS}))${NC}"
  echo -e "${B}  ─────────────────────────────────────────────${NC}"
  echo
  read -rp "$(echo -e "  ${Y}确认安装? [Y/n]: ${NC}")" CONFIRM
  [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && return

  log_step "安装依赖"
  apt-get install -y -q apache2-utils python3 2>/dev/null || true
  command -v htpasswd &>/dev/null || die "apache2-utils 安装失败，请手动执行: apt install apache2-utils"
  log_ok "依赖就绪"

  log_step "写入管理面板 HTML"
  mkdir -p "$CUSTOM_DIR"
  python3 -c "
import base64
html = 'PCFET0NUWVBFIGh0bWw+CjxodG1sIGxhbmc9InpoLUNOIj4KPGhlYWQ+CjxtZXRhIGNoYXJzZXQ9IlVURi04Ij4KPG1ldGEgbmFtZT0idmlld3BvcnQiIGNvbnRlbnQ9IndpZHRoPWRldmljZS13aWR0aCxpbml0aWFsLXNjYWxlPTEiPgo8dGl0bGU+SVAg6ZmQ5Yi25Zmo566h55CGPC90aXRsZT4KPHN0eWxlPgpAaW1wb3J0IHVybCgnaHR0cHM6Ly9mb250cy5nb29nbGVhcGlzLmNvbS9jc3MyP2ZhbWlseT1KZXRCcmFpbnMrTW9ubzp3Z2h0QDQwMDs2MDAmZmFtaWx5PVNvcmE6d2dodEAzMDA7NDAwOzUwMDs2MDAmZGlzcGxheT1zd2FwJyk7Cip7Ym94LXNpemluZzpib3JkZXItYm94O21hcmdpbjowO3BhZGRpbmc6MH0KOnJvb3R7CiAgLS1iZzojMDcwOTBmOy0tYmcyOiMwZDExMTc7LS1iZzM6IzExMTgyNzsKICAtLWNhcmQ6IzExMTgyNzstLWNhcmQyOiMxNjFkMmU7LS1jYXJkMzojMWMyNDM2OwogIC0tYm9yZGVyOnJnYmEoMjU1LDI1NSwyNTUsMC4wNik7LS1ib3JkZXIyOnJnYmEoMjU1LDI1NSwyNTUsMC4xKTsKICAtLXRleHQ6I2UyZThmMDstLXRleHQyOiM5NGEzYjg7LS10ZXh0MzojNDc1NTY5OwogIC0tYmx1ZTojMzhiZGY4Oy0tYmx1ZTI6IzAyODRjNzstLWJsdWVkaW06cmdiYSg1NiwxODksMjQ4LDAuMDgpOy0tYmx1ZWdsb3c6cmdiYSg1NiwxODksMjQ4LDAuMTUpOwogIC0tZ3JlZW46IzRhZGU4MDstLWdyZWVuZGltOnJnYmEoNzQsMjIyLDEyOCwwLjA4KTsKICAtLXJlZDojZjg3MTcxOy0tcmVkZGltOnJnYmEoMjQ4LDExMywxMTMsMC4wOCk7CiAgLS1hbWJlcjojZmJiZjI0Oy0tYW1iZXJkaW06cmdiYSgyNTEsMTkxLDM2LDAuMDgpOwogIC0tcjoxMHB4Oy0tcjI6N3B4Oy0tcjM6NXB4OwogIC0tZm9udDonU29yYScsc2Fucy1zZXJpZjstLW1vbm86J0pldEJyYWlucyBNb25vJyxtb25vc3BhY2U7Cn0KaHRtbHtiYWNrZ3JvdW5kOnZhcigtLWJnKX0KYm9keXtmb250LWZhbWlseTp2YXIoLS1mb250KTtmb250LXNpemU6MTRweDtjb2xvcjp2YXIoLS10ZXh0KTttaW4taGVpZ2h0OjEwMHZoOwogIGJhY2tncm91bmQ6dmFyKC0tYmcpIHJhZGlhbC1ncmFkaWVudChlbGxpcHNlIDgwJSA1MCUgYXQgNTAlIC0yMCUscmdiYSg1NiwxODksMjQ4LDAuMDQpLHRyYW5zcGFyZW50KX0KOjotd2Via2l0LXNjcm9sbGJhcnt3aWR0aDo0cHg7aGVpZ2h0OjRweH0KOjotd2Via2l0LXNjcm9sbGJhci10cmFja3tiYWNrZ3JvdW5kOnRyYW5zcGFyZW50fQo6Oi13ZWJraXQtc2Nyb2xsYmFyLXRodW1ie2JhY2tncm91bmQ6dmFyKC0tYm9yZGVyMik7Ym9yZGVyLXJhZGl1czoycHh9Ci5oZWFkZXJ7YmFja2dyb3VuZDpyZ2JhKDEzLDE3LDIzLDAuOSk7YmFja2Ryb3AtZmlsdGVyOmJsdXIoMTJweCk7Ym9yZGVyLWJvdHRvbToxcHggc29saWQgdmFyKC0tYm9yZGVyKTsKICBwYWRkaW5nOjAgMjhweDtoZWlnaHQ6NThweDtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2p1c3RpZnktY29udGVudDpzcGFjZS1iZXR3ZWVuOwogIHBvc2l0aW9uOnN0aWNreTt0b3A6MDt6LWluZGV4OjEwMH0KLmhsb2dve2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjEwcHh9Ci5obG9nby1pY29ue3dpZHRoOjMycHg7aGVpZ2h0OjMycHg7Ym9yZGVyLXJhZGl1czo4cHg7CiAgYmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoMTM1ZGVnLHZhcigtLWJsdWUyKSx2YXIoLS1ibHVlKSk7CiAgZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6Y2VudGVyO2JveC1zaGFkb3c6MCAwIDE2cHggdmFyKC0tYmx1ZWdsb3cpfQouaGxvZ28taWNvbiBzdmd7d2lkdGg6MTZweDtoZWlnaHQ6MTZweDtmaWxsOiNmZmZ9Ci5odGl0bGV7Zm9udC1zaXplOjE1cHg7Zm9udC13ZWlnaHQ6NjAwO2xldHRlci1zcGFjaW5nOi0uM3B4fQouaHN1Yntmb250LXNpemU6MTFweDtjb2xvcjp2YXIoLS10ZXh0Myk7Zm9udC1mYW1pbHk6dmFyKC0tbW9ubyk7bWFyZ2luLXRvcDoxcHh9Ci5ocmlnaHR7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6OHB4fQouYmFkZ2UtbGl2ZXtiYWNrZ3JvdW5kOnZhcigtLWdyZWVuZGltKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzQsMjIyLDEyOCwwLjIpO2NvbG9yOnZhcigtLWdyZWVuKTsKICBwYWRkaW5nOjRweCAxMnB4O2JvcmRlci1yYWRpdXM6MjBweDtmb250LXNpemU6MTFweDtmb250LXdlaWdodDo1MDA7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6NXB4fQouZG90LXB1bHNle3dpZHRoOjVweDtoZWlnaHQ6NXB4O2JvcmRlci1yYWRpdXM6NTAlO2JhY2tncm91bmQ6dmFyKC0tZ3JlZW4pO2FuaW1hdGlvbjpkcCAxLjhzIGVhc2UtaW4tb3V0IGluZmluaXRlfQpAa2V5ZnJhbWVzIGRwezAlLDEwMCV7b3BhY2l0eToxO3RyYW5zZm9ybTpzY2FsZSgxKX01MCV7b3BhY2l0eTouMzt0cmFuc2Zvcm06c2NhbGUoLjcpfX0KLmJ0bntkaXNwbGF5OmlubGluZS1mbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6NXB4O3BhZGRpbmc6NnB4IDE0cHg7Ym9yZGVyLXJhZGl1czp2YXIoLS1yMik7CiAgZm9udC1zaXplOjEycHg7Zm9udC13ZWlnaHQ6NTAwO2N1cnNvcjpwb2ludGVyO2JvcmRlcjoxcHggc29saWQgdmFyKC0tYm9yZGVyMik7CiAgYmFja2dyb3VuZDp2YXIoLS1jYXJkMik7Y29sb3I6dmFyKC0tdGV4dDIpO3RyYW5zaXRpb246YWxsIC4xNXM7Zm9udC1mYW1pbHk6dmFyKC0tZm9udCl9Ci5idG46aG92ZXJ7Ym9yZGVyLWNvbG9yOnZhcigtLWJsdWUpO2NvbG9yOnZhcigtLWJsdWUpO2JhY2tncm91bmQ6dmFyKC0tYmx1ZWRpbSl9Ci5idG4tc217cGFkZGluZzozcHggMTBweDtmb250LXNpemU6MTFweH0KLmJ0bi1yZWR7YmFja2dyb3VuZDp2YXIoLS1yZWRkaW0pO2NvbG9yOnZhcigtLXJlZCk7Ym9yZGVyLWNvbG9yOnJnYmEoMjQ4LDExMywxMTMsMC4yKX0KLmJ0bi1yZWQ6aG92ZXJ7YmFja2dyb3VuZDpyZ2JhKDI0OCwxMTMsMTEzLDAuMTUpO2JvcmRlci1jb2xvcjp2YXIoLS1yZWQpfQouYnRuLWdyZWVue2JhY2tncm91bmQ6dmFyKC0tZ3JlZW5kaW0pO2NvbG9yOnZhcigtLWdyZWVuKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoNzQsMjIyLDEyOCwwLjIpOwogIHBhZGRpbmc6NHB4IDEycHg7Ym9yZGVyLXJhZGl1czp2YXIoLS1yMik7Zm9udC1zaXplOjEycHg7Y3Vyc29yOnBvaW50ZXI7Zm9udC1mYW1pbHk6dmFyKC0tZm9udCk7dHJhbnNpdGlvbjphbGwgLjE1c30KLmJ0bi1ncmVlbjpob3ZlcntiYWNrZ3JvdW5kOnJnYmEoNzQsMjIyLDEyOCwwLjE1KTtib3JkZXItY29sb3I6dmFyKC0tZ3JlZW4pfQoubWFpbntwYWRkaW5nOjI0cHggMjhweDttYXgtd2lkdGg6MTI4MHB4O21hcmdpbjowIGF1dG99Ci5zdGF0c3tkaXNwbGF5OmdyaWQ7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOnJlcGVhdCg0LDFmcik7Z2FwOjE0cHg7bWFyZ2luLWJvdHRvbToyNHB4fQouc3RhdHtiYWNrZ3JvdW5kOnZhcigtLWNhcmQpO2JvcmRlcjoxcHggc29saWQgdmFyKC0tYm9yZGVyKTtib3JkZXItcmFkaXVzOnZhcigtLXIpOwogIHBhZGRpbmc6MThweCAyMHB4O3Bvc2l0aW9uOnJlbGF0aXZlO292ZXJmbG93OmhpZGRlbjt0cmFuc2l0aW9uOmJvcmRlci1jb2xvciAuMnN9Ci5zdGF0OmhvdmVye2JvcmRlci1jb2xvcjp2YXIoLS1ib3JkZXIyKX0KLnN0YXQ6OmJlZm9yZXtjb250ZW50OicnO3Bvc2l0aW9uOmFic29sdXRlO3RvcDowO2xlZnQ6MDtyaWdodDowO2hlaWdodDoycHg7CiAgYmFja2dyb3VuZDpsaW5lYXItZ3JhZGllbnQoOTBkZWcsdHJhbnNwYXJlbnQsdmFyKC0tYWMsdmFyKC0tYmx1ZSkpLHRyYW5zcGFyZW50KTtvcGFjaXR5Oi42fQoucy1iey0tYWM6dmFyKC0tYmx1ZSl9LnMtZ3stLWFjOnZhcigtLWdyZWVuKX0ucy1yey0tYWM6dmFyKC0tcmVkKX0ucy1hey0tYWM6dmFyKC0tYW1iZXIpfQouc3RhdC10b3B7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6c3BhY2UtYmV0d2VlbjttYXJnaW4tYm90dG9tOjEycHh9Ci5zdGF0LWxhYmVse2ZvbnQtc2l6ZToxMXB4O2NvbG9yOnZhcigtLXRleHQzKTt0ZXh0LXRyYW5zZm9ybTp1cHBlcmNhc2U7bGV0dGVyLXNwYWNpbmc6LjhweDtmb250LXdlaWdodDo1MDB9Ci5zaXt3aWR0aDoyOHB4O2hlaWdodDoyOHB4O2JvcmRlci1yYWRpdXM6NnB4O2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OmNlbnRlcjtmb250LXNpemU6MTNweH0KLnNpLWJ7YmFja2dyb3VuZDp2YXIoLS1ibHVlZGltKTtjb2xvcjp2YXIoLS1ibHVlKX0uc2ktZ3tiYWNrZ3JvdW5kOnZhcigtLWdyZWVuZGltKTtjb2xvcjp2YXIoLS1ncmVlbil9Ci5zaS1ye2JhY2tncm91bmQ6dmFyKC0tcmVkZGltKTtjb2xvcjp2YXIoLS1yZWQpfS5zaS1he2JhY2tncm91bmQ6dmFyKC0tYW1iZXJkaW0pO2NvbG9yOnZhcigtLWFtYmVyKX0KLnN0YXQtdmFse2ZvbnQtc2l6ZTozMnB4O2ZvbnQtd2VpZ2h0OjYwMDtsaW5lLWhlaWdodDoxO2ZvbnQtZmFtaWx5OnZhcigtLW1vbm8pfQouY3YtYntjb2xvcjp2YXIoLS1ibHVlKX0uY3YtZ3tjb2xvcjp2YXIoLS1ncmVlbil9LmN2LXJ7Y29sb3I6dmFyKC0tcmVkKX0uY3YtYXtjb2xvcjp2YXIoLS1hbWJlcil9Ci5zdGF0LXN1Yntmb250LXNpemU6MTFweDtjb2xvcjp2YXIoLS10ZXh0Myk7bWFyZ2luLXRvcDo2cHh9Ci50YWJzLWJhcntkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO21hcmdpbi1ib3R0b206MThweH0KLnRhYnN7ZGlzcGxheTpmbGV4O2dhcDoycHg7YmFja2dyb3VuZDp2YXIoLS1jYXJkKTtib3JkZXI6MXB4IHNvbGlkIHZhcigtLWJvcmRlcik7Ym9yZGVyLXJhZGl1czp2YXIoLS1yKTtwYWRkaW5nOjNweH0KLnRhYntwYWRkaW5nOjdweCAxOHB4O2JvcmRlci1yYWRpdXM6N3B4O2N1cnNvcjpwb2ludGVyO2ZvbnQtc2l6ZToxM3B4O2ZvbnQtd2VpZ2h0OjUwMDsKICBjb2xvcjp2YXIoLS10ZXh0Myk7YmFja2dyb3VuZDp0cmFuc3BhcmVudDtib3JkZXI6bm9uZTt0cmFuc2l0aW9uOmFsbCAuMTVzOwogIHBvc2l0aW9uOnJlbGF0aXZlO2ZvbnQtZmFtaWx5OnZhcigtLWZvbnQpfQoudGFiOmhvdmVye2NvbG9yOnZhcigtLXRleHQyKX0KLnRhYi5hY3RpdmV7YmFja2dyb3VuZDp2YXIoLS1jYXJkMyk7Y29sb3I6dmFyKC0tdGV4dCk7Ym94LXNoYWRvdzowIDFweCAzcHggcmdiYSgwLDAsMCwuMyl9Ci50YWItYmFkZ2V7cG9zaXRpb246YWJzb2x1dGU7dG9wOi01cHg7cmlnaHQ6LTVweDtiYWNrZ3JvdW5kOnZhcigtLXJlZCk7Y29sb3I6I2ZmZjsKICBmb250LXNpemU6OXB4O2ZvbnQtd2VpZ2h0OjcwMDt3aWR0aDoxNXB4O2hlaWdodDoxNXB4O2JvcmRlci1yYWRpdXM6NTAlOwogIGRpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OmNlbnRlcn0KLmJhcntkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxMHB4O21hcmdpbi1ib3R0b206MTRweDtmbGV4LXdyYXA6d3JhcH0KLnN3e3Bvc2l0aW9uOnJlbGF0aXZlO2ZsZXg6MTttaW4td2lkdGg6MTgwcHg7bWF4LXdpZHRoOjI4MHB4fQouc2ktaWNvbntwb3NpdGlvbjphYnNvbHV0ZTtsZWZ0OjEwcHg7dG9wOjUwJTt0cmFuc2Zvcm06dHJhbnNsYXRlWSgtNTAlKTtjb2xvcjp2YXIoLS10ZXh0Myk7cG9pbnRlci1ldmVudHM6bm9uZX0KLnNlYXJjaHt3aWR0aDoxMDAlO2JhY2tncm91bmQ6dmFyKC0tY2FyZCk7Ym9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO2JvcmRlci1yYWRpdXM6dmFyKC0tcjIpOwogIHBhZGRpbmc6N3B4IDEwcHggN3B4IDMycHg7Y29sb3I6dmFyKC0tdGV4dCk7Zm9udC1zaXplOjEzcHg7b3V0bGluZTpub25lOwogIHRyYW5zaXRpb246Ym9yZGVyIC4xNXM7Zm9udC1mYW1pbHk6dmFyKC0tZm9udCl9Ci5zZWFyY2g6Zm9jdXN7Ym9yZGVyLWNvbG9yOnZhcigtLWJsdWUpfQouc2VhcmNoOjpwbGFjZWhvbGRlcntjb2xvcjp2YXIoLS10ZXh0Myl9Ci50Z2wtbGFiZWx7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6N3B4O2N1cnNvcjpwb2ludGVyO2ZvbnQtc2l6ZToxMnB4O2NvbG9yOnZhcigtLXRleHQzKTt1c2VyLXNlbGVjdDpub25lfQoudGdsLWxhYmVsIGlucHV0e2Rpc3BsYXk6bm9uZX0KLnRnbHt3aWR0aDozMHB4O2hlaWdodDoxNnB4O2JhY2tncm91bmQ6dmFyKC0tY2FyZDMpO2JvcmRlci1yYWRpdXM6OHB4O3Bvc2l0aW9uOnJlbGF0aXZlOwogIHRyYW5zaXRpb246YmFja2dyb3VuZCAuMnM7Ym9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIyKX0KLnRnbDo6YWZ0ZXJ7Y29udGVudDonJztwb3NpdGlvbjphYnNvbHV0ZTt3aWR0aDoxMHB4O2hlaWdodDoxMHB4O2JvcmRlci1yYWRpdXM6NTAlOwogIGJhY2tncm91bmQ6dmFyKC0tdGV4dDMpO3RvcDoycHg7bGVmdDoycHg7dHJhbnNpdGlvbjphbGwgLjJzfQoudGdsLWxhYmVsIGlucHV0OmNoZWNrZWQrLnRnbHtiYWNrZ3JvdW5kOnJnYmEoNTYsMTg5LDI0OCwuMik7Ym9yZGVyLWNvbG9yOnZhcigtLWJsdWUpfQoudGdsLWxhYmVsIGlucHV0OmNoZWNrZWQrLnRnbDo6YWZ0ZXJ7bGVmdDoxNnB4O2JhY2tncm91bmQ6dmFyKC0tYmx1ZSl9Ci50Ymwtd3JhcHtiYWNrZ3JvdW5kOnZhcigtLWNhcmQpO2JvcmRlcjoxcHggc29saWQgdmFyKC0tYm9yZGVyKTtib3JkZXItcmFkaXVzOnZhcigtLXIpO292ZXJmbG93OmhpZGRlbn0KdGFibGV7d2lkdGg6MTAwJTtib3JkZXItY29sbGFwc2U6Y29sbGFwc2V9CnRoZWFke2JhY2tncm91bmQ6cmdiYSgwLDAsMCwuMil9CnRoe3BhZGRpbmc6MTBweCAxNnB4O3RleHQtYWxpZ246bGVmdDtmb250LXNpemU6MTBweDtjb2xvcjp2YXIoLS10ZXh0Myk7CiAgdGV4dC10cmFuc2Zvcm06dXBwZXJjYXNlO2xldHRlci1zcGFjaW5nOi44cHg7Zm9udC13ZWlnaHQ6NTAwOwogIGJvcmRlci1ib3R0b206MXB4IHNvbGlkIHZhcigtLWJvcmRlcik7d2hpdGUtc3BhY2U6bm93cmFwfQp0ZHtwYWRkaW5nOjExcHggMTZweDtib3JkZXItYm90dG9tOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO3ZlcnRpY2FsLWFsaWduOm1pZGRsZX0KdHI6bGFzdC1jaGlsZCB0ZHtib3JkZXItYm90dG9tOm5vbmV9CnRyLnRyOmhvdmVyIHRke2JhY2tncm91bmQ6cmdiYSgyNTUsMjU1LDI1NSwuMDIpfQoudW5hbWV7Zm9udC1zaXplOjEzcHg7Zm9udC13ZWlnaHQ6NjAwO2NvbG9yOnZhcigtLXRleHQpfQoudW5vdGV7Zm9udC1zaXplOjExcHg7Y29sb3I6dmFyKC0tdGV4dDMpO21hcmdpbi10b3A6MnB4O2ZvbnQtZmFtaWx5OnZhcigtLW1vbm8pfQouc2J7ZGlzcGxheTppbmxpbmUtZmxleDthbGlnbi1pdGVtczpjZW50ZXI7Z2FwOjRweDtwYWRkaW5nOjNweCA5cHg7Ym9yZGVyLXJhZGl1czoyMHB4OwogIGZvbnQtc2l6ZToxMXB4O2ZvbnQtd2VpZ2h0OjYwMDt3aGl0ZS1zcGFjZTpub3dyYXB9Ci5zYi1vbntiYWNrZ3JvdW5kOnZhcigtLWdyZWVuZGltKTtjb2xvcjp2YXIoLS1ncmVlbik7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDc0LDIyMiwxMjgsLjIpfQouc2Itb2Zme2JhY2tncm91bmQ6cmdiYSgyNTUsMjU1LDI1NSwuMDMpO2NvbG9yOnZhcigtLXRleHQzKTtib3JkZXI6MXB4IHNvbGlkIHZhcigtLWJvcmRlcil9Ci5zYi1iYW57YmFja2dyb3VuZDp2YXIoLS1yZWRkaW0pO2NvbG9yOnZhcigtLXJlZCk7Ym9yZGVyOjFweCBzb2xpZCByZ2JhKDI0OCwxMTMsMTEzLC4yKX0KLnNiLW92e2JhY2tncm91bmQ6dmFyKC0tYW1iZXJkaW0pO2NvbG9yOnZhcigtLWFtYmVyKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMjUxLDE5MSwzNiwuMil9Ci5jaGlwc3tkaXNwbGF5OmZsZXg7ZmxleC13cmFwOndyYXA7Z2FwOjRweH0KLmNoaXB7Zm9udC1mYW1pbHk6dmFyKC0tbW9ubyk7Zm9udC1zaXplOjExcHg7YmFja2dyb3VuZDpyZ2JhKDI1NSwyNTUsMjU1LC4wNCk7CiAgYm9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO2NvbG9yOnZhcigtLXRleHQyKTtwYWRkaW5nOjJweCA4cHg7Ym9yZGVyLXJhZGl1czo0cHh9Ci5saXJvd3tkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDo2cHh9Ci5saWlue3dpZHRoOjU0cHg7YmFja2dyb3VuZDp2YXIoLS1jYXJkMyk7Ym9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO2JvcmRlci1yYWRpdXM6dmFyKC0tcjMpOwogIHBhZGRpbmc6NHB4IDhweDtjb2xvcjp2YXIoLS10ZXh0KTtmb250LXNpemU6MTNweDt0ZXh0LWFsaWduOmNlbnRlcjtvdXRsaW5lOm5vbmU7CiAgdHJhbnNpdGlvbjpib3JkZXIgLjE1cztmb250LWZhbWlseTp2YXIoLS1tb25vKX0KLmxpaW46Zm9jdXN7Ym9yZGVyLWNvbG9yOnZhcigtLWJsdWUpfQoubGN7Zm9udC1mYW1pbHk6dmFyKC0tbW9ubyk7Zm9udC1zaXplOjEycHh9Ci5sYy1va3tjb2xvcjp2YXIoLS1ncmVlbil9LmxjLXd7Y29sb3I6dmFyKC0tYW1iZXIpfS5sYy1le2NvbG9yOnZhcigtLXJlZCl9LmxjLW57Y29sb3I6dmFyKC0tdGV4dDMpfQouYmdyaWR7ZGlzcGxheTpncmlkO2dhcDoxMHB4fQouYmNhcmR7YmFja2dyb3VuZDp2YXIoLS1jYXJkKTtib3JkZXI6MXB4IHNvbGlkIHJnYmEoMjQ4LDExMywxMTMsLjE1KTtib3JkZXItcmFkaXVzOnZhcigtLXIpOwogIHBhZGRpbmc6MTZweCAxOHB4O2Rpc3BsYXk6ZmxleDthbGlnbi1pdGVtczpjZW50ZXI7anVzdGlmeS1jb250ZW50OnNwYWNlLWJldHdlZW47Z2FwOjEycHg7dHJhbnNpdGlvbjpib3JkZXItY29sb3IgLjJzfQouYmNhcmQ6aG92ZXJ7Ym9yZGVyLWNvbG9yOnJnYmEoMjQ4LDExMywxMTMsLjMpfQouYmNhcmQtbHtkaXNwbGF5OmZsZXg7YWxpZ24taXRlbXM6Y2VudGVyO2dhcDoxNHB4fQouYmF2YXRhcnt3aWR0aDo0MHB4O2hlaWdodDo0MHB4O2JvcmRlci1yYWRpdXM6NTAlO2ZsZXgtc2hyaW5rOjA7YmFja2dyb3VuZDp2YXIoLS1yZWRkaW0pOwogIGJvcmRlcjoxcHggc29saWQgcmdiYSgyNDgsMTEzLDExMywuMik7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6Y2VudGVyOwogIGNvbG9yOnZhcigtLXJlZCk7Zm9udC1zaXplOjE4cHh9Ci5ibmFtZXtmb250LXdlaWdodDo2MDA7Zm9udC1zaXplOjE0cHg7bWFyZ2luLWJvdHRvbTo0cHh9Ci5iY2R7Zm9udC1mYW1pbHk6dmFyKC0tbW9ubyk7Zm9udC1zaXplOjE4cHg7Zm9udC13ZWlnaHQ6NjAwO2NvbG9yOnZhcigtLXJlZCk7bGV0dGVyLXNwYWNpbmc6MnB4fQouYnVuYmFue2ZvbnQtc2l6ZToxMXB4O2NvbG9yOnZhcigtLXRleHQzKTttYXJnaW4tdG9wOjVweH0KLnB3e3dpZHRoOjEwMCU7bWF4LXdpZHRoOjIwMHB4O2hlaWdodDozcHg7YmFja2dyb3VuZDpyZ2JhKDI1NSwyNTUsMjU1LC4wNik7Ym9yZGVyLXJhZGl1czoycHg7bWFyZ2luLXRvcDo4cHh9Ci5wYntoZWlnaHQ6M3B4O2JvcmRlci1yYWRpdXM6MnB4O2JhY2tncm91bmQ6dmFyKC0tcmVkKTt0cmFuc2l0aW9uOndpZHRoIDFzIGxpbmVhcn0KLm5jYXJke2JhY2tncm91bmQ6dmFyKC0tY2FyZCk7Ym9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO2JvcmRlci1yYWRpdXM6dmFyKC0tcik7CiAgcGFkZGluZzoxNHB4IDE4cHg7ZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6c3BhY2UtYmV0d2VlbjtnYXA6MTJweDsKICBtYXJnaW4tYm90dG9tOjhweDt0cmFuc2l0aW9uOmJvcmRlci1jb2xvciAuMnN9Ci5uY2FyZDpsYXN0LW9mLXR5cGV7bWFyZ2luLWJvdHRvbTowfQoubmNhcmQ6aG92ZXJ7Ym9yZGVyLWNvbG9yOnZhcigtLWJvcmRlcjIpfQoubmRvdHt3aWR0aDo4cHg7aGVpZ2h0OjhweDtib3JkZXItcmFkaXVzOjUwJTtmbGV4LXNocmluazowfQoubmQtZ3tiYWNrZ3JvdW5kOnZhcigtLWdyZWVuKTtib3gtc2hhZG93OjAgMCA4cHggcmdiYSg3NCwyMjIsMTI4LC41KX0KLm5kLWF7YmFja2dyb3VuZDp2YXIoLS1hbWJlcil9Ci5uZC1ye2JhY2tncm91bmQ6dmFyKC0tcmVkKX0KLm5uYW1le2ZvbnQtd2VpZ2h0OjYwMDtmb250LXNpemU6MTRweH0KLm5tZXRhe2ZvbnQtc2l6ZToxMXB4O2NvbG9yOnZhcigtLXRleHQzKTttYXJnaW4tdG9wOjNweDtmb250LWZhbWlseTp2YXIoLS1tb25vKX0KLm5zdHtmb250LXNpemU6MTNweDtmb250LXdlaWdodDo2MDA7dGV4dC1hbGlnbjpyaWdodH0KLm5wb3N7Zm9udC1zaXplOjExcHg7Y29sb3I6dmFyKC0tdGV4dDMpO21hcmdpbi10b3A6M3B4O2ZvbnQtZmFtaWx5OnZhcigtLW1vbm8pO3RleHQtYWxpZ246cmlnaHR9Ci5uaGludHtiYWNrZ3JvdW5kOnZhcigtLWNhcmQpO2JvcmRlcjoxcHggc29saWQgdmFyKC0tYm9yZGVyKTtib3JkZXItcmFkaXVzOnZhcigtLXIpO3BhZGRpbmc6MTRweCAxOHB4O21hcmdpbi10b3A6MTJweH0KLm5oaW50LWx7Zm9udC1zaXplOjExcHg7Y29sb3I6dmFyKC0tdGV4dDMpO21hcmdpbi1ib3R0b206N3B4fQouY29kZXtmb250LWZhbWlseTp2YXIoLS1tb25vKTtmb250LXNpemU6MTJweDtjb2xvcjp2YXIoLS1ibHVlKTtiYWNrZ3JvdW5kOnZhcigtLWJnMik7CiAgcGFkZGluZzoxMHB4IDE0cHg7Ym9yZGVyLXJhZGl1czp2YXIoLS1yMik7Ym9yZGVyOjFweCBzb2xpZCB2YXIoLS1ib3JkZXIpO3dvcmQtYnJlYWs6YnJlYWstYWxsO2xpbmUtaGVpZ2h0OjEuN30KLmVtcHR5e3RleHQtYWxpZ246Y2VudGVyO3BhZGRpbmc6NTJweCAyMHB4O2NvbG9yOnZhcigtLXRleHQzKX0KLmVtcHR5LWlje2ZvbnQtc2l6ZTozNnB4O21hcmdpbi1ib3R0b206MTBweDtvcGFjaXR5Oi4zfQouZW1wdHktdHh7Zm9udC1zaXplOjEzcHh9Ci50b2FzdHN7cG9zaXRpb246Zml4ZWQ7Ym90dG9tOjI0cHg7cmlnaHQ6MjRweDt6LWluZGV4Ojk5OTk7ZGlzcGxheTpmbGV4O2ZsZXgtZGlyZWN0aW9uOmNvbHVtbjtnYXA6OHB4O3BvaW50ZXItZXZlbnRzOm5vbmV9Ci50b2FzdHtiYWNrZ3JvdW5kOnZhcigtLWNhcmQyKTtib3JkZXI6MXB4IHNvbGlkIHZhcigtLWJvcmRlcjIpO2JvcmRlci1yYWRpdXM6dmFyKC0tcik7CiAgcGFkZGluZzoxMHB4IDE2cHg7Zm9udC1zaXplOjEzcHg7Y29sb3I6dmFyKC0tdGV4dCk7YW5pbWF0aW9uOnRpbiAuMnMgZWFzZTttYXgtd2lkdGg6MzAwcHg7cG9pbnRlci1ldmVudHM6YWxsfQoudG9hc3Qub2t7Ym9yZGVyLWxlZnQ6MnB4IHNvbGlkIHZhcigtLWdyZWVuKX0KLnRvYXN0LmVycntib3JkZXItbGVmdDoycHggc29saWQgdmFyKC0tcmVkKX0KLnRvYXN0LmluZm97Ym9yZGVyLWxlZnQ6MnB4IHNvbGlkIHZhcigtLWJsdWUpfQpAa2V5ZnJhbWVzIHRpbntmcm9te29wYWNpdHk6MDt0cmFuc2Zvcm06dHJhbnNsYXRlWSg4cHgpIHNjYWxlKC45Nyl9dG97b3BhY2l0eToxO3RyYW5zZm9ybTpub25lfX0KLm1vZGFsLWJne3Bvc2l0aW9uOmZpeGVkO2luc2V0OjA7YmFja2dyb3VuZDpyZ2JhKDAsMCwwLC43NSk7ei1pbmRleDoyMDA7CiAgZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtqdXN0aWZ5LWNvbnRlbnQ6Y2VudGVyO2JhY2tkcm9wLWZpbHRlcjpibHVyKDRweCl9Ci5tb2RhbHtiYWNrZ3JvdW5kOnZhcigtLWNhcmQpO2JvcmRlcjoxcHggc29saWQgdmFyKC0tYm9yZGVyMik7Ym9yZGVyLXJhZGl1czp2YXIoLS1yKTsKICBwYWRkaW5nOjI4cHg7d2lkdGg6MzQwcHg7YW5pbWF0aW9uOm1pbiAuMnMgZWFzZX0KQGtleWZyYW1lcyBtaW57ZnJvbXtvcGFjaXR5OjA7dHJhbnNmb3JtOnNjYWxlKC45NSl9dG97b3BhY2l0eToxO3RyYW5zZm9ybTpub25lfX0KLm1vZGFsIGgze2ZvbnQtc2l6ZToxNnB4O2ZvbnQtd2VpZ2h0OjYwMDttYXJnaW4tYm90dG9tOjhweH0KLm1vZGFsIHB7Y29sb3I6dmFyKC0tdGV4dDIpO2ZvbnQtc2l6ZToxM3B4O21hcmdpbi1ib3R0b206MjBweDtsaW5lLWhlaWdodDoxLjZ9Ci5tb2RhbC1idG5ze2Rpc3BsYXk6ZmxleDtnYXA6OHB4O2p1c3RpZnktY29udGVudDpmbGV4LWVuZH0KQGtleWZyYW1lcyBzcGlue3Rve3RyYW5zZm9ybTpyb3RhdGUoMzYwZGVnKX19Ci5zcGlubmluZ3thbmltYXRpb246c3BpbiAuN3MgbGluZWFyIGluZmluaXRlfQpAbWVkaWEobWF4LXdpZHRoOjkwMHB4KXsKICAuc3RhdHN7Z3JpZC10ZW1wbGF0ZS1jb2x1bW5zOnJlcGVhdCgyLDFmcil9CiAgLm1haW57cGFkZGluZzoxNnB4fS5oZWFkZXJ7cGFkZGluZzowIDE2cHh9CiAgdGg6bnRoLWNoaWxkKDMpLHRkOm50aC1jaGlsZCgzKXtkaXNwbGF5Om5vbmV9Cn0KQG1lZGlhKG1heC13aWR0aDo1NjBweCl7CiAgdGg6bnRoLWNoaWxkKDQpLHRkOm50aC1jaGlsZCg0KXtkaXNwbGF5Om5vbmV9CiAgLmhzdWJ7ZGlzcGxheTpub25lfQp9Cjwvc3R5bGU+CjwvaGVhZD4KPGJvZHk+Cgo8ZGl2IGNsYXNzPSJoZWFkZXIiPgogIDxkaXYgY2xhc3M9Imhsb2dvIj4KICAgIDxkaXYgY2xhc3M9Imhsb2dvLWljb24iPgogICAgICA8c3ZnIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZD0iTTEyIDFMMyA1djZjMCA1LjU1IDMuODQgMTAuNzQgOSAxMiA1LjE2LTEuMjYgOS02LjQ1IDktMTJWNWwtOS00eiIvPjwvc3ZnPgogICAgPC9kaXY+CiAgICA8ZGl2PgogICAgICA8ZGl2IGNsYXNzPSJodGl0bGUiPklQIOmZkOWItuWZqOeuoeeQhjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJoc3ViIj5NYXJ6YmFuIMK3IFJlYWwtdGltZSBNb25pdG9yPC9kaXY+CiAgICA8L2Rpdj4KICA8L2Rpdj4KICA8ZGl2IGNsYXNzPSJocmlnaHQiPgogICAgPGRpdiBjbGFzcz0iYmFkZ2UtbGl2ZSI+PGRpdiBjbGFzcz0iZG90LXB1bHNlIj48L2Rpdj7lrp7ml7bnm5Hmjqc8L2Rpdj4KICAgIDxidXR0b24gY2xhc3M9ImJ0biIgb25jbGljaz0iZG9SZWZyZXNoKCkiPgogICAgICA8c3ZnIGlkPSJyaSIgd2lkdGg9IjEyIiBoZWlnaHQ9IjEyIiB2aWV3Qm94PSIwIDAgMjQgMjQiIGZpbGw9Im5vbmUiIHN0cm9rZT0iY3VycmVudENvbG9yIiBzdHJva2Utd2lkdGg9IjIuNSI+CiAgICAgICAgPHBhdGggZD0iTTEgNHY2aDZNMjMgMjB2LTZoLTYiLz48cGF0aCBkPSJNMjAuNDkgOUE5IDkgMCAwMDUuNjQgNS42NEwxIDEwbTIyIDRsLTQuNjQgNC4zNkE5IDkgMCAwMTMuNTEgMTUiLz4KICAgICAgPC9zdmc+5Yi35pawCiAgICA8L2J1dHRvbj4KICA8L2Rpdj4KPC9kaXY+Cgo8ZGl2IGNsYXNzPSJtYWluIj4KCiAgPGRpdiBjbGFzcz0ic3RhdHMiPgogICAgPGRpdiBjbGFzcz0ic3RhdCBzLWIiPgogICAgICA8ZGl2IGNsYXNzPSJzdGF0LXRvcCI+PGRpdiBjbGFzcz0ic3RhdC1sYWJlbCI+5Zyo57q/55So5oi3PC9kaXY+PGRpdiBjbGFzcz0ic2kgc2ktYiI+8J+RpDwvZGl2PjwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJzdGF0LXZhbCBjdi1iIiBpZD0icy1vbmxpbmUiPuKAlDwvZGl2PgogICAgICA8ZGl2IGNsYXNzPSJzdGF0LXN1YiI+5b2T5YmN5rS76LeD6L+e5o6l5pWwPC9kaXY+CiAgICA8L2Rpdj4KICAgIDxkaXYgY2xhc3M9InN0YXQgcy1nIj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC10b3AiPjxkaXYgY2xhc3M9InN0YXQtbGFiZWwiPuWcqOe6vyBJUCDmlbA8L2Rpdj48ZGl2IGNsYXNzPSJzaSBzaS1nIj7wn4yQPC9kaXY+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InN0YXQtdmFsIGN2LWciIGlkPSJzLWlwcyI+4oCUPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InN0YXQtc3ViIj7lhajpg6jnlKjmiLcgSVAg5ZCI6K6hPC9kaXY+CiAgICA8L2Rpdj4KICAgIDxkaXYgY2xhc3M9InN0YXQgcy1yIj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC10b3AiPjxkaXYgY2xhc3M9InN0YXQtbGFiZWwiPuWwgeemgeeUqOaItzwvZGl2PjxkaXYgY2xhc3M9InNpIHNpLXIiPvCfmqs8L2Rpdj48L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC12YWwgY3YtciIgaWQ9InMtYmFubmVkIj7igJQ8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC1zdWIiPuetieW+heiHquWKqOino+WwgTwvZGl2PgogICAgPC9kaXY+CiAgICA8ZGl2IGNsYXNzPSJzdGF0IHMtYSI+CiAgICAgIDxkaXYgY2xhc3M9InN0YXQtdG9wIj48ZGl2IGNsYXNzPSJzdGF0LWxhYmVsIj7oioLngrnml6Xlv5c8L2Rpdj48ZGl2IGNsYXNzPSJzaSBzaS1hIj7wn5OhPC9kaXY+PC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9InN0YXQtdmFsIGN2LWEiIGlkPSJzLW5vZGVzIj7igJQ8L2Rpdj4KICAgICAgPGRpdiBjbGFzcz0ic3RhdC1zdWIiPua0u+i3g+aOqOmAgeiKgueCuTwvZGl2PgogICAgPC9kaXY+CiAgPC9kaXY+CgogIDxkaXYgY2xhc3M9InRhYnMtYmFyIj4KICAgIDxkaXYgY2xhc3M9InRhYnMiPgogICAgICA8YnV0dG9uIGNsYXNzPSJ0YWIgYWN0aXZlIiBpZD0idC11c2VycyIgb25jbGljaz0ic3dpdGNoVGFiKCd1c2VycycsdGhpcykiPueUqOaIt+WIl+ihqDwvYnV0dG9uPgogICAgICA8YnV0dG9uIGNsYXNzPSJ0YWIiIGlkPSJ0LWJhbm5lZCIgb25jbGljaz0ic3dpdGNoVGFiKCdiYW5uZWQnLHRoaXMpIj7lsIHnpoHnrqHnkIY8L2J1dHRvbj4KICAgICAgPGJ1dHRvbiBjbGFzcz0idGFiIiBpZD0idC1ub2RlcyIgb25jbGljaz0ic3dpdGNoVGFiKCdub2RlcycsdGhpcykiPuiKgueCueeKtuaAgTwvYnV0dG9uPgogICAgPC9kaXY+CiAgPC9kaXY+CgogIDwhLS0gVXNlcnMgLS0+CiAgPGRpdiBpZD0iY29udGVudC11c2VycyI+CiAgICA8ZGl2IGNsYXNzPSJiYXIiPgogICAgICA8ZGl2IGNsYXNzPSJzdyI+CiAgICAgICAgPHNwYW4gY2xhc3M9InNpLWljb24iPgogICAgICAgICAgPHN2ZyB3aWR0aD0iMTMiIGhlaWdodD0iMTMiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgc3Ryb2tlPSJjdXJyZW50Q29sb3IiIHN0cm9rZS13aWR0aD0iMiI+CiAgICAgICAgICAgIDxjaXJjbGUgY3g9IjExIiBjeT0iMTEiIHI9IjgiLz48cGF0aCBkPSJtMjEgMjEtNC4zNS00LjM1Ii8+CiAgICAgICAgICA8L3N2Zz4KICAgICAgICA8L3NwYW4+CiAgICAgICAgPGlucHV0IGNsYXNzPSJzZWFyY2giIHR5cGU9InRleHQiIHBsYWNlaG9sZGVyPSLmkJzntKLnlKjmiLflkI0uLi4iIG9uaW5wdXQ9ImZpbHRlclUodGhpcy52YWx1ZSkiPgogICAgICA8L2Rpdj4KICAgICAgPGxhYmVsIGNsYXNzPSJ0Z2wtbGFiZWwiPjxpbnB1dCB0eXBlPSJjaGVja2JveCIgaWQ9Im9ubHlMaW0iIG9uY2hhbmdlPSJyZW5kZXJVc2VycygpIj48ZGl2IGNsYXNzPSJ0Z2wiPjwvZGl2PuS7heaciemZkOWItjwvbGFiZWw+CiAgICAgIDxsYWJlbCBjbGFzcz0idGdsLWxhYmVsIj48aW5wdXQgdHlwZT0iY2hlY2tib3giIGlkPSJvbmx5T24iIG9uY2hhbmdlPSJyZW5kZXJVc2VycygpIj48ZGl2IGNsYXNzPSJ0Z2wiPjwvZGl2PuS7heWcqOe6vzwvbGFiZWw+CiAgICA8L2Rpdj4KICAgIDxkaXYgY2xhc3M9InRibC13cmFwIj4KICAgICAgPHRhYmxlPgogICAgICAgIDx0aGVhZD48dHI+PHRoPueUqOaItzwvdGg+PHRoPueKtuaAgTwvdGg+PHRoPuWcqOe6vyBJUDwvdGg+PHRoPklQIOmZkOWItjwvdGg+PHRoPuaTjeS9nDwvdGg+PC90cj48L3RoZWFkPgogICAgICAgIDx0Ym9keSBpZD0idXRib2R5Ij48dHI+PHRkIGNvbHNwYW49IjUiIGNsYXNzPSJlbXB0eSI+PGRpdiBjbGFzcz0iZW1wdHktaWMiPuKPszwvZGl2PjxkaXYgY2xhc3M9ImVtcHR5LXR4Ij7liqDovb3kuK0uLi48L2Rpdj48L3RkPjwvdHI+PC90Ym9keT4KICAgICAgPC90YWJsZT4KICAgIDwvZGl2PgogIDwvZGl2PgoKICA8IS0tIEJhbm5lZCAtLT4KICA8ZGl2IGlkPSJjb250ZW50LWJhbm5lZCIgc3R5bGU9ImRpc3BsYXk6bm9uZSI+CiAgICA8ZGl2IGNsYXNzPSJiYXIiPgogICAgICA8ZGl2IGlkPSJiYW4tY291bnQiIHN0eWxlPSJmb250LXNpemU6MTNweDtjb2xvcjp2YXIoLS10ZXh0MykiPjwvZGl2PgogICAgICA8ZGl2IHN0eWxlPSJtYXJnaW4tbGVmdDphdXRvIj4KICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4gYnRuLXJlZCBidG4tc20iIGlkPSJ1bmJhbkFsbEJ0biIgc3R5bGU9ImRpc3BsYXk6bm9uZSIgb25jbGljaz0idW5iYW5BbGwoKSI+5YWo6YOo6Kej5bCBPC9idXR0b24+CiAgICAgIDwvZGl2PgogICAgPC9kaXY+CiAgICA8ZGl2IGlkPSJiYW5uZWQtbGlzdCI+CiAgICAgIDxkaXYgY2xhc3M9ImVtcHR5Ij48ZGl2IGNsYXNzPSJlbXB0eS1pYyI+4pyFPC9kaXY+PGRpdiBjbGFzcz0iZW1wdHktdHgiPuW9k+WJjeayoeacieWwgeemgeeUqOaItzwvZGl2PjwvZGl2PgogICAgPC9kaXY+CiAgPC9kaXY+CgogIDwhLS0gTm9kZXMgLS0+CiAgPGRpdiBpZD0iY29udGVudC1ub2RlcyIgc3R5bGU9ImRpc3BsYXk6bm9uZSI+CiAgICA8ZGl2IGlkPSJub2Rlcy1saXN0Ij48L2Rpdj4KICAgIDxkaXYgY2xhc3M9Im5oaW50Ij4KICAgICAgPGRpdiBjbGFzcz0ibmhpbnQtbCI+5Zyo6IqC54K55pyN5Yqh5Zmo5omn6KGM5Lul5LiL5ZG95Luk5byA5ZCv5pel5b+X5o6o6YCB77yaPC9kaXY+CiAgICAgIDxkaXYgY2xhc3M9ImNvZGUiPmJhc2ggL29wdC9tYXJ6YmFuL2lwLWxpbWl0ZXIvaW5zdGFsbC1ub2RlLXB1c2guc2ggIuiKgueCueWQjSIgIumdouadv0lQOjkxOTEiPC9kaXY+CiAgICA8L2Rpdj4KICA8L2Rpdj4KCjwvZGl2PgoKPGRpdiBjbGFzcz0idG9hc3RzIiBpZD0idG9hc3RzIj48L2Rpdj4KCjxkaXYgY2xhc3M9Im1vZGFsLWJnIiBpZD0ibW9kYWwiIHN0eWxlPSJkaXNwbGF5Om5vbmUiIG9uY2xpY2s9ImlmKGV2ZW50LnRhcmdldD09PXRoaXMpY2xvc2VNb2RhbCgpIj4KICA8ZGl2IGNsYXNzPSJtb2RhbCI+CiAgICA8aDM+56Gu6K6k6Kej5bCBPC9oMz4KICAgIDxwIGlkPSJtb2RhbC1tc2ciPuehruWumuino+WwgeivpeeUqOaIt++8nzwvcD4KICAgIDxkaXYgY2xhc3M9Im1vZGFsLWJ0bnMiPgogICAgICA8YnV0dG9uIGNsYXNzPSJidG4iIG9uY2xpY2s9ImNsb3NlTW9kYWwoKSI+5Y+W5raIPC9idXR0b24+CiAgICAgIDxidXR0b24gY2xhc3M9ImJ0bi1ncmVlbiIgaWQ9Im1vZGFsLW9rIj7noa7orqTop6PlsIE8L2J1dHRvbj4KICAgIDwvZGl2PgogIDwvZGl2Pgo8L2Rpdj4KCjxzY3JpcHQ+CmNvbnN0IEFQST0nL2FwaS1pcGwnOwpsZXQgYWxsVXNlcnM9W10sYWxsQmFubmVkPXt9LGFsbE5vZGVzPXt9LGFsbExpbWl0cz17fTsKbGV0IHVGaWx0ZXI9Jyc7CmxldCBfY2R0PW51bGw7Cgphc3luYyBmdW5jdGlvbiByZXEocGF0aCxvcHRzKXsKICB0cnl7Y29uc3Qgcj1hd2FpdCBmZXRjaChBUEkrcGF0aCxvcHRzfHx7fSk7cmV0dXJuIHIub2s/ci5qc29uKCk6bnVsbH1jYXRjaHtyZXR1cm4gbnVsbH0KfQoKYXN5bmMgZnVuY3Rpb24gZG9SZWZyZXNoKCl7CiAgY29uc3QgaWM9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3JpJyk7CiAgaWMuY2xhc3NMaXN0LmFkZCgnc3Bpbm5pbmcnKTsKICBjb25zdCBbdXNlcnMsYmFubmVkLG5vZGVzLGxpbWl0c109YXdhaXQgUHJvbWlzZS5hbGwoWwogICAgcmVxKCcvdXNlcnMnKSxyZXEoJy9iYW5uZWQnKSxyZXEoJy9ub2RlcycpLHJlcSgnL2xpbWl0cycpCiAgXSk7CiAgaWYodXNlcnMpYWxsVXNlcnM9dXNlcnM7CiAgaWYoYmFubmVkKWFsbEJhbm5lZD1iYW5uZWQ7CiAgaWYobm9kZXMpYWxsTm9kZXM9bm9kZXM7CiAgaWYobGltaXRzKWFsbExpbWl0cz1saW1pdHM7CiAgaWMuY2xhc3NMaXN0LnJlbW92ZSgnc3Bpbm5pbmcnKTsKICB1cGRhdGVTdGF0cygpO3JlbmRlclVzZXJzKCk7cmVuZGVyQmFubmVkKCk7cmVuZGVyTm9kZXMoKTsKfQoKZnVuY3Rpb24gdXBkYXRlU3RhdHMoKXsKICBjb25zdCBvbmxpbmU9YWxsVXNlcnMuZmlsdGVyKHU9PnUub25saW5lPjApLmxlbmd0aDsKICBjb25zdCB0b3RhbElwPWFsbFVzZXJzLnJlZHVjZSgoYSx1KT0+YSt1Lm9ubGluZSwwKTsKICBjb25zdCBiYz1PYmplY3Qua2V5cyhhbGxCYW5uZWQpLmxlbmd0aDsKICBzZXQoJ3Mtb25saW5lJyxvbmxpbmUpO3NldCgncy1pcHMnLHRvdGFsSXApOwogIHNldCgncy1iYW5uZWQnLGJjKTtzZXQoJ3Mtbm9kZXMnLE9iamVjdC5rZXlzKGFsbE5vZGVzKS5sZW5ndGgpOwogIGNvbnN0IHRiPWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCd0LWJhbm5lZCcpOwogIGxldCBiZGc9dGIucXVlcnlTZWxlY3RvcignLnRhYi1iYWRnZScpOwogIGlmKGJjPjApewogICAgaWYoIWJkZyl7YmRnPWRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ3NwYW4nKTtiZGcuY2xhc3NOYW1lPSd0YWItYmFkZ2UnO3RiLmFwcGVuZENoaWxkKGJkZyl9CiAgICBiZGcudGV4dENvbnRlbnQ9YmM7CiAgfWVsc2UgaWYoYmRnKWJkZy5yZW1vdmUoKTsKfQpmdW5jdGlvbiBzZXQoaWQsdil7Y29uc3QgZT1kb2N1bWVudC5nZXRFbGVtZW50QnlJZChpZCk7aWYoZSllLnRleHRDb250ZW50PXZ9CgpmdW5jdGlvbiByZW5kZXJVc2VycygpewogIGNvbnN0IG9sPWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdvbmx5TGltJyk/LmNoZWNrZWQ7CiAgY29uc3Qgb289ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ29ubHlPbicpPy5jaGVja2VkOwogIGxldCBsaXN0PVsuLi5hbGxVc2Vyc107CiAgaWYodUZpbHRlcilsaXN0PWxpc3QuZmlsdGVyKHU9PnUudXNlcm5hbWUudG9Mb3dlckNhc2UoKS5pbmNsdWRlcyh1RmlsdGVyLnRvTG93ZXJDYXNlKCkpKTsKICBpZihvbClsaXN0PWxpc3QuZmlsdGVyKHU9PnUuaXBfbGltaXQ+MCk7CiAgaWYob28pbGlzdD1saXN0LmZpbHRlcih1PT51Lm9ubGluZT4wKTsKICBsaXN0LnNvcnQoKGEsYik9PihiLm9ubGluZS1hLm9ubGluZSl8fGEudXNlcm5hbWUubG9jYWxlQ29tcGFyZShiLnVzZXJuYW1lKSk7CiAgY29uc3QgdGI9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3V0Ym9keScpOwogIGlmKCFsaXN0Lmxlbmd0aCl7CiAgICB0Yi5pbm5lckhUTUw9Jzx0cj48dGQgY29sc3Bhbj0iNSIgY2xhc3M9ImVtcHR5Ij48ZGl2IGNsYXNzPSJlbXB0eS1pYyI+8J+UjTwvZGl2PjxkaXYgY2xhc3M9ImVtcHR5LXR4Ij7msqHmnInljLnphY3nmoTnlKjmiLc8L2Rpdj48L3RkPjwvdHI+JzsKICAgIHJldHVybjsKICB9CiAgdGIuaW5uZXJIVE1MPWxpc3QubWFwKHU9PnsKICAgIGNvbnN0IGliPXUuYmFubmVkfHwhIWFsbEJhbm5lZFt1LnVzZXJuYW1lXTsKICAgIGNvbnN0IG92PXUuaXBfbGltaXQ+MCYmdS5vbmxpbmU+dS5pcF9saW1pdDsKICAgIGxldCBzYjsKICAgIGlmKGliKXNiPSc8c3BhbiBjbGFzcz0ic2Igc2ItYmFuIj7wn5qrIOWwgeemgeS4rTwvc3Bhbj4nOwogICAgZWxzZSBpZihvdilzYj0nPHNwYW4gY2xhc3M9InNiIHNiLW92Ij7imqAg6LaF5Ye66ZmQ5Yi2PC9zcGFuPic7CiAgICBlbHNlIGlmKHUub25saW5lPjApc2I9JzxzcGFuIGNsYXNzPSJzYiBzYi1vbiI+4pePIOWcqOe6vzwvc3Bhbj4nOwogICAgZWxzZSBzYj0nPHNwYW4gY2xhc3M9InNiIHNiLW9mZiI+4peLIOemu+e6vzwvc3Bhbj4nOwogICAgY29uc3QgY2g9dS5pcHMmJnUuaXBzLmxlbmd0aAogICAgICA/YDxkaXYgY2xhc3M9ImNoaXBzIj4ke3UuaXBzLm1hcChpcD0+YDxzcGFuIGNsYXNzPSJjaGlwIj4ke2lwfTwvc3Bhbj5gKS5qb2luKCcnKX08L2Rpdj5gCiAgICAgIDpgPHNwYW4gc3R5bGU9ImNvbG9yOnZhcigtLXRleHQzKSI+4oCUPC9zcGFuPmA7CiAgICBjb25zdCBsdj11LmlwX2xpbWl0fHwwOwogICAgbGV0IGxjPSdsYy1uJyxsdD0n5LiN6ZmQJzsKICAgIGlmKGx2PjApe2x0PWAke3Uub25saW5lfS8ke2x2fWA7bGM9b3Y/J2xjLWUnOnUub25saW5lPjA/J2xjLXcnOidsYy1vayd9CiAgICBjb25zdCB1bj1lc2ModS51c2VybmFtZSk7CiAgICByZXR1cm4gYDx0ciBjbGFzcz0idHIiPgogICAgICA8dGQ+PGRpdiBjbGFzcz0idW5hbWUiPiR7dW59PC9kaXY+JHt1Lm5vdGU/YDxkaXYgY2xhc3M9InVub3RlIj4ke2VzYyh1Lm5vdGUpfTwvZGl2PmA6Jyd9PC90ZD4KICAgICAgPHRkPiR7c2J9PC90ZD4KICAgICAgPHRkPiR7Y2h9PC90ZD4KICAgICAgPHRkPgogICAgICAgIDxkaXYgY2xhc3M9Imxpcm93Ij4KICAgICAgICAgIDxpbnB1dCBjbGFzcz0ibGlpbiIgdHlwZT0ibnVtYmVyIiBtaW49IjAiIG1heD0iOTkiIHZhbHVlPSIke2x2fSIgaWQ9ImxpLSR7dW59IgogICAgICAgICAgICBvbmtleWRvd249ImlmKGV2ZW50LmtleT09PSdFbnRlcicpc2F2ZUxpbWl0KCcke3VufScpIj4KICAgICAgICAgIDxzcGFuIGNsYXNzPSJsYyAke2xjfSI+JHtsdH08L3NwYW4+CiAgICAgICAgICA8YnV0dG9uIGNsYXNzPSJidG4gYnRuLXNtIiBvbmNsaWNrPSJzYXZlTGltaXQoJyR7dW59JykiPuS/neWtmDwvYnV0dG9uPgogICAgICAgIDwvZGl2PgogICAgICA8L3RkPgogICAgICA8dGQ+JHtpYj9gPGJ1dHRvbiBjbGFzcz0iYnRuLWdyZWVuIiBvbmNsaWNrPSJjb25maXJtVW5iYW4oJyR7dW59JykiPueri+WNs+ino+WwgTwvYnV0dG9uPmA6YDxzcGFuIHN0eWxlPSJjb2xvcjp2YXIoLS10ZXh0Myk7Zm9udC1zaXplOjEycHgiPuKAlDwvc3Bhbj5gfTwvdGQ+CiAgICA8L3RyPmA7CiAgfSkuam9pbignJyk7Cn0KCmZ1bmN0aW9uIHJlbmRlckJhbm5lZCgpewogIGNvbnN0IGxpc3Q9T2JqZWN0LmVudHJpZXMoYWxsQmFubmVkKTsKICBzZXQoJ2Jhbi1jb3VudCcsbGlzdC5sZW5ndGg/YOWFsSAke2xpc3QubGVuZ3RofSDkuKrnlKjmiLflsIHnpoHkuK1gOiflvZPliY3msqHmnInlsIHnpoHnlKjmiLcnKTsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgndW5iYW5BbGxCdG4nKS5zdHlsZS5kaXNwbGF5PWxpc3QubGVuZ3RoPycnOidub25lJzsKICBjb25zdCB3cmFwPWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdiYW5uZWQtbGlzdCcpOwogIGlmKCFsaXN0Lmxlbmd0aCl7CiAgICB3cmFwLmlubmVySFRNTD0nPGRpdiBjbGFzcz0iZW1wdHkiPjxkaXYgY2xhc3M9ImVtcHR5LWljIj7inIU8L2Rpdj48ZGl2IGNsYXNzPSJlbXB0eS10eCI+5b2T5YmN5rKh5pyJ5bCB56aB55So5oi3PC9kaXY+PC9kaXY+JzsKICAgIHN0b3BDZCgpO3JldHVybjsKICB9CiAgY29uc3QgQlQ9MyozNjAwOwogIHdyYXAuaW5uZXJIVE1MPWA8ZGl2IGNsYXNzPSJiZ3JpZCI+JHtsaXN0Lm1hcCgoW3UsaW5mb10pPT57CiAgICBjb25zdCBzZWM9TWF0aC5tYXgoMCxNYXRoLnJvdW5kKGluZm8udW5iYW5faW5fc2Vjb25kc3x8MCkpOwogICAgY29uc3QgaD1TdHJpbmcoTWF0aC5mbG9vcihzZWMvMzYwMCkpLnBhZFN0YXJ0KDIsJzAnKTsKICAgIGNvbnN0IG09U3RyaW5nKE1hdGguZmxvb3IoKHNlYyUzNjAwKS82MCkpLnBhZFN0YXJ0KDIsJzAnKTsKICAgIGNvbnN0IHM9U3RyaW5nKHNlYyU2MCkucGFkU3RhcnQoMiwnMCcpOwogICAgY29uc3QgcGN0PU1hdGgubWluKDEwMCxNYXRoLnJvdW5kKCgxLXNlYy9CVCkqMTAwKSk7CiAgICBjb25zdCBldT1lc2ModSk7CiAgICByZXR1cm4gYDxkaXYgY2xhc3M9ImJjYXJkIiBpZD0iYmMtJHtldX0iPgogICAgICA8ZGl2IGNsYXNzPSJiY2FyZC1sIj4KICAgICAgICA8ZGl2IGNsYXNzPSJiYXZhdGFyIj7wn5qrPC9kaXY+CiAgICAgICAgPGRpdj4KICAgICAgICAgIDxkaXYgY2xhc3M9ImJuYW1lIj4ke2V1fTwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzcz0iYmNkIiBpZD0iY2QtJHtldX0iPiR7aH06JHttfToke3N9PC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJwdyI+PGRpdiBjbGFzcz0icGIiIGlkPSJwYi0ke2V1fSIgc3R5bGU9IndpZHRoOiR7cGN0fSUiPjwvZGl2PjwvZGl2PgogICAgICAgICAgPGRpdiBjbGFzcz0iYnVuYmFuIj7op6PlsIHml7bpl7TvvJoke2VzYyhpbmZvLnVuYmFuX2F0fHwn6Ieq5Yqo6Kej5bCBJyl9PC9kaXY+CiAgICAgICAgPC9kaXY+CiAgICAgIDwvZGl2PgogICAgICA8YnV0dG9uIGNsYXNzPSJidG4tZ3JlZW4iIG9uY2xpY2s9ImNvbmZpcm1VbmJhbignJHtldX0nKSI+56uL5Y2z6Kej5bCBPC9idXR0b24+CiAgICA8L2Rpdj5gOwogIH0pLmpvaW4oJycpfTwvZGl2PmA7CiAgc3RhcnRDZChsaXN0KTsKfQoKZnVuY3Rpb24gc3RhcnRDZChsaXN0KXsKICBzdG9wQ2QoKTsKICBjb25zdCBlbmRzPXt9O2NvbnN0IG5vdz1EYXRlLm5vdygpLzEwMDA7CiAgbGlzdC5mb3JFYWNoKChbdSxpbmZvXSk9PntlbmRzW3VdPW5vdysoaW5mby51bmJhbl9pbl9zZWNvbmRzfHwwKX0pOwogIF9jZHQ9c2V0SW50ZXJ2YWwoKCk9PnsKICAgIGNvbnN0IG49RGF0ZS5ub3coKS8xMDAwOwogICAgT2JqZWN0LmVudHJpZXMoZW5kcykuZm9yRWFjaCgoW3UsZW5kXSk9PnsKICAgICAgY29uc3QgcmVtPU1hdGgubWF4KDAsTWF0aC5yb3VuZChlbmQtbikpOwogICAgICBjb25zdCBjZD1kb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnY2QtJyt1KTsKICAgICAgY29uc3QgcGI9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3BiLScrdSk7CiAgICAgIGlmKCFjZClyZXR1cm47CiAgICAgIGNkLnRleHRDb250ZW50PVtNYXRoLmZsb29yKHJlbS8zNjAwKSxNYXRoLmZsb29yKChyZW0lMzYwMCkvNjApLHJlbSU2MF0ubWFwKHY9PlN0cmluZyh2KS5wYWRTdGFydCgyLCcwJykpLmpvaW4oJzonKTsKICAgICAgaWYocGIpcGIuc3R5bGUud2lkdGg9TWF0aC5taW4oMTAwLE1hdGgucm91bmQoKDEtcmVtLygzKjM2MDApKSoxMDApKSsnJSc7CiAgICAgIGlmKHJlbT09PTApe2RlbGV0ZSBlbmRzW3VdO2RvUmVmcmVzaCgpfQogICAgfSk7CiAgfSwxMDAwKTsKfQpmdW5jdGlvbiBzdG9wQ2QoKXtpZihfY2R0KXtjbGVhckludGVydmFsKF9jZHQpO19jZHQ9bnVsbH19CgpmdW5jdGlvbiByZW5kZXJOb2RlcygpewogIGNvbnN0IGVudHJpZXM9T2JqZWN0LmVudHJpZXMoYWxsTm9kZXMpOwogIGNvbnN0IHdyYXA9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ25vZGVzLWxpc3QnKTsKICBpZighZW50cmllcy5sZW5ndGgpewogICAgd3JhcC5pbm5lckhUTUw9JzxkaXYgY2xhc3M9ImVtcHR5Ij48ZGl2IGNsYXNzPSJlbXB0eS1pYyI+8J+ToTwvZGl2PjxkaXYgY2xhc3M9ImVtcHR5LXR4Ij7ml6DoioLngrnml6Xlv5fmlbDmja48L2Rpdj48L2Rpdj4nOwogICAgcmV0dXJuOwogIH0KICB3cmFwLmlubmVySFRNTD1lbnRyaWVzLnNvcnQoKGEsYik9PmFbMF0ubG9jYWxlQ29tcGFyZShiWzBdKSkubWFwKChbZm4saW5mb10pPT57CiAgICBjb25zdCBhZ2U9aW5mby5tdGltZXx8MDsKICAgIGxldCBkYyxkcyxzYzsKICAgIGlmKGFnZTw2MCl7ZGM9J25kLWcnO2RzPSfmraPluLjmjqjpgIEnO3NjPSd2YXIoLS1ncmVlbiknfQogICAgZWxzZSBpZihhZ2U8MzAwKXtkYz0nbmQtYSc7ZHM9YCR7TWF0aC5yb3VuZChhZ2UpfeenkuWJjWA7c2M9J3ZhcigtLWFtYmVyKSd9CiAgICBlbHNle2RjPSduZC1yJztkcz1gJHtNYXRoLnJvdW5kKGFnZS82MCl95YiG6ZKf5YmNYDtzYz0ndmFyKC0tcmVkKSd9CiAgICBjb25zdCBrYj0oaW5mby5zaXplLzEwMjQpLnRvRml4ZWQoMSk7CiAgICByZXR1cm4gYDxkaXYgY2xhc3M9Im5jYXJkIj4KICAgICAgPGRpdiBzdHlsZT0iZGlzcGxheTpmbGV4O2FsaWduLWl0ZW1zOmNlbnRlcjtnYXA6MTJweCI+CiAgICAgICAgPGRpdiBjbGFzcz0ibmRvdCAke2RjfSI+PC9kaXY+CiAgICAgICAgPGRpdj4KICAgICAgICAgIDxkaXYgY2xhc3M9Im5uYW1lIj4ke2VzYyhmbi5yZXBsYWNlKC9cLmxvZyQvLCcnKSl9PC9kaXY+CiAgICAgICAgICA8ZGl2IGNsYXNzPSJubWV0YSI+JHtlc2MoZm4pfSDCtyAke2tifSBLQjwvZGl2PgogICAgICAgIDwvZGl2PgogICAgICA8L2Rpdj4KICAgICAgPGRpdj4KICAgICAgICA8ZGl2IGNsYXNzPSJuc3QiIHN0eWxlPSJjb2xvcjoke3NjfSI+JHtlc2MoZHMpfTwvZGl2PgogICAgICAgIDxkaXYgY2xhc3M9Im5wb3MiPuWBj+enuyAke2luZm8ucG9zfSBCPC9kaXY+CiAgICAgIDwvZGl2PgogICAgPC9kaXY+YDsKICB9KS5qb2luKCcnKTsKfQoKZnVuY3Rpb24gc3dpdGNoVGFiKG5hbWUsYnRuKXsKICBbJ3VzZXJzJywnYmFubmVkJywnbm9kZXMnXS5mb3JFYWNoKHQ9PnsKICAgIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCd0LScrdCkuY2xhc3NMaXN0LnJlbW92ZSgnYWN0aXZlJyk7CiAgICBjb25zdCBjPWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdjb250ZW50LScrdCk7CiAgICBpZihjKWMuc3R5bGUuZGlzcGxheT0nbm9uZSc7CiAgfSk7CiAgYnRuLmNsYXNzTGlzdC5hZGQoJ2FjdGl2ZScpOwogIGNvbnN0IGN0PWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdjb250ZW50LScrbmFtZSk7CiAgaWYoY3QpY3Quc3R5bGUuZGlzcGxheT0nJzsKfQoKYXN5bmMgZnVuY3Rpb24gc2F2ZUxpbWl0KHUpewogIGNvbnN0IGVsPWRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdsaS0nK3UpO2lmKCFlbClyZXR1cm47CiAgY29uc3QgdmFsPXBhcnNlSW50KGVsLnZhbHVlKXx8MDsKICBjb25zdCByPWF3YWl0IHJlcSgnL2xpbWl0cy9zZXQnLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sCiAgICBib2R5OkpTT04uc3RyaW5naWZ5KHt1c2VybmFtZTp1LGlwX2xpbWl0OnZhbH0pfSk7CiAgaWYocil7dG9hc3QoJ29rJyxgJHt1fSDihpIg6ZmQ5Yi2ICR7dmFsPjA/dmFsKycg5LiqSVAnOifkuI3pmZAnfWApO2FsbExpbWl0c1t1XT12YWw7cmVuZGVyVXNlcnMoKX0KICBlbHNlIHRvYXN0KCdlcnInLCfkv53lrZjlpLHotKXvvIzor7fmo4Dmn6XpmZDliLblmajmnI3liqEnKTsKfQoKZnVuY3Rpb24gY29uZmlybVVuYmFuKHUpewogIGRvY3VtZW50LmdldEVsZW1lbnRCeUlkKCdtb2RhbC1tc2cnKS50ZXh0Q29udGVudD1g56Gu5a6a6KaB6Kej5bCB55So5oi3ICIke3V9Iu+8n+ino+WwgeWQjueri+WNs+aBouWkjeato+W4uOS9v+eUqOOAgmA7CiAgZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ21vZGFsLW9rJykub25jbGljaz0oKT0+e2Nsb3NlTW9kYWwoKTtkb1VuYmFuKHUpfTsKICBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnbW9kYWwnKS5zdHlsZS5kaXNwbGF5PSdmbGV4JzsKfQpmdW5jdGlvbiBjbG9zZU1vZGFsKCl7ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ21vZGFsJykuc3R5bGUuZGlzcGxheT0nbm9uZSd9Cgphc3luYyBmdW5jdGlvbiBkb1VuYmFuKHUpewogIGNvbnN0IHI9YXdhaXQgcmVxKCcvdW5iYW4nLHttZXRob2Q6J1BPU1QnLGhlYWRlcnM6eydDb250ZW50LVR5cGUnOidhcHBsaWNhdGlvbi9qc29uJ30sCiAgICBib2R5OkpTT04uc3RyaW5naWZ5KHt1c2VybmFtZTp1fSl9KTsKICBpZihyJiZyLnVuYmFubmVkKXsKICAgIHRvYXN0KCdvaycsYOW3suino+WwgSAke3V9YCk7CiAgICBkZWxldGUgYWxsQmFubmVkW3VdOwogICAgcmVuZGVyQmFubmVkKCk7cmVuZGVyVXNlcnMoKTt1cGRhdGVTdGF0cygpOwogIH1lbHNlIHRvYXN0KCdlcnInLHI/LmVycm9yfHwn6Kej5bCB5aSx6LSlJyk7Cn0KCmFzeW5jIGZ1bmN0aW9uIHVuYmFuQWxsKCl7CiAgY29uc3QgbGlzdD1PYmplY3Qua2V5cyhhbGxCYW5uZWQpO2lmKCFsaXN0Lmxlbmd0aClyZXR1cm47CiAgdG9hc3QoJ2luZm8nLGDmraPlnKjop6PlsIEgJHtsaXN0Lmxlbmd0aH0g5Liq55So5oi3Li4uYCk7CiAgZm9yKGNvbnN0IHUgb2YgbGlzdClhd2FpdCBkb1VuYmFuKHUpOwp9CgpmdW5jdGlvbiBmaWx0ZXJVKHYpe3VGaWx0ZXI9djtyZW5kZXJVc2VycygpfQoKZnVuY3Rpb24gdG9hc3QodHlwZSxtc2cpewogIGNvbnN0IHc9ZG9jdW1lbnQuZ2V0RWxlbWVudEJ5SWQoJ3RvYXN0cycpOwogIGNvbnN0IGVsPU9iamVjdC5hc3NpZ24oZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnZGl2Jykse2NsYXNzTmFtZTondG9hc3QgJyt0eXBlLHRleHRDb250ZW50Om1zZ30pOwogIHcuYXBwZW5kQ2hpbGQoZWwpO3NldFRpbWVvdXQoKCk9PmVsLnJlbW92ZSgpLDM1MDApOwp9CgpmdW5jdGlvbiBlc2Mocyl7CiAgcmV0dXJuIFN0cmluZyhzfHwnJykucmVwbGFjZSgvJi9nLCcmYW1wOycpLnJlcGxhY2UoLzwvZywnJmx0OycpCiAgICAucmVwbGFjZSgvPi9nLCcmZ3Q7JykucmVwbGFjZSgvIi9nLCcmcXVvdDsnKS5yZXBsYWNlKC8nL2csJyYjMzk7Jyk7Cn0KCmRvUmVmcmVzaCgpOwpzZXRJbnRlcnZhbChkb1JlZnJlc2gsMTUwMDApOwo8L3NjcmlwdD4KPC9ib2R5Pgo8L2h0bWw+Cg=='
with open('${CUSTOM_DIR}/ip-dashboard.html','wb') as f:
    f.write(base64.b64decode(html))
print('写入完成，大小:', len(base64.b64decode(html)), 'bytes')
"
  chmod 644 "$CUSTOM_DIR/ip-dashboard.html"
  log_ok "面板文件 → $CUSTOM_DIR/ip-dashboard.html"

  log_step "设置访问鉴权"
  htpasswd -bc "$HTPASSWD_FILE" "$DASH_USER" "$DASH_PASS" 2>/dev/null
  chmod 644 "$HTPASSWD_FILE"
  log_ok "登录凭证已写入 $HTPASSWD_FILE"

  log_step "启动静态文件服务（端口 $STATIC_PORT）"
  cat > /etc/systemd/system/ipl-web.service << SEOF
[Unit]
Description=IPL Dashboard Static Server
After=network.target

[Service]
Type=simple
WorkingDirectory=${CUSTOM_DIR}
ExecStart=/usr/bin/python3 -m http.server ${STATIC_PORT} --bind 127.0.0.1
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SEOF
  systemctl daemon-reload
  systemctl enable ipl-web 2>/dev/null
  systemctl restart ipl-web
  sleep 2
  local SVC_ST; SVC_ST=$(systemctl is-active ipl-web 2>/dev/null)
  [[ "$SVC_ST" == "active" ]] && log_ok "静态服务运行中 ✓" || log_warn "服务启动异常，请检查: systemctl status ipl-web"

  log_step "更新 Nginx 配置"
  [[ -f "$NGINX_CONF" ]] || die "未找到 $NGINX_CONF，请先安装 Marzban 面板（选项1）"

  python3 << PYEOF
import re
path="${NGINX_CONF}"; htpf="${HTPASSWD_FILE}"; dp="${DASH_PATH}"; port="${STATIC_PORT}"
with open(path) as f: c=f.read()
# 清理旧的 ipl-admin location 块
c=re.sub(r'\n?[ \t]*location\s+[=]?\s*'+re.escape(dp)+r'[/]?[^{]*\{[^{}]*(?:\{[^{}]*\}[^{}]*)?\}','',c,flags=re.DOTALL)
new_loc=f"""
    location = {dp} {{
        return 301 {dp}/;
    }}
    location {dp}/ {{
        proxy_pass http://127.0.0.1:{port}/;
        proxy_set_header Host \$host;
        auth_basic "IP Manager";
        auth_basic_user_file {htpf};
    }}
"""
if "location /api-ipl/" in c:
    c=c.replace("    location /api-ipl/",new_loc+"\n    location /api-ipl/",1)
elif "location /mz-plugin/" in c:
    c=c.replace("    location /mz-plugin/",new_loc+"\n    location /mz-plugin/",1)
else:
    last=c.rfind("}"); c=c[:last]+new_loc+"\n"+c[last:]
with open(path,"w") as f: f.write(c)
print("ok")
PYEOF
  log_ok "Nginx 配置已更新"

  log_step "验证并重载 Nginx"
  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    log_ok "Nginx 已重载"
  else
    nginx -t; die "Nginx 配置校验失败，请检查 $NGINX_CONF"
  fi

  log_step "检查 IP 限制器服务"
  local IPL_ST; IPL_ST=$(systemctl is-active marzban-ip-limiter 2>/dev/null || echo "inactive")
  [[ "$IPL_ST" == "active" ]] && log_ok "限制器服务运行中 ✓" || \
    log_warn "限制器未运行（$IPL_ST）— 请先执行选项6安装 IP 限制器"

  cat > /root/ipl-dashboard-info.txt << INFOEOF
══════════════════════════════════════════════
  IP 限制器面板安装信息  $(date '+%Y-%m-%d %H:%M:%S')
══════════════════════════════════════════════
  访问地址 : https://${PANEL_DOMAIN}${DASH_PATH}/
  用户名   : ${DASH_USER}
  密  码   : ${DASH_PASS}
  静态端口 : ${STATIC_PORT}
  修改密码 : htpasswd ${HTPASSWD_FILE} ${DASH_USER}
  查看服务 : systemctl status ipl-web
══════════════════════════════════════════════
INFOEOF
  chmod 600 /root/ipl-dashboard-info.txt

  echo
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  🎉  IP 限制器管理面板安装完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${C}访问地址${NC}  https://${W}${PANEL_DOMAIN}${DASH_PATH}/${NC}"
  echo -e "  ${C}用户名  ${NC}  ${W}${DASH_USER}${NC}"
  echo -e "  ${C}密  码  ${NC}  ${W}${DASH_PASS}${NC}"
  echo
  echo -e "  ${DIM}面板功能: 在线用户·IP数量·封禁倒计时·一键解封·节点推送状态${NC}"
  echo -e "  ${DIM}信息已保存至 /root/ipl-dashboard-info.txt${NC}"
  echo
  echo -e "  ${Y}重置密码: ${DIM}htpasswd ${HTPASSWD_FILE} ${DASH_USER}${NC}"
  echo
  read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 8 - 安装 Clash 分流规则 + Nginx UA 自动识别
# ══════════════════════════════════════════════════════════════
install_clash_rules() {
  show_banner
  echo -e "\n${C}┌─ ${W}安装 Clash 分流规则 + Nginx UA 自动识别 ${C}─${NC}"
  echo -e "  ${DIM}规则集: Semporia/Clash  |  支持自动识别 Clash 客户端${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  # ── 检测 Marzban ──────────────────────────────────────────
  log_step "检测 Marzban 安装路径"
  local MARZBAN_DIR=""
  for dir in /opt/marzban /root/marzban /home/marzban; do
    [[ -f "$dir/.env" && -f "$dir/docker-compose.yml" ]] && MARZBAN_DIR="$dir" && break
  done
  [[ -z "$MARZBAN_DIR" ]] && die "未找到 Marzban 安装目录（需先运行选项1）"
  log_ok "Marzban 目录: $MARZBAN_DIR"

  local ENV_FILE="$MARZBAN_DIR/.env"
  local CONTAINER_NAME; CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep -i marzban | head -1)
  [[ -z "$CONTAINER_NAME" ]] && die "Marzban 容器未运行，请先启动"
  log_ok "容器: $CONTAINER_NAME"

  # ── 读取配置 ──────────────────────────────────────────────
  log_step "读取配置"
  local TEMPLATES_DIR; TEMPLATES_DIR=$(grep "^CUSTOM_TEMPLATES_DIRECTORY=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
  [[ -z "$TEMPLATES_DIR" ]] && TEMPLATES_DIR="/var/lib/marzban/templates"
  local SUB_PREFIX; SUB_PREFIX=$(grep "^XRAY_SUBSCRIPTION_URL_PREFIX=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
  log_ok "模板目录: $TEMPLATES_DIR"
  log_ok "订阅前缀: ${SUB_PREFIX:-（未检测到）}"

  # ── 确认 ──────────────────────────────────────────────────
  echo
  echo -e "  ${Y}此操作将：${NC}"
  echo -e "  ${DIM}· 在 $TEMPLATES_DIR/clash/ 写入 Semporia 分流规则模板${NC}"
  echo -e "  ${DIM}· 配置 Nginx UA 自动识别（Clash 客户端自动获取分流订阅）${NC}"
  echo -e "  ${DIM}· 重启 Marzban 容器使配置生效${NC}"
  echo
  read -rp "$(echo -e "  ${Y}确认安装? [Y/n]: ${NC}")" CONFIRM
  [[ "${CONFIRM:-Y}" =~ ^[Nn]$ ]] && return

  # ── 备份默认模板 ──────────────────────────────────────────
  log_step "备份默认 Clash 模板"
  docker exec "$CONTAINER_NAME" cat /code/app/templates/clash/default.yml \
    > /tmp/clash_default_backup.yml 2>/dev/null && \
    log_ok "已备份到 /tmp/clash_default_backup.yml" || log_warn "未能读取默认模板（不影响部署）"

  # ── 写入 Clash 分流模板 ───────────────────────────────────
  log_step "写入 Clash 分流规则模板（Semporia 规则集）"
  mkdir -p "$TEMPLATES_DIR/clash"

  python3 -c "
import sys
path = '${TEMPLATES_DIR}/clash/default.yml'
content = '''mode: rule
mixed-port: 7890
socks-port: 7891
allow-lan: true
bind-address: \"*\"
log-level: info
ipv6: true

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

{{ conf | except(\"proxy-groups\", \"port\", \"mode\") | yaml }}

proxy-groups:
  - name: \"\U0001f680 节点选择\"
    type: select
    proxies:
      - \"\u267b\ufe0f Auto\"
      - DIRECT
      {{ proxy_remarks | yaml | indent(6) }}

  - name: \"\u267b\ufe0f Auto\"
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Apple
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Adobe
    type: select
    proxies:
      - REJECT
      - \"\U0001f680 节点选择\"

  - name: Amazon
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      - DIRECT
      {{ proxy_remarks | yaml | indent(6) }}

  - name: China
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: Facebook
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: GitHub
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Google
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Microsoft
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Netflix
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Spotify
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Steam
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Telegram
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Twitter
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: YouTube
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: WhatsApp
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: PayPal
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      {{ proxy_remarks | yaml | indent(6) }}

  - name: Tencent
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: WeChat
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: Zoom
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: Speedtest
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: ChinaIP
    type: select
    proxies:
      - DIRECT
      - \"\U0001f680 节点选择\"

  - name: \"\U0001f30d Global\"
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      - \"\u267b\ufe0f Auto\"
      - DIRECT
      {{ proxy_remarks | yaml | indent(6) }}

  - name: MATCH
    type: select
    proxies:
      - \"\U0001f680 节点选择\"
      - DIRECT

rule-providers:
  Adobe:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Adobe.yaml
    path: ./ruleset/Adobe.yaml
  Apple:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Apple.yaml
    path: ./ruleset/Apple.yaml
  Amazon:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Amazon.yaml
    path: ./ruleset/Amazon.yaml
  China:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/China.yaml
    path: ./ruleset/China.yaml
  DingTalk:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/DingTalk.yaml
    path: ./ruleset/DingTalk.yaml
  Facebook:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Facebook.yaml
    path: ./ruleset/Facebook.yaml
  GitHub:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/GitHub.yaml
    path: ./ruleset/GitHub.yaml
  Google:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Google.yaml
    path: ./ruleset/Google.yaml
  Microsoft:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Microsoft.yaml
    path: ./ruleset/Microsoft.yaml
  Netflix:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Netflix.yaml
    path: ./ruleset/Netflix.yaml
  NetEase:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/NetEase.yaml
    path: ./ruleset/NetEase.yaml
  Spotify:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Spotify.yaml
    path: ./ruleset/Spotify.yaml
  Speedtest:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Speedtest.yaml
    path: ./ruleset/Speedtest.yaml
  Steam:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Steam.yaml
    path: ./ruleset/Steam.yaml
  Telegram:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Telegram.yaml
    path: ./ruleset/Telegram.yaml
  Twitter:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Twitter.yaml
    path: ./ruleset/Twitter.yaml
  Tencent:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Tencent.yaml
    path: ./ruleset/Tencent.yaml
  TencentVideo:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/TencentVideo.yaml
    path: ./ruleset/TencentVideo.yaml
  YouTube:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/YouTube.yaml
    path: ./ruleset/YouTube.yaml
  WhatsApp:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/WhatsApp.yaml
    path: ./ruleset/WhatsApp.yaml
  WeChat:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/WeChat.yaml
    path: ./ruleset/WeChat.yaml
  PayPal:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/PayPal.yaml
    path: ./ruleset/PayPal.yaml
  Zoom:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Zoom.yaml
    path: ./ruleset/Zoom.yaml
  ChinaIP:
    type: http
    behavior: ipcidr
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/soffchen/GeoIP2-CN@release/clash-rule-provider.yml
    path: ./ruleset/ChinaIP.yaml
  Proxy:
    type: http
    behavior: classical
    interval: 86400
    url: https://cdn.jsdelivr.net/gh/Semporia/Clash@master/Rule/Proxy.yaml
    path: ./ruleset/Proxy.yaml

rules:
  - RULE-SET,Adobe,REJECT
  - RULE-SET,Apple,Apple
  - RULE-SET,Amazon,Amazon
  - RULE-SET,DingTalk,DIRECT
  - RULE-SET,Facebook,Facebook
  - RULE-SET,GitHub,GitHub
  - RULE-SET,Google,Google
  - RULE-SET,Microsoft,Microsoft
  - RULE-SET,Netflix,Netflix
  - RULE-SET,NetEase,DIRECT
  - RULE-SET,Spotify,Spotify
  - RULE-SET,Speedtest,Speedtest
  - RULE-SET,Steam,Steam
  - RULE-SET,Telegram,Telegram
  - RULE-SET,Twitter,Twitter
  - RULE-SET,Tencent,Tencent
  - RULE-SET,TencentVideo,DIRECT
  - RULE-SET,YouTube,YouTube
  - RULE-SET,WhatsApp,WhatsApp
  - RULE-SET,WeChat,WeChat
  - RULE-SET,PayPal,PayPal
  - RULE-SET,Zoom,Zoom
  - RULE-SET,China,DIRECT
  - RULE-SET,ChinaIP,DIRECT
  - RULE-SET,Proxy,\U0001f30d Global
  - IP-CIDR,192.168.0.0/16,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT
  - IP-CIDR,172.16.0.0/12,DIRECT
  - IP-CIDR,127.0.0.0/8,DIRECT
  - IP-CIDR,100.64.0.0/10,DIRECT
  - IP-CIDR,224.0.0.0/4,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,MATCH
'''
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('OK')
" 2>&1 || die "Clash 模板写入失败"

  # 验证模板
  python3 -c "
with open('${TEMPLATES_DIR}/clash/default.yml', encoding='utf-8') as f:
    c = f.read()
ok = ('节点选择' in c) and ('{{ conf' in c) and ('Semporia' in c) and ('rule-providers' in c)
print('验证: emoji={} jinja={} semporia={} rules={}'.format(
    '节点选择' in c, '{{ conf' in c, 'Semporia' in c, 'rule-providers' in c))
exit(0 if ok else 1)
" || die "模板验证失败，请检查 Python3 是否支持 Unicode"
  log_ok "模板已写入: $TEMPLATES_DIR/clash/default.yml"

  # ── 配置 .env ──────────────────────────────────────────────
  log_step "配置 .env"
  if ! grep -q "^CUSTOM_TEMPLATES_DIRECTORY=" "$ENV_FILE"; then
    echo "CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATES_DIR" >> "$ENV_FILE"
    log_ok "已添加 CUSTOM_TEMPLATES_DIRECTORY=$TEMPLATES_DIR"
  else
    log_ok "CUSTOM_TEMPLATES_DIRECTORY 已存在"
  fi
  # 移除自定义 CLASH_SUBSCRIPTION_TEMPLATE（使用默认路径）
  if grep -q "^CLASH_SUBSCRIPTION_TEMPLATE=" "$ENV_FILE"; then
    sed -i '/^CLASH_SUBSCRIPTION_TEMPLATE=/d' "$ENV_FILE"
    log_warn "已移除旧的 CLASH_SUBSCRIPTION_TEMPLATE 覆盖配置"
  fi
  # 清理旧文件
  [[ -f "$TEMPLATES_DIR/clash.yml" ]] && rm -f "$TEMPLATES_DIR/clash.yml" && log_warn "已清理旧文件 clash.yml"

  # ── Nginx UA 自动识别 ──────────────────────────────────────
  log_step "配置 Nginx UA 自动识别"
  local NGINX_CONF=""
  for f in /etc/nginx/conf.d/*.conf /etc/nginx/sites-enabled/*; do
    [[ -f "$f" ]] && grep -q "proxy_pass.*127.0.0.1:8000" "$f" 2>/dev/null && NGINX_CONF="$f" && break
  done

  if [[ -z "$NGINX_CONF" ]]; then
    log_warn "未找到 Nginx 配置，跳过 UA 自动识别"
    log_warn "手动使用时在订阅链接后加 /clash-meta 获取分流订阅"
  else
    log_ok "Nginx 配置: $NGINX_CONF"
    # 备份
    cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"

    if grep -q "clash-ua-redirect" "$NGINX_CONF" 2>/dev/null; then
      log_ok "Clash UA 重写规则已存在，跳过"
    else
      # 创建 UA map 文件
      if [[ ! -f /etc/nginx/conf.d/00-clash-ua-map.conf ]]; then
        cat > /etc/nginx/conf.d/00-clash-ua-map.conf << 'MAPEOF'
# clash-ua-redirect: Clash 客户端 UA 识别
map $http_user_agent $is_clash_client {
    default         0;
    "~*[Cc]lash"    1;
    "~*mihomo"      1;
    "~*[Ss]tash"    1;
}
MAPEOF
        log_ok "已创建 UA 识别 map 文件"
      fi

      # 在 location / 之前插入订阅路径重写
      if grep -q "location / {" "$NGINX_CONF"; then
        sed -i "/location \/ {/i\\
    # clash-ua-redirect: 自动识别 Clash 客户端\\
    location ~ ^\\/sub\\/([^\\/]+)\$ {\\
        if (\$is_clash_client) {\\
            rewrite ^\\/sub\\/(.*)\$ /sub/\$1/clash-meta break;\\
        }\\
        proxy_pass http://127.0.0.1:8000;\\
        proxy_set_header Host \$host;\\
        proxy_set_header X-Real-IP \$remote_addr;\\
        proxy_http_version 1.1;\\
        proxy_set_header Upgrade \$http_upgrade;\\
        proxy_set_header Connection \"upgrade\";\\
    }\\
" "$NGINX_CONF"
        log_ok "已添加订阅路径重写规则"

        if nginx -t 2>/dev/null; then
          systemctl reload nginx 2>/dev/null
          log_ok "Nginx 已重载"
        else
          log_err "Nginx 配置校验失败，正在恢复..."
          local LATEST_BAK; LATEST_BAK=$(ls -t "${NGINX_CONF}.bak."* 2>/dev/null | head -1)
          [[ -n "$LATEST_BAK" ]] && cp "$LATEST_BAK" "$NGINX_CONF"
          rm -f /etc/nginx/conf.d/00-clash-ua-map.conf
          nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
          log_warn "Nginx 已恢复，UA 自动识别未启用"
        fi
      else
        log_warn "未找到 'location / {'，跳过 UA 重写（可手动添加）"
      fi
    fi
  fi

  # ── 重启 Marzban ──────────────────────────────────────────
  log_step "重启 Marzban（应用模板配置）"
  cd "$MARZBAN_DIR"
  local COMPOSE_CMD="docker compose"
  command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1 && COMPOSE_CMD="docker-compose"
  $COMPOSE_CMD down 2>&1 | tail -2
  $COMPOSE_CMD up -d 2>&1 | tail -2

  log_info "等待 Marzban 启动（约18秒）..."
  for i in $(seq 1 18); do
    sleep 1; printf "\r  等待 %ds..." $i
    local hc; hc=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "http://127.0.0.1:8000/" 2>/dev/null || echo "000")
    [[ "$hc" == "200" || "$hc" == "301" ]] && break
  done; echo

  # ── 验证 ──────────────────────────────────────────────────
  log_step "验证订阅模板"
  local TOKEN; TOKEN=$(docker compose logs --tail=200 2>/dev/null | grep -oP '/sub/\K[^/\s]+' | head -1)
  if [[ -n "$TOKEN" && -n "$SUB_PREFIX" ]]; then
    local RESULT; RESULT=$(curl -sA 'clash-verge/v1.0' "${SUB_PREFIX}/sub/${TOKEN}/clash-meta" 2>/dev/null | head -3)
    if echo "$RESULT" | grep -q "mode: rule"; then
      log_ok "订阅验证通过！(mode: rule 存在)"
    else
      log_warn "自动验证未通过，请手动访问订阅链接检查"
    fi
  else
    log_warn "无法获取 token 自动验证，请手动测试"
  fi

  # ── 完成 ──────────────────────────────────────────────────
  echo
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  🎉  Clash 分流规则安装完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${C}用户使用方式：${NC}"
  echo -e "  ${W}Clash 客户端${NC}  → 直接导入面板订阅链接，自动获取分流规则"
  echo -e "  ${W}V2rayN 等     ${NC}→ 正常导入，获取节点列表"
  [[ -n "$SUB_PREFIX" ]] && \
  echo -e "  ${W}手动订阅地址${NC}  → ${C}${SUB_PREFIX}/sub/<token>/clash-meta${NC}"
  echo
  echo -e "  ${Y}已集成分流规则：${NC}"
  echo -e "  ${DIM}Apple · Adobe(拦截) · Amazon · Facebook · GitHub${NC}"
  echo -e "  ${DIM}Google · Microsoft · Netflix · Spotify · Steam${NC}"
  echo -e "  ${DIM}Telegram · Twitter · YouTube · WhatsApp · PayPal${NC}"
  echo -e "  ${DIM}Tencent · WeChat · Zoom · Speedtest · China · ChinaIP${NC}"
  echo
  echo -e "  ${Y}恢复默认：${NC}"
  echo -e "  ${DIM}rm -rf $TEMPLATES_DIR/clash/${NC}"
  echo -e "  ${DIM}rm -f /etc/nginx/conf.d/00-clash-ua-map.conf${NC}"
  echo -e "  ${DIM}cd $MARZBAN_DIR && docker compose down && docker compose up -d${NC}"
  echo -e "  ${DIM}nginx -t && systemctl reload nginx${NC}"
  echo
  read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 9 - 卸载清空面板机
# ══════════════════════════════════════════════════════════════
uninstall_panel() {
  show_banner
  echo -e "\n${R}┌─ ${W}卸载清空 面板机 ${R}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  echo -e "  ${R}${BOLD}⚠ 警告：此操作将彻底删除以下内容：${NC}"
  echo -e "  ${DIM}· Marzban 容器及镜像${NC}"
  echo -e "  ${DIM}· /opt/marzban/ 目录（含 .env、docker-compose.yml）${NC}"
  echo -e "  ${DIM}· /var/lib/marzban/ 目录（含数据库、证书、日志）${NC}"
  echo -e "  ${DIM}· IP 限制器服务及数据${NC}"
  echo -e "  ${DIM}· Nginx Marzban 配置及 Clash UA 规则${NC}"
  echo -e "  ${DIM}· IP 限制器 Web 管理面板${NC}"
  echo -e "  ${DIM}· 节点看门狗 cron 任务${NC}"
  echo
  echo -e "  ${R}${BOLD}数据库将被永久删除，无法恢复！${NC}"
  echo
  read -rp "$(echo -e "  ${Y}确认卸载? 请输入 YES 确认: ${NC}")" CONFIRM
  [[ "$CONFIRM" != "YES" ]] && { echo -e "  ${G}已取消${NC}"; return; }
  read -rp "$(echo -e "  ${R}再次确认，输入 DELETE 继续: ${NC}")" CONFIRM2
  [[ "$CONFIRM2" != "DELETE" ]] && { echo -e "  ${G}已取消${NC}"; return; }

  echo
  log_step "停止并删除 Marzban 容器"
  cd /opt/marzban 2>/dev/null && docker compose down --rmi all --volumes 2>/dev/null || true
  docker rm -f marzban 2>/dev/null || true
  docker rmi gozargah/marzban 2>/dev/null || true
  log_ok "容器已清除"

  log_step "停止 IP 限制器服务"
  systemctl stop marzban-ip-limiter 2>/dev/null || true
  systemctl disable marzban-ip-limiter 2>/dev/null || true
  rm -f /etc/systemd/system/marzban-ip-limiter.service
  rm -rf /etc/systemd/system/marzban-ip-limiter.service.d/
  log_ok "IP 限制器服务已移除"

  log_step "停止 IP 面板静态服务"
  systemctl stop ipl-web 2>/dev/null || true
  systemctl disable ipl-web 2>/dev/null || true
  rm -f /etc/systemd/system/ipl-web.service
  log_ok "ipl-web 服务已移除"

  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true

  log_step "删除 Marzban 数据目录"
  rm -rf /opt/marzban/
  log_ok "/opt/marzban/ 已删除"

  log_step "删除 Marzban 数据库及证书"
  rm -rf /var/lib/marzban/
  log_ok "/var/lib/marzban/ 已删除"

  log_step "清理 Nginx 配置"
  rm -f /etc/nginx/sites-available/marzban
  rm -f /etc/nginx/sites-enabled/marzban
  rm -f /etc/nginx/conf.d/00-clash-ua-map.conf
  rm -f /etc/nginx/.ipl_htpasswd
  # 重新加载 nginx（如果还有其他站点）
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  log_ok "Nginx 配置已清理"

  log_step "删除命令行工具"
  rm -f /usr/local/bin/ip-manage
  rm -f /usr/local/bin/marzban-watchdog.sh
  log_ok "命令行工具已删除"

  log_step "删除 cron 任务"
  crontab -l 2>/dev/null | grep -v marzban-watchdog | crontab - 2>/dev/null || true
  rm -f /etc/cron.d/marzban-cert-sync
  rm -f /etc/cron.d/marzban-cert-renew-panel
  log_ok "cron 任务已清除"

  log_step "删除安装信息文件"
  rm -f /root/marzban-info.txt
  rm -f /root/ipl-dashboard-info.txt
  log_ok "信息文件已删除"

  echo
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  ✅  面板机卸载完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${DIM}如需重新安装，运行本脚本选择选项 1${NC}"
  echo
  read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  选项 10 - 卸载清空节点机
# ══════════════════════════════════════════════════════════════
uninstall_node() {
  show_banner
  echo -e "\n${R}┌─ ${W}卸载清空 节点机 ${R}─${NC}\n"
  [[ $EUID -ne 0 ]] && die "请以 root 运行"

  echo -e "  ${R}${BOLD}⚠ 警告：此操作将彻底删除以下内容：${NC}"
  echo -e "  ${DIM}· marzban-node 容器及镜像${NC}"
  echo -e "  ${DIM}· /opt/marzban-node/ 目录（含 docker-compose.yml）${NC}"
  echo -e "  ${DIM}· /var/lib/marzban-node/ 目录（含证书、日志）${NC}"
  echo -e "  ${DIM}· /var/lib/marzban/ 目录（同步证书及日志）${NC}"
  echo -e "  ${DIM}· 节点日志推送服务（marzban-push-*）${NC}"
  echo -e "  ${DIM}· 证书自动同步 cron 任务${NC}"
  echo
  read -rp "$(echo -e "  ${Y}确认卸载? 请输入 YES 确认: ${NC}")" CONFIRM
  [[ "$CONFIRM" != "YES" ]] && { echo -e "  ${G}已取消${NC}"; return; }
  read -rp "$(echo -e "  ${R}再次确认，输入 DELETE 继续: ${NC}")" CONFIRM2
  [[ "$CONFIRM2" != "DELETE" ]] && { echo -e "  ${G}已取消${NC}"; return; }

  echo
  log_step "停止并删除 marzban-node 容器"
  cd /opt/marzban-node 2>/dev/null && docker compose down --rmi all --volumes 2>/dev/null || true
  docker rm -f marzban-node 2>/dev/null || true
  docker rmi gozargah/marzban-node 2>/dev/null || true
  log_ok "容器已清除"

  log_step "停止节点日志推送服务"
  for svc in $(systemctl list-units --type=service --all 2>/dev/null | grep "marzban-push" | awk '{print $1}'); do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/${svc}"
    log_ok "已删除推送服务: $svc"
  done
  rm -rf /opt/marzban-push/
  log_ok "节点推送服务已清除"

  systemctl daemon-reload
  systemctl reset-failed 2>/dev/null || true

  log_step "删除节点目录"
  rm -rf /opt/marzban-node/
  log_ok "/opt/marzban-node/ 已删除"

  log_step "删除节点数据目录"
  rm -rf /var/lib/marzban-node/
  log_ok "/var/lib/marzban-node/ 已删除"

  log_step "删除面板兼容目录"
  rm -rf /var/lib/marzban/
  log_ok "/var/lib/marzban/ 已删除"

  log_step "删除证书同步 cron"
  rm -f /etc/cron.d/marzban-cert-sync
  rm -f /etc/cron.d/marzban-cert-renew-node
  crontab -l 2>/dev/null | grep -v marzban | crontab - 2>/dev/null || true
  log_ok "cron 任务已清除"

  log_step "删除安装信息文件"
  rm -f /root/marzban-node-info.txt
  log_ok "信息文件已删除"

  echo
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${G}  ✅  节点机卸载完成！${NC}"
  echo -e "${G}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "  ${DIM}如需重新安装节点，运行本脚本选择选项 2${NC}"
  echo -e "  ${DIM}记得在面板后台删除对应节点记录${NC}"
  echo
  read -rp "  按 Enter 返回主菜单..."
}

# ══════════════════════════════════════════════════════════════
#  主入口
# ══════════════════════════════════════════════════════════════
main() {
  while true; do
    show_menu
    case "$CHOICE" in
      1) install_panel ;;
      2) install_node ;;
      3) change_reality_dest ;;
      4) diag_panel ;;
      5) diag_node ;;
      6) install_ip_limiter ;;
      7) install_ip_dashboard ;;
      8) install_clash_rules ;;
      9) uninstall_panel ;;
      10) uninstall_node ;;
      0) echo -e "\n  ${G}再见！${NC}\n"; exit 0 ;;
      *) echo -e "  ${R}无效选项${NC}"; sleep 1 ;;
    esac
  done
}

main
