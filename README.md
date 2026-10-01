# LP Pools — every live DEX pool in one table

Single-page directory of live liquidity pools (2000+, 15 chains): cached top pools per network for browsing, every text search hits the DEX API live. One API total ([GeckoTerminal](https://www.geckoterminal.com), free, no key) plus [Raydium's own API](https://api-v3.raydium.io) as a first-party source. Each row's **Deposit** button runs a 3-step flow (amount → save order → open pool page).

## Run

```bash
bin/collect.sh     # refresh pool cache (GeckoTerminal top pools + Raydium), retries + merge
bin/serve.sh       # start server, prints local/LAN/tailnet URLs
test/all.sh        # QA gate: JS syntax + API smoke + scripted-browser visual + pain digest
```

Server is Python stdlib only (threaded). UI is one dependency-free HTML file. All machine values (ports, URLs) live in `needs.json`, never in code.

## API

- `GET /api/all-pools` — empty `q` browses cache; `q` live-searches the DEX API. Filters: `dex`/`chain`/`src` (repeatable), `min/max` ranges for liquidity, volume, turnover, Δ24h, txns, age. Sort + order + page + size.
- `GET /api/all-pools.csv` — same filters, top 5000 download.
- `GET /api/pool-refresh?pool=` — single pool live (60s cache).
- `GET /api/pool-meta` — chains + dexes + sources for filters.
- `POST /api/zap-quote` — cost/fee estimate (fee tier parsed from pool name or Raydium data).
- `GET/POST /api/orders`, `POST /api/orders/done` — saved deposit orders.

## Provenance (why believe any number)

- Every row carries `src`: `raydium` = the venue's own API, `geckoterminal` = aggregator fallback (Orca serves only raw accounts; EVM majors expose no keyless first-party API — probed, documented in gap reports).
- Deposit panel shows the pool contract + token contracts with copy buttons and chain-explorer links, the named API, and a direct pool-page link. Verify everything on-chain.
- Turnover (vol/liquidity per day) is the earning signal. Deliberately absent: APY (except DEX-reported on Raydium rows), IL flags, asset counts — the source can't provide them, so they're not shown.
- Quotes are labeled estimates. Nothing moves on this site; money moves only at the venue.
