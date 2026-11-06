#!/bin/bash
# Установка мониторинга VPN-сервера (идемпотентно, можно запускать повторно).
# Первый запуск:  curl -fsSL https://raw.githubusercontent.com/passha228/vps-watch/main/server/install.sh | TOKEN=123:ABC CHAT=123456 bash
# Обновление:     curl -fsSL https://raw.githubusercontent.com/passha228/vps-watch/main/server/install.sh | bash
# CHAT может содержать несколько id через пробел: CHAT="111 -100222"
set -e
[[ $EUID -eq 0 ]] || { echo "Запускай от root"; exit 1; }

CONF=/etc/vpswatch.conf
if [[ -n $TOKEN && -n $CHAT ]]; then
  IP=${IP:-$(curl -s -4 ifconfig.me)}
  echo "TOKEN='$TOKEN'; CHAT='$CHAT'; IP='$IP'" > $CONF; chmod 600 $CONF
elif [[ ! -f $CONF ]]; then
  echo "Нет $CONF — передай TOKEN и CHAT: ... | TOKEN=... CHAT=... bash"; exit 1
fi

apt-get install -y -qq jq sysstat >/dev/null
sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
systemctl enable --now sysstat >/dev/null 2>&1 || true

# Amnezia по умолчанию запрещает ping — без этого не работают внешние ping-мониторы
iptables -D INPUT -p icmp -m icmp --icmp-type 8 -j DROP 2>/dev/null || true

cat > /usr/local/lib/vpswatch.sh <<'EOF'
source /etc/vpswatch.conf
api(){ curl -s -m 60 "https://api.telegram.org/bot$TOKEN/$1" "${@:2}"; }
send(){ for c in ${TO:-$CHAT}; do api sendMessage -d chat_id="$c" --data-urlencode text="$1" >/dev/null; done; }
stats(){
  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat; sleep "${1:-5}"
  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
  local t=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
  steal=$(( 100*(st2-st1)/t )); iowait=$(( 100*(w2-w1)/t ))
  mem=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  docker ps --format '{{.Names}}' | grep -q amnezia; vpn_down=$?
}
report(){ stats 1
  printf '🖥 Сервер %s\n⏱ Аптайм: %s\n⚙️ CPU: нагрузка %s, steal %s%%, iowait %s%%\n🧠 Свободно памяти: %s МБ\n🔐 VPN: %s\n' \
    "$IP" "$(uptime -p | sed 's/^up //')" "$(cut -d' ' -f1 /proc/loadavg)" "$steal" "$iowait" "$mem" \
    "$( ((vpn_down)) && echo '❌ не работает' || echo '✅ работает')"
}
EOF

cat > /usr/local/bin/vps-watch.sh <<'EOF'
#!/bin/bash
source /usr/local/lib/vpswatch.sh
alert(){ local f=/run/vpswatch.$1
  if (( $2 )); then [[ -e $f ]] || { send "⚠️ $3"; touch "$f"; }
  elif [[ -e $f ]]; then send "✅ $4"; rm "$f"; fi; }
stats
alert steal  $((steal>20))  "Хостер отжимает CPU: steal ${steal}% — VPN может тормозить" "CPU снова в норме"
alert iowait $((iowait>30)) "Тормозит диск: iowait ${iowait}%" "Диск снова в норме"
alert mem    $((mem<50))    "Кончается память: свободно ${mem} МБ" "Память снова в норме"
alert vpn    $vpn_down      "VPN лёг: контейнер Amnezia не запущен" "VPN снова работает"
EOF

cat > /usr/local/bin/vps-bot.sh <<'EOF'
#!/bin/bash
source /usr/local/lib/vpswatch.sh
off=0
while :; do
  upd=$(api getUpdates -d offset=$off -d timeout=50) || { sleep 5; continue; }
  while read -r id chat text; do
    off=$((id+1))
    [[ " $CHAT " == *" $chat "* && $text == /server_info* ]] || continue
    TO=$chat send "$(report)"
  done < <(jq -r '.result[]? | "\(.update_id) \(.message.chat.id // 0) \(.message.text // "")"' <<<"$upd")
done
EOF

printf '#!/bin/bash\nsource /usr/local/lib/vpswatch.sh\nreport\n' > /usr/local/bin/vps-status
chmod +x /usr/local/bin/vps-watch.sh /usr/local/bin/vps-bot.sh /usr/local/bin/vps-status

cat > /etc/systemd/system/vps-bot.service <<'EOF'
[Unit]
After=network-online.target docker.service
[Service]
ExecStart=/usr/local/bin/vps-bot.sh
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF
echo '* * * * * root /usr/local/bin/vps-watch.sh' > /etc/cron.d/vps-watch

systemctl daemon-reload
systemctl enable vps-bot >/dev/null 2>&1
systemctl restart vps-bot

source /usr/local/lib/vpswatch.sh
send "✅ Мониторинг установлен на $IP"
vps-status
