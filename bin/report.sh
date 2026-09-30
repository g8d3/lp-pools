#!/bin/bash
# pain digest from telemetry: what users hit, without them telling us. Run before every delivery.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$DIR/data/events.jsonl" <<'EOF'
import json, sys, collections
evs = []
try:
    for line in open(sys.argv[1]):
        line = line.strip()
        if line:
            try: evs.append(json.loads(line))
            except: pass
except FileNotFoundError:
    print("no telemetry yet"); sys.exit()
print(f"== {len(evs)} events ==")
by = collections.Counter(e.get("event") for e in evs)
for k, v in by.most_common():
    print(f"  {v:5}  {k}")
def show(title, filt, fmt, last=10):
    rows = [e for e in evs if filt(e)]
    if not rows: return
    print(f"== {title} ({len(rows)}) ==")
    for e in rows[-last:]:
        print("  " + fmt(e))
show("JS ERRORS", lambda e: e.get("event") == "js_error",
     lambda e: f"[{e.get('build', '?')}] {e.get('session','?')[:6]} {(e.get('detail') or {}).get('msg', '')}")
show("SLOW RENDERS", lambda e: e.get("event") == "slow_render",
     lambda e: f"{(e.get('detail') or {}).get('ms')}ms total={(e.get('detail') or {}).get('total')}")
show("EMPTY SEARCHES", lambda e: e.get("event") == "empty",
     lambda e: f"q={(e.get('detail') or {}).get('q', '')!r}")
show("LOOKUP MISS/FAIL", lambda e: e.get("event") in ("lookup_empty", "dex_miss", "dex_fail"),
     lambda e: f"{e.get('event')} {(e.get('detail') or {}).get('id') or (e.get('detail') or {}).get('q', '')}")
show("USER REPORTS", lambda e: e.get("event") == "report",
     lambda e: f"{e.get('session','?')[:6]} {(e.get('detail') or {}).get('count','')} {(e.get('detail') or {}).get('url','')[-60:]}")
builds = collections.Counter(e.get("build", "?") for e in evs)
print("builds seen:", dict(builds))
EOF
