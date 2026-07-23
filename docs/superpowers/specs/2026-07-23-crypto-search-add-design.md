# Crypto Search & Add — Design

**Date:** 2026-07-23
**Status:** Approved, ready for implementation plan

## Goal

Two changes to the CryptoTicker menu-bar app:

1. Default selection becomes **BTC + ETH** only (was BTC only).
2. Users can **search** any Binance USDT spot pair and **add / remove** it from their ticker, via a **popover** anchored to the status item.

The curated 7-symbol table is removed entirely — the app no longer maintains a hardcoded currency list. Any tradable USDT symbol is fair game.

## Non-goals

- No non-USDT quote pairs (BTC/ETH-quoted markets). USDT only.
- No on-disk cache of the symbol list (in-memory per session is enough).
- No friendly full names or per-coin glyphs (the API doesn't provide them; see Display).
- No change to the networking layer (REST seed, `@trade` socket, reconnect/backoff/ping stay as-is).

## Background — Binance API (verified 2026-07-23)

All endpoints are public, security type `NONE`, no API key.

- **Symbol list:** `GET https://api.binance.com/api/v3/exchangeInfo?symbolStatus=TRADING&showPermissionSets=false` — ~54 KB gzipped, ~1,376 live symbols; URLSession sends `Accept-Encoding: gzip` automatically. Weight 20 against a 6,000/min budget. There is **no** server-side quote filter and **no** server-side search — fetch once, filter/search client-side.
- Each symbol object carries the fields we need: `symbol` (`"SOLUSDT"`), `baseAsset` (`"SOL"`), `quoteAsset` (`"USDT"`), `status` (`"TRADING"` vs `"BREAK"`).
- **The API returns only the ticker code (`baseAsset`), never a full name or icon.**
- Per-symbol REST seed (`/ticker/24hr?symbol=…`) and `wss://stream.binance.com:9443/ws/<symbol-lowercased>@trade` work for any valid symbol — the app's existing machinery already handles them, including the 24h forced socket disconnect.

## Architecture

The existing layered design is preserved: pure logic (testable core), config constants, `@MainActor` stateful manager, AppKit UI. New behavior goes into **pure types** wherever possible, per project convention.

### Current state (from recon)

- Defaults: `AppConfiguration.swift:44` — `Defaults.selectedCryptos = ["btcusdt"]`.
- Curated table: `CryptoCurrency.swift:14-22` — `availableCurrencies`, 7 hardcoded entries.
- Security guard: `CryptoCurrency.validSymbols(from:)` (`CryptoCurrency.swift:27-30`) — whitelists against those 7.
- Selection state: `WebSocketManager.selectedSymbols` — loaded/sanitized (`:79-82`), persisted (`:84-86`), toggled (`:288-296`).
- URL construction (symbol interpolated **unescaped** into WebSocket path): `WebSocketManager.swift:101-105` (REST) and `:145-159` (WebSocket).
- Menu: `AppDelegate.createMenu()` (`:76-96`) — one fixed row per curated currency, checkmark = selected.
- SPM sources list: `Package.swift:24-32` — new `.swift` files must be appended here.

### Data model — two decoupled layers

The "valid universe" (was the 7-item whitelist) splits into two independent guards:

1. **`SymbolFormat.isValid(_ symbol: String) -> Bool`** — **security boundary.** Regex `^[a-z0-9]{2,20}usdt$`. Because the symbol is interpolated unescaped into the WebSocket path, this is what blocks URL injection (`../evil@trade`, uppercase, empty, bare `usdt`, overlong). Always on — applied at load-from-UserDefaults and before any URL build. Guarantees URL safety **at launch, before exchangeInfo is fetched**. This fully replaces `CryptoCurrency.validSymbols(from:)`.

2. **`tradableSymbols: [TradableSymbol]`** — **correctness filter.** Cached exchangeInfo result, `{symbol: "solusdt", baseAsset: "SOL"}`, fetched on first popover open, filtered client-side to `quoteAsset == "USDT"` and `status == "TRADING"`. Search only surfaces symbols from this list, so a well-formed-but-nonexistent symbol can't be added. In-memory for the session; refetched next launch.

`TradableSymbol.symbol` is stored lowercase (`solusdt`) to match the existing stream-symbol convention used everywhere as the dictionary key.

### Pure / testable additions (the core)

- `SymbolFormat.isValid(symbol)` — regex guard above.
- `ExchangeInfo.parse(_ data: Data) -> [TradableSymbol]` — decode exchangeInfo JSON, keep only `status == "TRADING"` && `quoteAsset == "USDT"`, map to `{symbol (lowercased), baseAsset}`.
- `SymbolSearch.match(query: String, in: [TradableSymbol]) -> [TradableSymbol]` — case-insensitive match on `baseAsset` / `symbol`, ranked (prefix match ranks above substring), empty query returns empty (or the added list — UI decides).
- `displayCode(for symbol: String) -> String` — `solusdt` → `SOL` (strip trailing `usdt`, uppercase). One line; no curated lookup, no branch.

### Display

Every symbol is rendered uniformly from its `baseAsset` code — the API gives nothing else.

- Status bar / menu rows show the text code: `BTC $63,201`, `SOL $77`. No glyphs.
- BTC and ETH are treated identically to every other symbol.
- Added tickers render from the stored symbol string alone (`displayCode`), so existing rows draw correctly offline without exchangeInfo.

`CryptoCurrency.availableCurrencies`, its `icon`/`name` curation, and `validSymbols(from:)` are removed. Wherever the code currently reads a `CryptoCurrency`'s display fields, it uses `displayCode(for:)` instead.

### Persistence

- `AppConfiguration.Defaults.selectedCryptos = ["btcusdt", "ethusdt"]`.
- `loadSelectedCryptos` sanitizes each stored symbol through `SymbolFormat.isValid` (not the old whitelist), so arbitrary added symbols survive relaunch and open sockets safely. Existing users keep their stored selection via the current `??` fallback.
- `saveSelectedCryptos` unchanged (persists the already-sanitized in-memory list).

### UI

- **Menu** (`AppDelegate`): rows for **selected symbols only** — live prices, keyed `NSMenuItem`s, in-place `refreshMenuItems` preserved. Plus an **"Add crypto…"** item that opens the popover, plus Quit. The fixed 7-row checklist is gone.
- **Popover** (new): `NSPopover` anchored to the status item, containing a search field + list:
  - **Added** section — current `selectedSymbols`, each checkmarked; click **removes** (stops the socket, drops the row).
  - **Search results** — as the user types, `SymbolSearch.match` filters the cached `tradableSymbols`; click **adds** (persists, REST-seeds, opens `@trade` socket).
  - First open triggers the exchangeInfo fetch. While loading: a spinner / "Loading…" state. On failure: "Couldn't load symbols — retry"; existing tickers are unaffected and the menu keeps working.

### Networking — unchanged

`toggleCryptoSelection` still drives `connectWebSockets()`; adding a symbol reuses `fetchPrice` (REST seed) + `connectWebSocket` (`@trade`) + the reconnect/backoff/ping machinery verbatim. The only guard change: `SymbolFormat.isValid` gates the symbol before it reaches a URL.

## Error handling

- **exchangeInfo fetch fails:** popover shows a retry state; menu and live tickers unaffected. Search is unavailable until the list loads.
- **Malformed / tampered persisted symbol:** rejected by `SymbolFormat.isValid` at load; never reaches a URL.
- **Added symbol goes stale (delisted → BREAK → removed):** the existing reconnect path handles a socket with no trades; the symbol simply shows its last price. (No active de-listing sweep — YAGNI.)

## Testing (SwiftPM pure core)

- `SymbolFormat.isValid`: accepts `btcusdt`, `solusdt`; rejects `../evil@trade`, `BTCUSDT` (case), `usdt` (no base), empty, overlong.
- `ExchangeInfo.parse`: keeps TRADING+USDT, drops BREAK and non-USDT, extracts `baseAsset`, lowercases `symbol`.
- `SymbolSearch.match`: `sol` → `solusdt`; case-insensitive; prefix ranks above substring; empty query.
- `displayCode`: `solusdt` → `SOL`.
- Register every new `.swift` file in `Package.swift` `sources:` (`:24-32`) or `swift test` won't compile it.

## Files touched (anticipated)

- `AppConfiguration.swift` — default → `["btcusdt","ethusdt"]`.
- `CryptoCurrency.swift` — remove curated table + `validSymbols`; likely replaced by the new pure types.
- New: `SymbolFormat.swift`, `ExchangeInfo.swift`, `SymbolSearch.swift` (or grouped), + display helper.
- `WebSocketManager.swift` — new `tradableSymbols` state + fetch; load sanitizer swap; guard swap.
- `AppDelegate.swift` — menu rebuild (selected-only + "Add crypto…") + popover controller.
- `Package.swift` — register new source files.
- `Tests/CryptoTickerCoreTests/` — new tests; remove/adjust `SymbolValidationTests` for the new guard.
