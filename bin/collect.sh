#!/bin/bash
# top DEX pools per network via GeckoTerminal (free, no key) -> data/dex_cache.json
DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 -u - "$DIR" <<'EOF'
import datetime, json, os, sys, time, urllib.request, urllib.parse
root = sys.argv[1]
cfg = json.load(open(root + "/needs.json"))
API = cfg.get("gecko_api", "https://api.geckoterminal.com/api/v2")
NETS = cfg.get("gecko_networks", ["eth", "solana", "base", "bsc", "arbitrum"])
PAGES = int(cfg.get("gecko_pages", 3))

def get(path, tries=4):
    wait = 10
    for a in range(tries):
        try:
            req = urllib.request.Request(API + path, headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
            return json.load(urllib.request.urlopen(req, timeout=30))
        except Exception as e:
            if a == tries - 1:
                raise
            print(f"     retry {a + 1} in {wait}s ({str(e)[:60]})")
            time.sleep(wait)
            wait *= 2

def fnum(v):
    try:
        if v is None or v == "": return None
        return float(v)
    except (TypeError, ValueError): return None

def tokaddr(tid):
    if not tid: return ""
    s = str(tid)
    return s.split("_", 1)[1] if "_" in s else s

def slim(net, p):
    a = p.get("attributes", {})
    rel = p.get("relationships", {})
    addr = a.get("address", "")
    vol = fnum((a.get("volume_usd") or {}).get("h24"))
    tx = ((a.get("transactions") or {}).get("h24")) or {}
    try: liq = round(float(a.get("reserve_in_usd") or 0))
    except: liq = 0
    tv = vol / liq if vol and liq else None
    return {"pool": f"{net}:{addr}", "symbol": a.get("name"), "dex": (rel.get("dex") or {}).get("data", {}).get("id", ""),
            "chain": net, "tvl": liq, "vol": vol, "turn": tv,
            "buys": fnum(tx.get("buys")), "sells": fnum(tx.get("sells")),
            "chg": fnum((a.get("price_change_percentage") or {}).get("h24")),
            "created": a.get("pool_created_at"), "price": fnum(a.get("base_token_price_usd")),
            "baseAddr": tokaddr((rel.get("base_token") or {}).get("data", {}).get("id", "")),
            "quoteAddr": tokaddr((rel.get("quote_token") or {}).get("data", {}).get("id", "")),
            "src": "geckoterminal",
            "url": f"https://www.geckoterminal.com/{net}/pools/{addr}"}

def rslim(p):
    ma, mb = p.get("mintA") or {}, p.get("mintB") or {}
    day = p.get("day") or {}
    tvl = fnum(p.get("tvl")) or 0
    vol = fnum(day.get("volume"))
    pid = p.get("id", "")
    try: created = datetime.datetime.fromtimestamp(int(p.get("openTime") or 0), tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception: created = None
    return {"pool": f"raydium:{pid}", "symbol": f"{ma.get('symbol')} / {mb.get('symbol')}",
            "dex": "raydium", "chain": "solana",
            "tvl": round(tvl), "vol": vol, "turn": (vol / tvl if vol and tvl else None),
            "buys": None, "sells": None, "chg": None, "created": created, "price": fnum(p.get("price")),
            "src": "raydium", "apr": fnum(day.get("apr")), "fee": fnum(p.get("feeRate")),
            "baseAddr": ma.get("address", ""), "quoteAddr": mb.get("address", ""),
            "url": "https://raydium.io/liquidity-pools/"}

out = []
for pg in (1, 2):
    try:
        req = urllib.request.Request(
            f"https://api-v3.raydium.io/pools/info/list?poolType=all&poolSortField=default&sortType=desc&pageSize=100&page={pg}",
            headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
        rows = json.load(urllib.request.urlopen(req, timeout=30))["data"]["data"]
        out.extend(rslim(p) for p in rows)
        print(f"OK   raydium      page {pg}: {len(rows)} pools")
    except Exception as e:
        print(f"ERR  raydium      page {pg}: {str(e)[:100]}")
    time.sleep(5)
for net in NETS:
    for pg in range(1, PAGES + 1):
        try:
            d = get(f"/networks/{urllib.parse.quote(net)}/pools?page={pg}")
            rows = d.get("data") or []
            out.extend(slim(net, p) for p in rows)
            print(f"OK   {net:12} page {pg}: {len(rows)} pools")
            if len(rows) < 20:
                break
        except Exception as e:
            print(f"ERR  {net:12} page {pg}: {str(e)[:100]}")
        time.sleep(5)
cp = root + "/" + cfg.get("pools_cache_path", "data/dex_cache.json")
merged = {}
try:
    for p in json.load(open(cp)).get("pools", []):
        merged[p.get("pool")] = p
except Exception:
    pass
for p in out:
    merged[p.get("pool")] = p
out = list(merged.values())
tmp = cp + ".tmp"
json.dump({"fetched_at": int(time.time()), "count": len(out), "pools": out}, open(tmp, "w"))
os.replace(tmp, cp)
print(f"cached {len(out)} pools -> {cp}")
EOF
