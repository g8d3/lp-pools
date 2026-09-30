# Columns — one fact per column, every column filterable + sortable

| Column | Filter | Sort | Why |
|---|---|---|---|
| Pool | live text search (hits the DEX API) | A–Z | identity; search always live, empty search browses cache |
| DEX | multi-select + search | A–Z | raydium, uniswap_v3, aerodrome… pick several |
| Src | multi-select | A–Z | **who says so**: venue's own API vs aggregator — the doubt-killer column |
| Chain | multi-select + search | A–Z | eth, solana, base… pick several |
| Liquidity | min + max range | numeric | size = trust + capacity |
| Vol 24h | min + max range | numeric | raw activity |
| Turnover | min + max range | numeric | vol/liquidity per day — the earning signal |
| Δ 24h | min + max range | numeric | momentum, green/red |
| Txns | min + max range | numeric | buys+sells — real usage vs wash |
| Age | min + max days | oldest/newest | new pools = farm risk + opportunity |
| Action | Deposit button per row | — | opens the 3-step panel instantly; row taps do nothing |

Rules: numeric = range, many-valued = multi-select, text = live API search.
Every filter + sort + page lives in the URL hash. CSV exports the current view.
Deliberately absent: IL flags, asset counts — the DEX API doesn't provide them, so they're not shown.
Deposit panel extras: DEX-reported APR (Raydium rows), token contracts with copy + explorer links, Uniswap pools get a deep link straight to the add-liquidity page.
