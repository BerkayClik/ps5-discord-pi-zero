#!/bin/sh
# discord-hosts.txt listesinden dnsmasq ve nginx ayar dosyalarını üretir.
#
#   ./make-config.sh                          # varsayılan adreslerle
#   PI_IP=192.168.0.50 MODEM_IP=192.168.0.1 ./make-config.sh
#
# Çıktı: out/dnsmasq-ps5gw.conf ve out/nginx.conf
set -eu

PI_IP="${PI_IP:-192.168.1.250}"       # Pi'nin sabit adresi
MODEM_IP="${MODEM_IP:-192.168.1.1}"   # Discord dışındaki sorguların gideceği DNS
IFACE="${IFACE:-wlan0}"               # Pi'nin ağ arayüzü
PORTS="${PORTS:-443 2053 2083 2087 2096 8443}"

DIR=$(cd "$(dirname "$0")" && pwd)
HOSTS="${HOSTS:-$DIR/discord-hosts.txt}"
OUT="${OUT:-$DIR/out}"
mkdir -p "$OUT"

# ---------------------------------------------------------------- dnsmasq
{
  echo "# PS5 Discord gateway: Discord names point at this Pi, everything else goes to the modem DNS as before."
  echo "interface=$IFACE"
  echo "bind-dynamic"
  echo "no-resolv"
  echo "server=$MODEM_IP"
  echo "cache-size=2000"
  while read -r d; do
    [ -n "$d" ] && echo "address=/$d/$PI_IP"
  done < "$HOSTS"
  echo "# Other record types (AAAA, HTTPS) for these names are answered empty instead of going to the ISP."
  while read -r d; do
    [ -n "$d" ] && echo "local=/$d/"
  done < "$HOSTS"
} > "$OUT/dnsmasq-ps5gw.conf"

# ---------------------------------------------------------------- nginx
{
  cat <<'EOF'
# PS5 Discord gateway: SNI proxy for Discord domains only.
user www-data;
worker_processes 1;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log warn;
include /etc/nginx/modules-enabled/*.conf;

events { worker_connections 512; }

stream {
    # Real addresses come from 1.1.1.1, never from the local dnsmasq.
    resolver 1.1.1.1 1.0.0.1 valid=300s ipv6=off;
    resolver_timeout 5s;
    log_format ps5gw "$time_local $remote_addr $ssl_preread_server_name:$server_port -> $upstream_addr status=$status out=$bytes_sent in=$bytes_received t=$session_time";

    map $ssl_preread_server_name $ps5gw_target {
        hostnames;
        default 127.0.0.1:9;
EOF
  while read -r d; do
    [ -n "$d" ] && echo "        .$d \$ssl_preread_server_name:\$server_port;"
  done < "$HOSTS"
  echo "    }"
  echo
  echo "    server {"
  for p in $PORTS; do
    echo "        listen $p;"
  done
  cat <<'EOF'
        access_log /var/log/nginx/stream.log ps5gw;
        ssl_preread on;
        preread_timeout 10s;
        proxy_connect_timeout 10s;
        proxy_timeout 30m;
        proxy_pass $ps5gw_target;
    }
}

http {
    access_log off;
    server_tokens off;
    server {
        listen 80 default_server;
        return 301 https://$host$request_uri;
    }
}
EOF
} > "$OUT/nginx.conf"

echo "Yazıldı: $OUT/dnsmasq-ps5gw.conf"
echo "Yazıldı: $OUT/nginx.conf"
