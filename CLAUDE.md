# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A lightweight macOS **menu bar** app showing real-time crypto prices via the Binance WebSocket + REST API. No main window — it lives entirely in the status bar (`NSStatusItem`) with a dropdown `NSMenu`. Defaults to BTC + ETH; users search and add/remove any Binance USDT spot pair via a popover (`AddCryptoPopover`).

## Build & test

There are two build paths and they are deliberately separate:

- **The shippable app** is built from `CryptoTicker.xcodeproj` (open in Xcode and Run/Archive). `xcodebuild`'s IDE plugins are broken in this environment, so building the app from the CLI is unreliable.
- **The logic is tested** via SwiftPM:
  ```bash
  swift test                                   # all tests
  swift test --filter PriceFormatterTests      # one test class
  swift test --filter WebSocketPlanTests/testReconnect  # one method
  ```

`Package.swift` is a **test-only harness**, not a second product. It compiles the *same* source files the Xcode target uses (no duplicated code) by listing them explicitly in the `CryptoTickerCore` target's `sources:`. **When you add a new `.swift` file to the app, add it to that `sources:` list** or `swift test` won't see it. `CryptoTickerApp.swift` is excluded because its `@main` entry point is only valid in an executable target.

## Architecture

Entry point is `CryptoTickerApp.swift` (`@main`, SwiftUI `App` with an empty `Settings` scene) which hands off to `AppDelegate` via `@NSApplicationDelegateAdaptor`. All real work is in AppKit, not SwiftUI.

Two cooperating layers:

- **`AppDelegate`** — owns the `NSStatusItem` and `NSMenu`. Renders state to the UI; holds no market data of its own.
- **`WebSocketManager`** — owns *all* market state (`prices`, `priceChanges`, `selectedSymbols`, `connectionStates`) and all networking. The single source of truth.

They communicate via two `NotificationCenter` notifications: `.priceUpdated` and `.connectionStateChanged` (defined in `WebSocketManager.swift`).

### Concurrency model (important)

Both `AppDelegate` and `WebSocketManager` are `@MainActor`. **All mutable state lives on the main actor.** The only off-actor work is the network I/O itself; every URLSession completion (`task.receive`, `sendPing`) hops back via `Task { @MainActor in ... }` *before* touching shared state. Preserve this — don't read/write manager state from a background callback directly.

### Data flow

1. At launch `WebSocketManager` REST-fetches prices for the **selected** symbols only, then opens a `@trade` WebSocket per selected symbol. Adding a symbol from search REST-seeds its price and opens its socket; removing one closes the socket and drops its state. The search universe is the Binance `exchangeInfo` USDT/TRADING list, fetched once on first popover open (`loadTradableSymbolsIfNeeded`).
2. Live trade messages update `prices`; `.priceUpdated` is posted **only while the menu is visible** (`isMenuVisible`) — when closed, the 1 Hz status-bar timer reads state directly, so per-trade notifications would be wasted work.
3. Status bar title: rebuilt every 1s by a timer, but `button.title` is only assigned when the text actually changed.
4. Menu rows: one row per **selected** symbol, rebuilt on menu-open (`rebuildCurrencyRows`) for the current selection (which the popover mutates). While the menu is open, per-trade ticks refresh only the affected row **in place** (`refreshMenuItem`) via the `currencyMenuItems` map — never via reassigning `statusBarItem.menu`.

### Connection resilience

- **Reconnect:** exponential backoff with a ceiling (`BackoffPolicy`, base 5s → cap 60s); a successful connect resets the attempt counter.
- **Half-open detection:** a dead connection delivers neither data nor an error, so a ping timer (`pingInterval` = 30s) pings every active socket; a ping error triggers the same failure path as a receive error.
- **Stale-callback guard:** socket callbacks act only if the firing task is *identically* (`===`) the current socket for that symbol (`WebSocketPlan.isCurrentSocket`). A callback from a socket already replaced by a healthy reconnect is ignored — this prevents a stale teardown from killing the live connection.

### Pure logic (the testable core)

Side-effect-free decision/formatting code is factored out of the AppKit classes so it can be unit-tested without live sockets or AppKit:

- `WebSocketPlan` — which sockets to open/close/reconnect (pure set math over selected vs. active symbols).
- `BackoffPolicy` — reconnect delay calculation.
- `PriceFormatter` — raw feed strings → display text (magnitude-dependent precision; reused immutable `NumberFormatter`s; unparseable input returns a placeholder rather than echoing untrusted feed strings).
- `DisplayText` (`MenuRowText`, `StatusBarText`) — Foundation-only builders for the menu-row and status-bar strings, including the exact colour ranges.
- `SymbolFormat` — symbol validation (`isValid`, the URL-injection guard) and display-code derivation (`displayCode`, e.g. `solusdt` → `SOL`).
- `ExchangeInfo` — decodes Binance `exchangeInfo` into the tradable USDT/TRADING symbol list (the search universe).
- `SymbolSearch` — local, ranked, case-insensitive filter over that list (Binance has no server-side symbol search).

When adding behavior to networking or rendering, prefer extending these pure types and testing them, rather than putting logic inside the `@MainActor` classes.

## Conventions

- **Symbol sanitization:** the symbol is interpolated **unescaped** into the WebSocket URL path, so every symbol is validated by `SymbolFormat.isValid` (regex `^[a-z0-9]{2,20}usdt$`) before it can reach a URL — applied when loading `selectedSymbols` from `UserDefaults` and in `toggleCryptoSelection` before an add. A tampered plist or a searched symbol must not inject an arbitrary URL segment. Keep this when touching persistence or URL construction.
- **Config lives in `AppConfiguration`** (API URLs, timing, fonts, UserDefaults keys, log subsystem). No magic numbers/strings scattered in the logic.
- Code comments reference audit findings by ID (e.g. `F7`, `run3 F1`); these point at past fixes — don't regress the behavior they describe.
