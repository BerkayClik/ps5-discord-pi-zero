#!/bin/sh
# Bir nfqws yöntemini geçici olarak açıp Discord'a erişimi dener, sonra her şeyi geri alır.
# Pi'nin kendi çıkan bağlantılarını test eder; kalıcı hiçbir şey değiştirmez.
#
#   sudo sh try-strategy.sh ""                                             # yöntemsiz, engeli görmek için
#   sudo sh try-strategy.sh "--dpi-desync=fake --dpi-desync-fooling=md5sig"
#   sudo sh try-strategy.sh "--dpi-desync=multisplit --dpi-desync-split-pos=1,midsld"
PATH=$PATH:/usr/sbin
NFQ="${NFQ:-/opt/zapret/binaries/linux-arm64/nfqws}"
IFACE="${IFACE:-wlan0}"

modprobe nfnetlink_queue 2>/dev/null
nft delete table ip zt 2>/dev/null
pid=""
if [ -n "$1" ]; then
nft -f - <<NFT || exit 1
table ip zt {
  chain post {
    type filter hook postrouting priority mangle; policy accept;
    oifname "$IFACE" meta mark & 0x40000000 == 0 tcp dport 443 @ih,0,8 0x16 queue num 200 bypass
  }
}
NFT
# shellcheck disable=SC2086
$NFQ --qnum=200 $1 >/tmp/nfqws-try.log 2>&1 &
pid=$!
sleep 0.7
fi

for h in discord.com gateway.discord.gg; do
  r=$(curl -sS -o /dev/null -m 6 -w "%{http_code} %{time_total}s" "https://$h/" 2>&1 | tail -1)
  echo "  $h -> $r"
done

[ -n "$pid" ] && kill "$pid"
nft delete table ip zt 2>/dev/null
exit 0
