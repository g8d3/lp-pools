#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
B=http://127.0.0.1:$(python3 -c "import json;print(json.load(open('$DIR/needs.json'))['port'])")
echo "== $B"
curl -sf $B/api/health | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and d['pools']>100, d.get('pools');print('health OK',d['pools'],'pools',d.get('build'))"
curl -sf "$B/api/pool-meta" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and len(d['chains'])>=5 and len(d['dexes'])>=5;print('meta OK',len(d['chains']),'chains',len(d['dexes']),'dexes',d['srcs'])"
curl -sf "$B/api/all-pools?sort=tvl&size=5" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and len(d['rows'])==5 and not d['live'];print('browse OK',d['total'])"
curl -sf "$B/api/all-pools?q=HOOD&size=5" | tee /tmp/hood.json | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and d['live'] and d['total']>0;print('LIVE search OK',d['total'])"
curl -sf "$B/api/pool-meta" | python3 -c "import json,sys;d=json.load(sys.stdin);assert 'robinhood' in d['chains'], d['chains'];print('live-covered chains OK')"
curl -sf "$B/api/all-pools?chain=solana&chain=base&size=3" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and all(r['chain'] in ('solana','base') for r in d['rows']);print('multi filter OK',d['total'])"
curl -sf "$B/api/all-pools?minTurn=1&sort=turn&size=5" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and all((r['turn'] or 0)>=1 for r in d['rows']);print('turnover filter OK',d['total'])"
curl -sf "$B/api/all-pools.csv?chain=solana&size=5" -o /tmp/pools.csv && head -1 /tmp/pools.csv | grep -q turnover && echo "csv OK"
PID=$(curl -sf "$B/api/all-pools?size=1" | python3 -c "import json,sys;print(json.load(sys.stdin)['rows'][0]['pool'])")
curl -sf "$B/api/pool-refresh?pool=$PID" | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and d['tvl']>0;print('refresh OK',d['symbol'])"
curl -sf -X POST $B/api/zap-quote -H 'Content-Type: application/json' -d '{"amount":1000,"pool_id":"x","turn":2.5,"symbol":"A / B 0.3%"}' | python3 -c "import json,sys;d=json.load(sys.stdin);assert d['ok'] and d['yield_day_est']==7.5, d;print('quote OK',d['yield_day_est'],'/day')"
OID=$(curl -sf -X POST $B/api/orders -H 'Content-Type: application/json' -d '{"pool_id":"t1","symbol":"TST","chain":"eth","amount":100}' | python3 -c "import json,sys;print(json.load(sys.stdin)['id'])")
curl -sf $B/api/orders | grep -q "$OID" && echo "orders OK"
curl -sf -X POST $B/api/orders/done -H 'Content-Type: application/json' -d "{\"id\": \"$OID\"}" | grep -q '"ok": true' && echo "order done OK"
curl -sf $B/ | grep -q "v40" && echo "page OK"
