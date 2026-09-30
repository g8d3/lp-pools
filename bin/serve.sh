#!/bin/bash
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT=$(python3 -c "import json;print(json.load(open('$DIR/needs.json'))['port'])")
PID=$(ss -tlnp 2>/dev/null | grep ":$PORT " | grep -oP 'pid=\K[0-9]+' | head -n1)
case "${1:-start}" in
  stop) [ -n "$PID" ] && kill "$PID" && echo "stopped $PID" || echo "not running"; exit 0;;
  restart) "$0" stop; sleep 1; "$0" start; exit 0;;
esac
if [ -n "$PID" ]; then echo "already running pid=$PID"; else
  mkdir -p "$DIR/data"; nohup python3 "$DIR/server/app.py" > "$DIR/data/server.log" 2>&1 &
  echo "started pid=$!"; sleep 1
fi
LAN=$(hostname -I | awk '{print $1}')
TS=$(tailscale ip -4 2>/dev/null | head -n1)
echo "local:   http://127.0.0.1:$PORT"
echo "lan:     http://$LAN:$PORT"
[ -n "$TS" ] && echo "tailnet: http://$TS:$PORT"
PUB_URL="http://$TS:$PORT"; [ -z "$TS" ] && PUB_URL="http://$LAN:$PORT"
python3 -c "
import json
p='$DIR/needs.json'
d=json.load(open(p)); d['public_url']='$PUB_URL'; json.dump(d,open(p,'w'),indent=1)"
echo "public_url: $PUB_URL (needs.json)"
