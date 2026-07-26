# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A lightweight macOS **menu bar** app showing real-time crypto prices via the Binance WebSocket + REST API. No main window — it lives entirely in the status bar (`NSStatusItem`) with a custom dropdown panel. Shows BTC and ETH; each can be switched on/off in the panel to show or hide it in the menu bar. There is no search — the coin set is fixed.

The interface follows the **Nothing** design system: monochrome, typographically driven, colour only where it encodes data status. See `## Design system` below before changing anything visual.

## Build & test

There are two build paths and they are deliberately separate:

- **The shippable app** is built from `Tickbyte.xcodeproj` (open in Xcode and Run/Archive). `xcodebuild`'s IDE plugins are broken in this environment, so building the app from the CLI is unreliable.
- **The logic is tested** via SwiftPM:
  ```bash
  swift test                                   # all tests
  swift test --filter PriceFormatterTests      # one test class
  swift test --filter WebSocketPlanTests/testReconnect  # one method
  ```

`Package.swift` is a **test-only harness**, not a second product. It compiles the *same* source files the Xcode target uses (no duplicated code) by listing them explicitly in the `TickbyteCore` target's `sources:`. **When you add a new `.swift` file to the app, add it to that `sources:` list** or `swift test` won't see it. `TickbyteApp.swift` is excluded because its `@main` entry point is only valid in an executable target, and `Fonts/` because it is a resource directory, not source.

## Architecture

Entry point is `TickbyteApp.swift` (`@main`, SwiftUI `App` with an empty `Settings` scene) which hands off to `AppDelegate` via `@NSApplicationDelegateAdaptor`. All real work is in AppKit, not SwiftUI.

Two cooperating layers:

- **`AppDelegate`** — owns the `NSStatusItem` and the panel controller. Renders state to the UI; holds no market data of its own. It does own one piece of *view* state, `focusedSymbol` (which coin sits in the panel's hero slot), deliberately not persisted.
- **`TickerPanelController` / `TickerPanelView`** — the dropdown. A borderless `NSPanel`, not an `NSMenu` or `NSPopover`: both of those impose a system material, a shadow and a fixed row shape, and the design needs a flat surface with one hairline border and no shadow. The controller re-implements what `NSMenu` gave for free — positioning under the status item, dismissal on outside click and on Escape.
- **`WebSocketManager`** — owns *all* market state (`prices`, `priceChanges`, `selectedSymbols`, `connectionStates`) and all networking. The single source of truth.

They communicate via two `NotificationCenter` notifications: `.priceUpdated` and `.connectionStateChanged` (defined in `WebSocketManager.swift`).

### Concurrency model (important)

Both `AppDelegate` and `WebSocketManager` are `@MainActor`. **All mutable state lives on the main actor.** The only off-actor work is the network I/O itself; every URLSession completion (`task.receive`, `sendPing`) hops back via `Task { @MainActor in ... }` *before* touching shared state. Preserve this — don't read/write manager state from a background callback directly.

### Data flow

1. At launch `WebSocketManager` REST-fetches prices for the **selected** symbols only, then opens a `@trade` WebSocket per selected symbol. Prices for all supported coins are refreshed (debounced) when the panel opens, so a hidden coin's row stays current even though it has no live socket.
2. Live trade messages update `prices`; `.priceUpdated` is posted **only while the panel is visible** (`isPanelVisible`) — when closed, the 1 Hz status-bar timer reads state directly, so per-trade notifications would be wasted work.
3. Status bar title: rebuilt every 1s by a timer, but `button.attributedTitle` is only assigned when the title actually changed. `StatusBarText.Title` is `Equatable` so a *colour-only* change (an item going stale at the same price) still counts as a change.
4. Panel: every view is built once in `TickerPanelView.init` for the fixed symbol list and refreshed in place through `update(with:)` — never rebuilt. `AppDelegate` resolves a `PanelSnapshot` and hands it over; the view holds no market state, exactly as the menu it replaced did not.

### Connection resilience

- **Reconnect:** exponential backoff with a ceiling (`BackoffPolicy`, base 5s → cap 60s); a successful connect resets the attempt counter.
- **Half-open detection:** a dead connection delivers neither data nor an error, so a ping timer (`pingInterval` = 30s) pings every active socket; a ping error triggers the same failure path as a receive error.
- **Stale-callback guard:** socket callbacks act only if the firing task is *identically* (`===`) the current socket for that symbol (`WebSocketPlan.isCurrentSocket`). A callback from a socket already replaced by a healthy reconnect is ignored — this prevents a stale teardown from killing the live connection.

### Pure logic (the testable core)

Side-effect-free decision/formatting code is factored out of the AppKit classes so it can be unit-tested without live sockets or AppKit:

- `WebSocketPlan` — which sockets to open/close/reconnect (pure set math over selected vs. active symbols).
- `BackoffPolicy` — reconnect delay calculation.
- `PriceFormatter` — raw feed strings → display text (magnitude-dependent precision; reused immutable `NumberFormatter`s; unparseable input returns a placeholder rather than echoing untrusted feed strings).
- `DisplayText` (`PanelText`, `StatusBarText`) — Foundation-only builders for the panel and status-bar strings. `StatusBarText.make` also returns the exact ranges to colour, computed by construction rather than by searching the finished string.
- `SymbolCatalog` — the fixed supported-symbol list, whitelist validation (`validSymbols`, the URL-injection guard) and display-code derivation (`displayCode`, e.g. `btcusdt` → `BTC`).

When adding behavior to networking or rendering, prefer extending these pure types and testing them, rather than putting logic inside the `@MainActor` classes.

## Design system

The Nothing system in one paragraph: three layers of importance per screen and no more; type carries hierarchy, not colour; spacing carries grouping, not dividers; monochrome canvas with status colour applied to the **value** only; exactly one pattern-break per screen. Anti-patterns to keep out: gradients, shadows, blur, filled or multi-colour icons, emoji as UI, spring easing, skeleton loaders, toasts.

- **Tokens live in `NothingTheme`** — colour, type, spacing, metrics. No hex literal or point size belongs in view code. Dark and light are equal: every surface/text colour is a dynamic `NSColor`, so a view works in both without branching.
- **`cgColor` freezes the appearance current at resolution time.** Any layer-backed view reading a dynamic colour must do it inside `effectiveAppearance.performAsCurrentDrawingAppearance { }` and re-resolve on `viewDidChangeEffectiveAppearance()`, or it stays stuck in whichever mode drew it first.
- **The panel's one pattern-break is the hero number** in Doto, the dot-matrix face. Nothing else on the panel may compete with it; if something needs more emphasis, take it from the hero or move it.
- **Three type sizes on the panel** (`TypeSize.hero` / `.value` / `.label`) and one on the menu bar. A fourth size is almost always a spacing problem — add distance instead.
- **Fonts are bundled, not assumed.** `Tickbyte/Fonts/*.ttf` (Doto, Space Grotesk, Space Mono — all OFL) are registered into the *process* on first font lookup by `NothingTheme.registration`; the app never installs fonts system-wide. Doto and Space Grotesk are variable faces whose named instances are not addressable by PostScript name, so `NothingTheme.resolve` goes through a family + weight `NSFontDescriptor` and verifies the family actually matched before returning — a missing face falls back to a system font rather than silently rendering the wrong one.
- **Adding a font file?** Drop it in `Tickbyte/Fonts/`; the Xcode target uses a filesystem-synchronized group, so it is bundled automatically.

## Conventions

- **Symbol sanitization:** symbols loaded from `UserDefaults` are filtered through `SymbolCatalog.validSymbols` against the supported list before reaching request URLs — a tampered plist must not inject an arbitrary URL segment. Keep this when touching persistence or URL construction.
- **Config lives in `AppConfiguration`** (API URLs, timing, UserDefaults keys, log subsystem); **design tokens live in `NothingTheme`**. No magic numbers/strings scattered in the logic.
- Code comments reference audit findings by ID (e.g. `F7`, `run3 F1`); these point at past fixes — don't regress the behavior they describe.
