#!/bin/bash
# SwiftBar 插件: 网速 + 出口 IP (30s 刷新, 纯 bash 零依赖)
# 菜单栏: ↓41K ↑92K · 出口IP   点开看明细
CACHE="$HOME/Library/Application Support/claude-mac-swiftbar"
mkdir -p "$CACHE"
IP_CACHE="$CACHE/ip.cache"
HIST="$CACHE/net-history.tsv"

fmt(){ awk -v b="$1" 'BEGIN{ if(b>=1073741824) printf "%.1fG", b/1073741824; else if(b>=1048576) printf "%.1fM", b/1048576; else if(b>=1024) printf "%.0fK", b/1024; else printf "%.0fB", b }'; }

# ── 网速采样: 全部物理网卡 1 秒差分 (每网卡取一行, 避免双栈重复计数) ──
sample(){ netstat -ib 2>/dev/null | awk '$1 ~ /^en/ && !seen[$1]++ {rx+=$7; tx+=$10} END{print rx+0, tx+0}'; }
read RX1 TX1 <<<"$(sample)"
sleep 1
read RX2 TX2 <<<"$(sample)"
DOWN=$(( RX2 > RX1 ? RX2-RX1 : 0 )); UP=$(( TX2 > TX1 ? TX2-TX1 : 0 ))

# ── 24h 历史记录 (每轮追加一条, 保留 24h) ──
NOW=$(date +%s)
printf '%s\t%s\t%s\n' "$NOW" "$DOWN" "$UP" >> "$HIST"
if [ -f "$HIST" ]; then
  awk -v cut=$(( NOW - 86400 )) -F'\t' '$1 >= cut' "$HIST" > "$HIST.t" && mv "$HIST.t" "$HIST"
fi
# 走势图: 24 格 = 24 小时, 每格取该小时样本均值, 高度相对 24h 峰值
sparkline(){ awk -F'\t' -v col="$1" -v end_h=$(( NOW / 3600 )) '
  BEGIN{ ch[1]="▁"; ch[2]="▂"; ch[3]="▃"; ch[4]="▄"; ch[5]="▅"; ch[6]="▆"; ch[7]="▇"; ch[8]="█" }
  { h=int($1/3600); s[h]+=$col; c[h]++ }
  END{
    n=8; max=0
    for(i=0;i<24;i++){ k=end_h-23+i; if(c[k]>0){ a[k]=s[k]/c[k]; if(a[k]>max) max=a[k] } }
    if(max<=0){ print "(累积中)"; exit }
    line=""
    for(i=0;i<24;i++){ k=end_h-23+i
      if(c[k]==0){ line=line"·" } else {
        idx=int(a[k]/max*(n-1))+1; if(idx<1)idx=1; if(idx>n)idx=n; line=line ch[idx]
      }
    }
    print line
  }' "$HIST"
}
PEAK_DN=$(awk -F'\t' '{if($2>m)m=$2}END{printf "%.0f",m}' "$HIST" 2>/dev/null)
PEAK_UP=$(awk -F'\t' '{if($3>m)m=$3}END{printf "%.0f",m}' "$HIST" 2>/dev/null)

# ── 出口 IP (缓存 10 分钟, 双源兜底) ──
if [ -f "$IP_CACHE" ] && [ $(( $(date +%s) - $(stat -f %m "$IP_CACHE" 2>/dev/null || echo 0) )) -lt 600 ]; then
  IP=$(head -1 "$IP_CACHE" 2>/dev/null); GEO=$(sed -n 2p "$IP_CACHE" 2>/dev/null)
else
  IP=$(curl -LfsS --connect-timeout 3 --max-time 5 https://icanhazip.com 2>/dev/null | tr -d '[:space:]')
  [ -z "$IP" ] && IP=$(curl -LfsS --connect-timeout 3 --max-time 5 https://api.ip.sb/ip 2>/dev/null | tr -d '[:space:]')
  if [ -n "$IP" ]; then
    GEO=$(curl -sS --max-time 5 "http://ip-api.com/line/${IP}?fields=country,city,isp" 2>/dev/null | paste -sd ' · ' -)
    printf '%s\n%s\n' "$IP" "$GEO" > "$IP_CACHE"
  fi
fi

# ── 输出 ──
echo "↓$(fmt $DOWN) ↑$(fmt $UP) · ${IP:-…}"
echo "---"
echo "实时速率: ↓$(fmt $DOWN)/s ↑$(fmt $UP)/s"
echo "出口 IP: ${IP:-探测中} ${GEO:+($GEO)}"
echo "---"
echo "最近24小时趋势 (24格·每小时均值·相对峰值):"
echo "↓ $(sparkline 2)  峰值 $(fmt ${PEAK_DN:-0})/s"
echo "↑ $(sparkline 3)  峰值 $(fmt ${PEAK_UP:-0})/s"
echo "---"
echo "网卡累计流量 (物理网卡):"
netstat -ib 2>/dev/null | awk '$1 ~ /^en/ && !seen[$1]++ && $7 > 1048576 {printf "-- %s  收 %.1fGB  发 %.1fGB\n", $1, $7/1073741824, $10/1073741824}' | head -4
echo "---"
echo "刷新 | refresh=true"
