import collections, csv, datetime, io, json, os, re, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUB = os.path.join(ROOT, "public")
DATA = os.path.join(ROOT, "data")
NEEDS = os.path.join(ROOT, "needs.json")

def cfg():
    try: return json.load(open(NEEDS))
    except Exception: return {"port": 8484, "bind": "0.0.0.0", "our_zap_fee_pct": 0.0}

def cache():
    c = cfg()
    p = os.path.join(ROOT, c.get("pools_cache_path", "data/dex_cache.json"))
    try: return json.load(open(p))
    except Exception: return {}

def gecko(path, timeout=20):
    c = cfg()
    base = c.get("gecko_api", "https://api.geckoterminal.com/api/v2")
    req = urllib.request.Request(base + path, headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))

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
    return {"pool": f"{net}:{addr}", "symbol": a.get("name"),
            "dex": (rel.get("dex") or {}).get("data", {}).get("id", ""), "chain": net,
            "tvl": liq, "vol": vol, "turn": tv,
            "buys": fnum(tx.get("buys")), "sells": fnum(tx.get("sells")),
            "chg": fnum((a.get("price_change_percentage") or {}).get("h24")),
            "created": a.get("pool_created_at"), "price": fnum(a.get("base_token_price_usd")),
            "baseAddr": tokaddr((rel.get("base_token") or {}).get("data", {}).get("id", "")),
            "quoteAddr": tokaddr((rel.get("quote_token") or {}).get("data", {}).get("id", "")),
            "url": f"https://www.geckoterminal.com/{net}/pools/{addr}", "src": "geckoterminal"}

_LIVE = {}   # q -> (ts, rows), TTL 120s
_ONE = {}    # pool -> (ts, row), TTL 60s

def live_search(q):
    now = time.time()
    hit = _LIVE.get(q.lower())
    if hit and now - hit[0] < 120: return hit[1]
    try:
        d = gecko("/search/pools?query=" + urllib.parse.quote(q) + "&include=network,dex&page=1")
    except Exception:
        return hit[1] if hit else []
    nets = {i["id"]: (i.get("attributes") or {}).get("name", i["id"]) for i in d.get("included", []) if i.get("type") == "network"}
    rows = []
    for p in (d.get("data") or [])[:30]:
        a = p.get("attributes", {})
        pid = p.get("id", "")
        net = pid.split("_")[0].split(":")[0]
        s = slim(nets.get(net, net), p)
        s["pool"] = "live:" + pid
        rows.append(s)
    _LIVE[q.lower()] = (now, rows)
    return rows

def refresh_one(pool):
    now = time.time()
    hit = _ONE.get(pool)
    if hit and now - hit[0] < 60: return hit[1]
    try:
        net, addr = pool.split(":", 1)
        if net == "live": return hit[1] if hit else None
        d = gecko(f"/networks/{urllib.parse.quote(net)}/pools/{urllib.parse.quote(addr)}?include=base_token,quote_token")
        row = slim(net, d.get("data", {}))
        toks = {i["id"]: (i.get("attributes") or {}).get("symbol", "")
                for i in d.get("included", []) if i.get("type") == "token"}
        rel = (d.get("data", {}).get("relationships") or {})
        row["baseSym"] = toks.get(((rel.get("base_token") or {}).get("data") or {}).get("id", ""), "")
        row["quoteSym"] = toks.get(((rel.get("quote_token") or {}).get("data") or {}).get("id", ""), "")
        _ONE[pool] = (now, row)
        return row
    except Exception:
        return hit[1] if hit else None

MIME = {".html": "text/html; charset=utf-8", ".js": "text/javascript", ".json": "application/json",
        ".css": "text/css", ".csv": "text/csv"}

SORTS = {
    "tvl": lambda p: p.get("tvl") or 0,
    "vol": lambda p: (p.get("vol") if p.get("vol") is not None else -1),
    "turn": lambda p: (p.get("turn") if p.get("turn") is not None else -1),
    "chg": lambda p: (p.get("chg") if p.get("chg") is not None else -1e18),
    "txns": lambda p: ((p.get("buys") or 0) + (p.get("sells") or 0)),
    "symbol": lambda p: (p.get("symbol") or "").lower(),
    "dex": lambda p: (p.get("dex") or "").lower(),
    "chain": lambda p: (p.get("chain") or "").lower(),
    "created": lambda p: p.get("created") or "",
    "src": lambda p: (p.get("src") or "").lower(),
}

def num(v, default=None):
    try:
        if v is None or v == "": return default
        return float(v)
    except (TypeError, ValueError): return default

def filtered(qs):
    ch = cache()
    q = (qs.get("q", [""])[0] or "").strip()
    if q:
        pools, fetched, live = live_search(q), int(time.time()), True
    else:
        pools, fetched, live = ch.get("pools", []), ch.get("fetched_at", 0), False
    if not pools and not q: raise LookupError("empty cache; run bin/collect.sh")
    fdx = [x for x in qs.get("dex", []) if x]
    fch = [x for x in qs.get("chain", []) if x]
    fsrc = [x for x in qs.get("src", []) if x]
    minLiq = num(qs.get("minLiq", [""])[0]); maxLiq = num(qs.get("maxLiq", [""])[0])
    minVol = num(qs.get("minVol", [""])[0]); maxVol = num(qs.get("maxVol", [""])[0])
    minTurn = num(qs.get("minTurn", [""])[0]); maxTurn = num(qs.get("maxTurn", [""])[0])
    minTx = num(qs.get("minTx", [""])[0]); maxTx = num(qs.get("maxTx", [""])[0])
    minAge = num(qs.get("minAge", [""])[0]); maxAge = num(qs.get("maxAge", [""])[0])
    r = pools
    if fdx: r = [p for p in r if p.get("dex") in fdx]
    if fch: r = [p for p in r if p.get("chain") in fch]
    if fsrc: r = [p for p in r if p.get("src") in fsrc]
    now = time.time()
    for p in r:
        try:
            dt = datetime.datetime.strptime((p.get("created") or "")[:19], "%Y-%m-%dT%H:%M:%S")
            p["ageDays"] = round((now - dt.replace(tzinfo=datetime.timezone.utc).timestamp()) / 86400, 1)
        except Exception:
            p["ageDays"] = None
    if minLiq is not None: r = [p for p in r if (p.get("tvl") or 0) >= minLiq]
    if maxLiq is not None: r = [p for p in r if (p.get("tvl") or 0) <= maxLiq]
    if minVol is not None: r = [p for p in r if (p.get("vol") or 0) >= minVol]
    if maxVol is not None: r = [p for p in r if (p.get("vol") or 0) <= maxVol]
    if minTurn is not None: r = [p for p in r if (p.get("turn") or 0) >= minTurn]
    if maxTurn is not None: r = [p for p in r if (p.get("turn") or 0) <= maxTurn]
    if minTx is not None: r = [p for p in r if ((p.get("buys") or 0) + (p.get("sells") or 0)) >= minTx]
    if maxTx is not None: r = [p for p in r if ((p.get("buys") or 0) + (p.get("sells") or 0)) <= maxTx]
    if minAge is not None: r = [p for p in r if p.get("ageDays") is not None and p["ageDays"] >= minAge]
    if maxAge is not None: r = [p for p in r if p.get("ageDays") is not None and p["ageDays"] <= maxAge]
    return r, fetched, live

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send_json(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def body(self):
        try: n = int(self.headers.get("Content-Length") or 0)
        except: n = 0
        raw = self.rfile.read(n) if n else b"{}"
        try: return json.loads(raw.decode() or "{}")
        except: return {}
    def do_GET(self):
        c = cfg()
        u = urllib.parse.urlparse(self.path)
        path, qs = u.path, urllib.parse.parse_qs(u.query)
        if path == "/api/health":
            ch = cache()
            return self.send_json({"ok": True, "site": c.get("site_name", "LP Pools"),
                "pools": len(ch.get("pools", [])), "fetched_at": ch.get("fetched_at", 0),
                "our_zap_fee_pct": c.get("our_zap_fee_pct", 0.0), "build": c.get("build", ""),
                "public_url": c.get("public_url", ""), "ts": int(time.time())})
        if path == "/api/config":
            return self.send_json({"site_name": c.get("site_name", "LP Pools"),
                "our_zap_fee_pct": c.get("our_zap_fee_pct", 0.0), "build": c.get("build", ""),
                "public_url": c.get("public_url", "")})
        if path == "/api/pool-meta":
            ch = cache()
            pools = ch.get("pools", [])
            dexes = collections.Counter([p.get("dex", "?") for p in pools] +
                [p.get("dex", "?") for _ts, rows in _LIVE.values() for p in rows]).most_common(40)
            chains = sorted(set([p.get("chain", "?") for p in pools] +
                [p.get("chain", "?") for _ts, rows in _LIVE.values() for p in rows]))
            return self.send_json({"ok": True, "total": len(pools), "fetched_at": ch.get("fetched_at", 0),
                "chains": chains, "dexes": [n for n, _ in dexes], "projects": [],
                "srcs": sorted(set([p.get("src", "?") for p in pools] + [p.get("src", "?") for _ts, rows in _LIVE.values() for p in rows]))})
        if path == "/api/all-pools":
            try: r, fetched, live = filtered(qs)
            except LookupError as e:
                return self.send_json({"ok": False, "err": str(e)})
            sort = qs.get("sort", ["tvl"])[0]; order = qs.get("order", ["desc"])[0]
            page = max(0, int(num(qs.get("page", ["0"])[0], 0)))
            size = min(100, max(1, int(num(qs.get("size", ["25"])[0], 25))))
            r = sorted(r, key=SORTS.get(sort, SORTS["tvl"]), reverse=(order == "desc"))
            pages = max(1, (len(r) + size - 1) // size); page = min(page, pages - 1)
            lo = page * size if r else 0
            return self.send_json({"ok": True, "total": len(r), "page": page, "pages": pages,
                "size": size, "lo": lo + 1 if r else 0, "hi": min(lo + size, len(r)),
                "fetched_at": fetched, "live": live, "rows": r[lo:lo + size]})
        if path == "/api/all-pools.csv":
            try: r, _, _ = filtered(qs)
            except LookupError as e:
                return self.send_json({"ok": False, "err": str(e)})
            sort = qs.get("sort", ["tvl"])[0]; order = qs.get("order", ["desc"])[0]
            r = sorted(r, key=SORTS.get(sort, SORTS["tvl"]), reverse=(order == "desc"))[:5000]
            buf = io.StringIO()
            w = csv.writer(buf)
            w.writerow(["pool", "symbol", "dex", "src", "chain", "liquidity_usd", "vol24_usd", "turnover",
                        "chg24", "buys24", "sells24", "created", "price_usd", "url"])
            for p in r:
                w.writerow([p.get("pool"), p.get("symbol"), p.get("dex"), p.get("src"), p.get("chain"), p.get("tvl"),
                            p.get("vol"), p.get("turn"), p.get("chg"), p.get("buys"), p.get("sells"),
                            p.get("created"), p.get("price"), p.get("url")])
            b = buf.getvalue().encode()
            self.send_response(200); self.send_header("Content-Type", "text/csv")
            self.send_header("Content-Disposition", "attachment; filename=lp-pools.csv")
            self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
            return
        if path == "/api/pool-refresh":
            pool = qs.get("pool", [""])[0]
            row = refresh_one(pool) if pool else None
            if not row: return self.send_json({"ok": False, "err": "no live data"})
            row["ok"] = True
            return self.send_json(row)
        if path == "/api/orders":
            rows = []
            p = os.path.join(DATA, "orders.jsonl")
            if os.path.exists(p):
                for line in open(p):
                    line = line.strip()
                    if line:
                        try: rows.append(json.loads(line))
                        except: pass
            return self.send_json(rows[-50:])
        # static
        rel = path[1:] if len(path) > 1 else "index.html"
        fp = os.path.join(PUB, rel)
        if os.path.isdir(fp): fp = os.path.join(fp, "index.html")
        if not os.path.abspath(fp).startswith(PUB) or not os.path.exists(fp):
            fp = os.path.join(PUB, "index.html")
        ext = os.path.splitext(fp)[1].lower()
        try:
            b = open(fp, "rb").read()
            mt = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime(os.path.getmtime(fp)))
            self.send_response(200); self.send_header("Content-Type", MIME.get(ext, "application/octet-stream"))
            self.send_header("Content-Length", str(len(b))); self.send_header("Cache-Control", "no-store, must-revalidate")
            self.send_header("Last-Modified", mt); self.end_headers(); self.wfile.write(b)
        except Exception as e:
            self.send_response(500); self.end_headers(); self.wfile.write(str(e).encode())
    def do_POST(self):
        c = cfg()
        u = urllib.parse.urlparse(self.path)
        path = u.path
        if path == "/api/events":
            d = self.body()
            try:
                with open(os.path.join(DATA, "events.jsonl"), "a") as f:
                    d["ts"] = int(time.time()); f.write(json.dumps(d) + "\n")
            except Exception: pass
            return self.send_json({"ok": True})
        if path == "/api/zap-quote":
            d = self.body()
            try: amount = float(d.get("amount", 0) or 0)
            except: amount = 0
            try: turn = float(d.get("turn") or 0)
            except: turn = 0
            tier = num(d.get("tierFee"))
            if tier is None:
                m = re.search(r"(\d+(?:\.\d+)?)\s*%", d.get("symbol") or "")
                if m: tier = float(m.group(1)) / 100.0
            swap_cost = amount * 0.5 * 0.003 if amount > 0 else 0
            est_day = amount * turn * tier if tier and turn else None
            net = amount - swap_cost + (est_day or 0)
            return self.send_json({"ok": True, "pool_id": d.get("pool_id", ""), "amount": amount,
                "swap_cost_est": round(swap_cost, 2),
                "yield_day_est": round(est_day, 2) if est_day is not None else None,
                "tier_pct": round(tier * 100, 3) if tier else None,
                "fee_est": 0, "net_est": round(net, 2),
                "note": "Estimate only: 50/50 split, 0.3% swap cost, daily fees = amount x turnover x fee tier. Not on-chain execution."})
        if path == "/api/orders":
            d = self.body()
            d["ts"] = int(time.time()); d["id"] = str(int(time.time() * 1000)); d["status"] = "open"
            try:
                with open(os.path.join(DATA, "orders.jsonl"), "a") as f: f.write(json.dumps(d) + "\n")
            except Exception as e:
                return self.send_json({"ok": False, "err": str(e)}, 500)
            return self.send_json({"ok": True, "id": d["id"]})
        if path == "/api/orders/done":
            oid = self.body().get("id", "")
            p = os.path.join(DATA, "orders.jsonl")
            if os.path.exists(p):
                rows = []
                for line in open(p):
                    line = line.strip()
                    if line:
                        try:
                            o = json.loads(line)
                            if o.get("id") == oid: o["status"] = "done"
                            rows.append(o)
                        except: pass
                open(p, "w").write("".join(json.dumps(o) + "\n" for o in rows))
            return self.send_json({"ok": True})
        return self.send_json({"ok": False, "err": "unknown route"}, 404)

if __name__ == "__main__":
    c = cfg()
    srv = ThreadingHTTPServer((c.get("bind", "0.0.0.0"), int(c.get("port", 8484))), H)
    print(f"serving {PUB} on {c.get('bind')}:{c.get('port')}", flush=True)
    srv.serve_forever()
