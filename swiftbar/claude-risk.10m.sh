#!/bin/bash
# SwiftBar 插件: Claude 环境风险评分 (10 分钟刷新)
# v3: 探测失败自动重试 + 连续2次严重失败才翻红 (防抖), 单次异常黄色待确认
DATA_DIR="$HOME/Library/Application Support/CheckClaude"
REPORT="$DATA_DIR/last-report.txt"
STATE="$DATA_DIR/plugin-state"
CURL="curl -LfsS --connect-timeout 4 --max-time 5"
IPRE='([0-9]{1,3}\.){3}[0-9]{1,3}'

FAIL_STREAK=0; LAST_GOOD_SCORE=100; LAST_GOOD_ICON="🟢"
[ -f "$STATE" ] && source "$STATE" 2>/dev/null

# ── 并行快探 (关键探测失败自动重试1次) ──
tmp=$(mktemp -d)
p(){ local out="$1"; shift; $CURL "$@" -o "$out" >/dev/null 2>&1 || { sleep 2; $CURL "$@" -o "$out" >/dev/null 2>&1; }; }
pa(){ local out="$1"; shift; $CURL "$@" >"$out" 2>/dev/null || { sleep 2; $CURL "$@" >"$out" 2>/dev/null; }; }
p "$tmp/intl" https://icanhazip.com &
p "$tmp/cn1"  https://ip.3322.net &
p "$tmp/cn2"  https://myip.ipip.net &
p "$tmp/trace" https://www.cloudflare.com/cdn-cgi/trace &
pa "$tmp/api" -X POST https://api.anthropic.com/v1/messages -H "content-type: application/json" -d '{}' -w "%{http_code}" &
p "$tmp/geo"  "http://ip-api.com/json/?fields=countryCode,city,isp,timezone" &
# WebRTC 实测: 真发一个 STUN 包, 看映射出的公网地址是谁 (被 pf 拦=无响应=安全; =代理出口=安全; =其它公网IP=真泄漏)
p_stun(){ python3 -c "
import socket,struct,os,sys
try:
    tid=os.urandom(12)
    msg=struct.pack('>HHI',0x0001,0,0x2112A442)+tid
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.settimeout(3)
    s.sendto(msg,('stun.l.google.com',19302))
    data,_=s.recvfrom(2048)
    i=20
    while i+4<=len(data):
        t,l=struct.unpack('>HH',data[i:i+4]); v=data[i+4:i+4+l]
        if t==0x0020:
            port=struct.unpack('>H',v[2:4])[0]^0x2112
            ip=socket.inet_ntoa(struct.pack('>I',struct.unpack('>I',v[4:8])[0]^0x2112A442))
            print(ip); sys.exit(0)
        i+=4+l+(l%4)
except Exception: pass
" >"$tmp/stun" 2>/dev/null; }
p_stun &
wait

is_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
INTL_IP=$(grep -Eo "$IPRE" "$tmp/intl" 2>/dev/null | head -1)
CN_IP=$(grep -Eo "$IPRE" "$tmp/cn1" 2>/dev/null | head -1)
[ -z "$CN_IP" ] && CN_IP=$(grep -Eo "$IPRE" "$tmp/cn2" 2>/dev/null | head -1)
GFW_IP=$(grep -E '^ip=' "$tmp/trace" 2>/dev/null | head -1 | cut -d= -f2)
API=$(tr -d '[:space:]' <"$tmp/api" 2>/dev/null)
CC=$(python3 -c "import json;print(json.load(open('$tmp/geo')).get('countryCode','?'))" 2>/dev/null)
GCITY=$(python3 -c "import json;print(json.load(open('$tmp/geo')).get('city','?'))" 2>/dev/null)
GTZ=$(python3 -c "import json;print(json.load(open('$tmp/geo')).get('timezone',''))" 2>/dev/null)
GISP=$(python3 -c "import json;print(json.load(open('$tmp/geo')).get('isp',''))" 2>/dev/null)
rm -rf "$tmp"

SYS_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
SYS_DNS=$(scutil --dns 2>/dev/null | grep "nameserver\[" | awk '{print $3}' | grep -vE '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.)' | sort -u | head -1)
SB_ON=$(pgrep -x sing-box >/dev/null && echo 1 || echo 0)
PF_REFS=$(grep -c claude-webrtc-guard /etc/pf.conf 2>/dev/null)

# ── 评分 (模型加权简版; 探测失败不计分) ──
SCORE=100; CRIT=0; WARN=0
EXIT_OK=0
is_ip "$INTL_IP" || INTL_IP=""
if [ -n "$INTL_IP" ]; then
  case "$CC" in CN|HK|RU|IR|CU|BY|VE|SD|AF|SY) ;; *) EXIT_OK=1;; esac
fi
[ "$EXIT_OK" = 1 ] || { SCORE=$((SCORE-14)); CRIT=1; }
[ "$API" = "401" ] || { SCORE=$((SCORE-10)); CRIT=1; }
[ "$SB_ON" = "1" ] || { SCORE=$((SCORE-10)); CRIT=1; }

THREE_STATE="ok"
if [ -n "$INTL_IP" ] && [ -n "$CN_IP" ] && [ "$INTL_IP" != "$CN_IP" ]; then
  THREE_STATE="mismatch"
elif [ -n "$INTL_IP" ] && [ -n "$GFW_IP" ] && [ "$INTL_IP" != "$GFW_IP" ]; then
  THREE_STATE="mismatch"
else
  [ -z "$CN_IP" ] && THREE_STATE="partial"
  [ -z "$GFW_IP" ] && THREE_STATE="partial"
  [ -z "$INTL_IP" ] && THREE_STATE="partial"
fi
[ "$THREE_STATE" = "mismatch" ] && { SCORE=$((SCORE-5)); WARN=1; }

TZ_OK=0
if [ -n "$GTZ" ]; then
  if [ "$GTZ" = "$SYS_TZ" ]; then TZ_OK=1; else SCORE=$((SCORE-5)); WARN=1; fi
fi
DNS_OK=0
case "$SYS_DNS" in
  223.5.5.5|223.6.6.6|114.114.114.114|119.29.29.29|180.76.76.76) SCORE=$((SCORE-4)); WARN=1;;
  "") ;;
  *) DNS_OK=1;;
esac
PF_OK=0
[ "${PF_REFS:-0}" -ge 2 ] && PF_OK=1 || { SCORE=$((SCORE-3)); WARN=1; }

# WebRTC 实测: STUN 映射 = 代理出口或被拦截 → 安全; = 其它公网 IP → 真泄漏 (确定性, 立即红)
STUN_IP=$(grep -Eo "$IPRE" "$tmp/stun" 2>/dev/null | head -1)
WEBRTC_STATE="blocked"
if [ -n "$STUN_IP" ]; then
  case "$STUN_IP" in
    192.168.*|10.*|127.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) WEBRTC_STATE="odd" ;;
    *)
      if { [ -n "$GFW_IP" ] && [ "$STUN_IP" = "$GFW_IP" ]; } || { [ -n "$INTL_IP" ] && [ "$STUN_IP" = "$INTL_IP" ]; }; then
        WEBRTC_STATE="via_proxy"
      elif [ -z "$GFW_IP" ] && [ -z "$INTL_IP" ]; then
        WEBRTC_STATE="unknown"
      else
        WEBRTC_STATE="leak"
      fi ;;
  esac
fi
case "$WEBRTC_STATE" in
  leak)    SCORE=$((SCORE-6)); CRIT=1; CERTAIN=1;;
  odd)     ;;
  unknown) ;;
esac

# ── 告警分级 ──
# 确定性本地故障(sing-box挂/pf丢) = 真危险, 立即红, 不防抖;
# 远端测量失败(网络瞬断) = 不确定, 防抖: 单次黄"待确认", 连续≥2次才红
CERTAIN_FAIL=0
[ "$SB_ON" != "1" ] && CERTAIN_FAIL=1
[ "$PF_OK" != "1" ] && CERTAIN_FAIL=1
[ "$WEBRTC_STATE" = "leak" ] && CERTAIN_FAIL=1
DEBOUNCE=0
if [ "$CRIT" = 1 ]; then
  FAIL_STREAK=$((FAIL_STREAK+1))
  if [ "$CERTAIN_FAIL" = 1 ]; then
    ICON="🔴"; TITLE_SCORE="$SCORE"
  elif [ "$FAIL_STREAK" -lt 2 ] && [ "${LAST_GOOD_SCORE:-100}" -ge 70 ]; then
    DEBOUNCE=1; ICON="🟡"; TITLE_SCORE="$LAST_GOOD_SCORE"
  else
    ICON="🔴"; TITLE_SCORE="$SCORE"
  fi
else
  FAIL_STREAK=0; ICON="🟢"; TITLE_SCORE="$SCORE"
  [ "$WARN" = 1 ] && ICON="🟡"
  LAST_GOOD_SCORE="$SCORE"; LAST_GOOD_ICON="$ICON"
fi
printf 'FAIL_STREAK=%s\nLAST_GOOD_SCORE=%s\nLAST_GOOD_ICON=%s\n' "$FAIL_STREAK" "$LAST_GOOD_SCORE" "$LAST_GOOD_ICON" > "$STATE"

tick(){ [ "$1" = 1 ] && echo "✓" || echo "✗"; }

# ── 输出 (SwiftBar 格式) ──
echo "${ICON}${TITLE_SCORE}"
echo "---"
if [ "$DEBOUNCE" = 1 ]; then
  echo "⚠️ 本轮探测异常(第${FAIL_STREAK}次), 下轮确认中 — 可能为网络瞬断"
  echo "上次健康分: ${LAST_GOOD_SCORE}/100 · 若下轮仍异常将显示真实降分"
  echo "---"
fi
echo "Claude 环境风险: ${SCORE}/100 ($([ "$CRIT" = 1 ] && echo 存在严重问题 || ([ "$WARN" = 1 ] && echo 有轻微问题 || echo 全部正常)))"
echo "出口: ${INTL_IP:-探测失败} ${CC} ${GCITY} · ${GISP}"
echo "---"
echo "$(tick $EXIT_OK) 出口国家: ${CC:-探测失败}"
echo "$(tick $([ "$API" = "401" ] && echo 1 || echo 0)) Anthropic API: HTTP ${API:-无响应} (401=健康)"
case "$THREE_STATE" in
  ok)       echo "✓ 三路一致: 国内 ${CN_IP} / 国际 ${INTL_IP} / 谷歌 ${GFW_IP}";;
  mismatch) echo "✗ 三路不一致: 国内 ${CN_IP:-?} / 国际 ${INTL_IP:-?} / 谷歌 ${GFW_IP:-?}";;
  partial)  echo "… 三路: 部分探测失败(不计分) 国内 ${CN_IP:-失败} / 国际 ${INTL_IP:-失败} / 谷歌 ${GFW_IP:-失败}";;
esac
if [ -n "$GTZ" ]; then
  echo "$(tick $TZ_OK) 时区匹配: 系统 ${SYS_TZ} / 出口 ${GTZ}"
else
  echo "… 时区: 出口地理位置探测失败(不计分)"
fi
case "$DNS_OK" in
  1) echo "✓ DNS: ${SYS_DNS}";;
  0) echo "✗ DNS: ${SYS_DNS} (国内解析器,建议换 1.1.1.1)";;
  *) echo "… DNS: 未检测到自定义解析器";;
esac
echo "$(tick $PF_OK) pf 防泄漏规则: $([ "$PF_OK" = 1 ] && echo 已加载 || echo 未加载!)"
case "$WEBRTC_STATE" in
  via_proxy) echo "✓ WebRTC 实测: STUN 经代理出口 ($STUN_IP)";;
  blocked)   echo "✓ WebRTC 实测: STUN 已被拦截 (无泄漏通道)";;
  leak)      echo "✗ WebRTC 泄漏: STUN 映射到 $STUN_IP (非代理出口!)";;
  odd)       echo "… WebRTC 实测: STUN 映射到内网地址 $STUN_IP (不计分)";;
  *)         echo "… WebRTC 实测: 出口未知无法比对 (不计分)";;
esac
echo "$(tick $SB_ON) sing-box: $([ "$SB_ON" = 1 ] && echo 运行中 || echo 未运行!)"
echo "---"
if [ -f "$REPORT" ]; then
  RSCORE=$(grep -m1 -o '[0-9]\+/100' "$REPORT" | head -1)
  RTIME=$(stat -f '%Sm' -t '%m-%d %H:%M' "$REPORT")
  echo "上次完整体检: ${RSCORE:-?} · ${RTIME}"
  echo "查看完整报告 | bash=/usr/bin/open param1=-t param2=${REPORT} terminal=false"
else
  echo "尚未跑过完整体检"
fi
echo "立即深度体检(约40s) | bash=${HOME}/CheckClaude/deep-check.sh terminal=false refresh=true"
echo "刷新 | refresh=true"
