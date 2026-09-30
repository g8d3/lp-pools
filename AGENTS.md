# e084 — LP Pools (one table, 100% DEX data)

Single page. Top DEX pools per network cached for browsing; every text search hits the GeckoTerminal API live. One API total (GeckoTerminal, free, no key). Each row's Deposit button runs a 3-step flow (amount → save order → open pool page).

## Product

| Surface | User action |
|---|---|
| Table `/` | Per-column filter + sort on Pool, DEX (multi), Chain (multi), Liquidity, Vol 24h, Turnover, Δ 24h, Txns, Age (all ranges); full pagination; CSV export; URL-hash state; Deposit per row opens the 3-step panel instantly; rows do nothing. |

Turnover = volume/liquidity per day — the LP earning signal (APY needs fee data the API doesn't give, so it's not shown).

## Architecture

```
server/app.py       stdlib only (threaded) + /api/*
  /api/health       alive + pool count + build
  /api/pool-meta    chains + top-40 dexes
  /api/all-pools    empty q -> cache browse; q -> LIVE GeckoTerminal search, then same filters/sort/page
  /api/all-pools.csv same, top 5000
  /api/pool-refresh ?pool= -> single pool live (60s cache; Raydium rows show DEX-reported APR)
  /api/zap-quote    POST {amount, pool_id, turn, symbol, tierFee} -> tier from Raydium feeRate or parsed from name
  /api/zap-quote    POST {amount, pool_id, turn, symbol} -> tier parsed from name, daily-fee estimate
  /api/orders       save/list/mark-done deposit orders
public/index.html   single-file UI, zero deps
data/dex_cache.json top pools via bin/collect.sh (GeckoTerminal networks + Raydium first-party, merged by pool id)
bin/collect.sh      refresh cache with retries + merge + atomic write
bin/collect.sh      refresh cache with retries + merge (a bad run never wipes good data)
```

Row `src` is never blank: `raydium` = venue's own API, `geckoterminal` = aggregator fallback (Orca raw accounts + EVM venues have no reachable keyless first-party API — probes documented this turn).

## QA GATE (standing rule — no delivery without it)

1. `bash test/all.sh` must print GATE GREEN: JS syntax + API smoke + scripted-browser visual (rows, 10/10 columns, sort, deposit, quote) + ZERO `window.__errs`.
2. `bash bin/report.sh` must be read: js_errors, slow_render (>1.5s), empty searches, lookup/dex misses, user reports, stale builds.
3. Telemetry is automatic and versioned: every error, slow render, empty search, and lookup/dex miss posts to /api/events with the client build. No user action needed — reading bin/report.sh is what surfaces their pain.
