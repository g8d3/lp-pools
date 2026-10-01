#!/bin/bash
# top pairs PER VENUE via DexScreener (free, no key) -> merged into data/dex_cache.json
DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 -u - "$DIR" <<'EOF'
import json, os, sys, time, urllib.request, urllib.parse, collections
root = sys.argv[1]
cfg = json.load(open(root + "/needs.json"))
API = "https://api.dexscreener.com"
PER = int(cfg.get("ds_per_dex", 12))
TOKENS = cfg.get("ds_tokens", ["So11111111111111111111111111111111111111112",
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"])
SEARCHES = cfg.get("ds_searches", ["HOOD", "wNEAR USDC", "NEAR USDC"])

def fnum(v):
    try:
        if v is None or v == "": return None
        return float(v)
    except (TypeError, ValueError): return None

def get(path):
    req = urllib.request.Request(API + path, headers={"User-Agent": "Mozilla/5.0"})
    return json.load(urllib.request.urlopen(req, timeout=20)).get("pairs") or []

def slim(p):
    liq = fnum((p.get("liquidity") or {}).get("usd")) or 0
    vol = fnum((p.get("volume") or {}).get("h24"))
    tx = (p.get("txns") or {}).get("h24") or {}
    try: created = __import__("datetime").datetime.fromtimestamp(int(p.get("pairCreatedAt") or 0) / 1000, tz=__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception: created = None
    bt, qt = p.get("baseToken") or {}, p.get("quoteToken") or {}
    return {"pool": f"ds:{p.get('chainId')}:{p.get('pairAddress')}",
            "symbol": f"{bt.get('symbol')} / {qt.get('symbol')}",
            "dex": p.get("dexId"), "chain": p.get("chainId"),
            "tvl": round(liq), "vol": vol, "turn": (vol / liq if vol and liq else None),
            "buys": fnum(tx.get("buys")), "sells": fnum(tx.get("sells")),
            "chg": fnum((p.get("priceChange") or {}).get("h24")),
            "created": created, "price": fnum(p.get("priceUsd")),
            "src": "dexscreener",
            "baseAddr": bt.get("address", ""), "quoteAddr": qt.get("address", ""),
            "baseSym": bt.get("symbol", ""), "quoteSym": qt.get("symbol", ""),
            "url": p.get("url", "")}

cands = []
for t in TOKENS:
    try:
        cands.extend(get(f"/latest/dex/tokens/{t}"))
        print(f"OK   token {t[:8]}: total pairs so far {len(cands)}")
    except Exception as e:
        print(f"ERR  token {t[:8]}: {str(e)[:70]}")
    time.sleep(3)
for q in SEARCHES:
    try:
        got = get(f"/latest/dex/search?q={urllib.parse.quote(q)}")
        cands.extend(got)
        print(f"OK   search {q!r}: {len(got)} pairs")
    except Exception as e:
        print(f"ERR  search {q!r}: {str(e)[:70]}")
    time.sleep(3)

best = {}
for p in cands:
    if not p.get("pairAddress") or not p.get("chainId"):
        continue
    key = (p.get("chainId"), p.get("dexId"))
    vol = fnum((p.get("volume") or {}).get("h24")) or 0
    lst = best.setdefault(key, [])
    lst.append((vol, p))
out = []
for key, lst in sorted(best.items()):
    lst.sort(key=lambda x: x[0], reverse=True)
    for _, p in lst[:PER]:
        out.append(slim(p))
print(collections.Counter((p["chain"], p["dex"]) for p in out).most_common(15))
cp = root + "/" + cfg.get("pools_cache_path", "data/dex_cache.json")
merged = {}
try:
    for p in json.load(open(cp)).get("pools", []):
        merged[p.get("pool")] = p
except Exception:
    pass
for p in out:
    merged[p.get("pool")] = p
merged = list(merged.values())
tmp = cp + ".tmp"
json.dump({"fetched_at": int(time.time()), "count": len(merged), "pools": merged}, open(tmp, "w"))
os.replace(tmp, cp)
print(f"merged {len(out)} dex rows -> {len(merged)} total")
EOF
