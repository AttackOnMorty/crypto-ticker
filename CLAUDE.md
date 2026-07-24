# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A lightweight macOS **menu bar** app showing real-time crypto prices via the Binance WebSocket + REST API. No main window — it lives entirely in the status bar (`NSStatusItem`) with a dropdown `NSMenu`. Shows BTC and ETH; each can be toggled on/off in the menu to show or hide it in the menu bar. There is no search — the coin set is fixed.

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

1. At launch `WebSocketManager` REST-fetches prices for the **selected** symbols only, then opens a `@trade` WebSocket per selected symbol. Prices for all supported coins are refreshed (debounced) when the menu opens, so a hidden coin's row stays current even though it has no live socket.
2. Live trade messages update `prices`; `.priceUpdated` is posted **only while the menu is visible** (`isMenuVisible`) — when closed, the 1 Hz status-bar timer reads state directly, so per-trade notifications would be wasted work.
3. Status bar title: rebuilt every 1s by a timer, but `button.title` is only assigned when the text actually changed.
4. Menu rows: one row per **supported** symbol, built once in `createMenu()` for the fixed list and refreshed in place thereafter (`refreshMenuItems`/`refreshMenuItem`) via the `currencyMenuItems` map — never rebuilt, never via reassigning `statusBarItem.menu`.

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
- `SymbolCatalog` — the fixed supported-symbol list, whitelist validation (`validSymbols`, the URL-injection guard) and display-code derivation (`displayCode`, e.g. `btcusdt` → `BTC`).

When adding behavior to networking or rendering, prefer extending these pure types and testing them, rather than putting logic inside the `@MainActor` classes.

## Conventions

- **Symbol sanitization:** symbols loaded from `UserDefaults` are filtered through `SymbolCatalog.validSymbols` against the supported list before reaching request URLs — a tampered plist must not inject an arbitrary URL segment. Keep this when touching persistence or URL construction.
- **Config lives in `AppConfiguration`** (API URLs, timing, fonts, UserDefaults keys, log subsystem). No magic numbers/strings scattered in the logic.
- Code comments reference audit findings by ID (e.g. `F7`, `run3 F1`); these point at past fixes — don't regress the behavior they describe.
