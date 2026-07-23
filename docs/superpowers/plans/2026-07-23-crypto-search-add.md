# Crypto Search & Add Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Default the ticker to BTC+ETH and let users search any Binance USDT spot pair and add/remove it via a status-item popover.

**Architecture:** New pure types (`SymbolFormat`, `ExchangeInfo`, `SymbolSearch`) carry the security guard, exchangeInfo parsing, and local search. The curated 7-symbol table is deleted; every symbol renders uniformly from its `baseAsset` code. `WebSocketManager` gains a cached exchangeInfo list; `AppDelegate` shows only selected symbols and opens an `NSPopover` for management. Networking (REST seed + `@trade` socket + reconnect) is unchanged.

**Tech Stack:** Swift, AppKit (Cocoa), SwiftUI app shell, URLSession, XCTest via SwiftPM.

## Global Constraints

- **Symbols are lowercase stream form** (`btcusdt`, `solusdt`) everywhere — dictionary keys, persistence, WebSocket path. Only the REST `?symbol=` param uppercases (`symbol.uppercased()`).
- **Security guard is `SymbolFormat.isValid`** — regex `^[a-z0-9]{2,20}usdt$`. The symbol is interpolated **unescaped** into the WebSocket URL path, so this guard (not any whitelist) is what prevents URL injection. Applied on load-from-UserDefaults and before any symbol reaches a URL. Never regress this.
- **The SwiftPM test target compiles the same app sources** (`Package.swift` `sources:` list). Every new `.swift` file under `CryptoTicker/` MUST be appended there or `swift test` won't see it. All app files compile together each commit — a shared-signature change breaks compilation until every call site is updated.
- **Concurrency:** `WebSocketManager` and `AppDelegate` are `@MainActor`; all mutable state stays on the main actor. Network I/O hops back via `Task { @MainActor in … }` before touching state.
- **Config lives in `AppConfiguration`** — no magic numbers/strings in logic.
- **Commit after each task**, directly on `main`, do not push.

---

### Task 1: SymbolFormat + TradableSymbol (pure)

**Files:**
- Create: `CryptoTicker/Symbol.swift`
- Modify: `Package.swift:24-32` (add source)
- Test: `Tests/CryptoTickerCoreTests/SymbolFormatTests.swift`

**Interfaces:**
- Produces:
  - `struct TradableSymbol: Equatable { let symbol: String; let baseAsset: String }`
  - `enum SymbolFormat { static func isValid(_ symbol: String) -> Bool; static func displayCode(for symbol: String) -> String }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CryptoTickerCoreTests/SymbolFormatTests.swift
import XCTest
@testable import CryptoTickerCore

final class SymbolFormatTests: XCTestCase {

    func testAcceptsWellFormedUSDTSymbols() {
        XCTAssertTrue(SymbolFormat.isValid("btcusdt"))
        XCTAssertTrue(SymbolFormat.isValid("solusdt"))
        XCTAssertTrue(SymbolFormat.isValid("1inchusdt"))
    }

    func testRejectsInjectionAndMalformed() {
        // The symbol is interpolated unescaped into the WebSocket path.
        XCTAssertFalse(SymbolFormat.isValid("../evil@trade"))
        XCTAssertFalse(SymbolFormat.isValid("BTCUSDT"))   // uppercase
        XCTAssertFalse(SymbolFormat.isValid("usdt"))       // no base asset
        XCTAssertFalse(SymbolFormat.isValid(""))
        XCTAssertFalse(SymbolFormat.isValid("btcusd"))     // wrong quote
        XCTAssertFalse(SymbolFormat.isValid(String(repeating: "a", count: 30) + "usdt")) // overlong base
    }

    func testDisplayCodeStripsQuoteAndUppercases() {
        XCTAssertEqual(SymbolFormat.displayCode(for: "solusdt"), "SOL")
        XCTAssertEqual(SymbolFormat.displayCode(for: "btcusdt"), "BTC")
        XCTAssertEqual(SymbolFormat.displayCode(for: "1inchusdt"), "1INCH")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SymbolFormatTests`
Expected: FAIL — `cannot find 'SymbolFormat' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// CryptoTicker/Symbol.swift
import Foundation

/// A Binance spot symbol tradable against USDT, as surfaced by `exchangeInfo`.
struct TradableSymbol: Equatable {
    let symbol: String     // lowercase stream form, e.g. "solusdt"
    let baseAsset: String  // e.g. "SOL"
}

/// Symbol validation and display. `isValid` is the security boundary: the symbol is
/// interpolated unescaped into the WebSocket URL path, so this regex (not a whitelist)
/// is what blocks URL injection.
enum SymbolFormat {
    static func isValid(_ symbol: String) -> Bool {
        symbol.range(of: "^[a-z0-9]{2,20}usdt$", options: .regularExpression) != nil
    }

    /// "solusdt" -> "SOL". Strips the trailing "usdt" quote and uppercases the base.
    static func displayCode(for symbol: String) -> String {
        let base = symbol.hasSuffix("usdt") ? String(symbol.dropLast(4)) : symbol
        return base.uppercased()
    }
}
```

- [ ] **Step 4: Register the source in Package.swift**

In `Package.swift`, add `"Symbol.swift",` to the `sources:` array (after `"CryptoCurrency.swift",`).

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SymbolFormatTests`
Expected: PASS (all three tests).

- [ ] **Step 6: Commit**

```bash
git add CryptoTicker/Symbol.swift Tests/CryptoTickerCoreTests/SymbolFormatTests.swift Package.swift
git commit -m "Add SymbolFormat guard + TradableSymbol"
```

---

### Task 2: ExchangeInfo.parse (pure)

**Files:**
- Create: `CryptoTicker/ExchangeInfo.swift`
- Modify: `Package.swift` (add source)
- Test: `Tests/CryptoTickerCoreTests/ExchangeInfoTests.swift`

**Interfaces:**
- Consumes: `TradableSymbol` (Task 1)
- Produces: `enum ExchangeInfo { static func parse(_ data: Data) -> [TradableSymbol] }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CryptoTickerCoreTests/ExchangeInfoTests.swift
import XCTest
@testable import CryptoTickerCore

final class ExchangeInfoTests: XCTestCase {

    private let json = """
    { "symbols": [
        { "symbol": "SOLUSDT", "status": "TRADING", "baseAsset": "SOL", "quoteAsset": "USDT" },
        { "symbol": "BTCUSDT", "status": "TRADING", "baseAsset": "BTC", "quoteAsset": "USDT" },
        { "symbol": "ETHBTC",  "status": "TRADING", "baseAsset": "ETH", "quoteAsset": "BTC"  },
        { "symbol": "LUNAUSDT","status": "BREAK",   "baseAsset": "LUNA","quoteAsset": "USDT" }
    ] }
    """.data(using: .utf8)!

    func testKeepsOnlyTradingUSDTPairs() {
        let result = ExchangeInfo.parse(json)
        XCTAssertEqual(result, [
            TradableSymbol(symbol: "solusdt", baseAsset: "SOL"),
            TradableSymbol(symbol: "btcusdt", baseAsset: "BTC"),
        ])
    }

    func testMalformedDataReturnsEmpty() {
        XCTAssertEqual(ExchangeInfo.parse(Data("not json".utf8)), [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ExchangeInfoTests`
Expected: FAIL — `cannot find 'ExchangeInfo' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// CryptoTicker/ExchangeInfo.swift
import Foundation

/// Decodes Binance `exchangeInfo` into the USDT-quoted, currently-tradable symbols we offer
/// for search. Filtering to `status == "TRADING"` skips halted/delisting (`BREAK`) markets;
/// there is no server-side quote filter, so USDT is filtered here.
enum ExchangeInfo {
    private struct Response: Decodable {
        struct Symbol: Decodable {
            let symbol: String
            let status: String
            let baseAsset: String
            let quoteAsset: String
        }
        let symbols: [Symbol]
    }

    static func parse(_ data: Data) -> [TradableSymbol] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return response.symbols
            .filter { $0.status == "TRADING" && $0.quoteAsset == "USDT" }
            .map { TradableSymbol(symbol: $0.symbol.lowercased(), baseAsset: $0.baseAsset) }
    }
}
```

- [ ] **Step 4: Register the source in Package.swift**

Add `"ExchangeInfo.swift",` to the `sources:` array.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ExchangeInfoTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add CryptoTicker/ExchangeInfo.swift Tests/CryptoTickerCoreTests/ExchangeInfoTests.swift Package.swift
git commit -m "Add ExchangeInfo.parse (TRADING + USDT filter)"
```

---

### Task 3: SymbolSearch.match (pure)

**Files:**
- Create: `CryptoTicker/SymbolSearch.swift`
- Modify: `Package.swift` (add source)
- Test: `Tests/CryptoTickerCoreTests/SymbolSearchTests.swift`

**Interfaces:**
- Consumes: `TradableSymbol` (Task 1)
- Produces: `enum SymbolSearch { static func match(query: String, in symbols: [TradableSymbol]) -> [TradableSymbol] }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CryptoTickerCoreTests/SymbolSearchTests.swift
import XCTest
@testable import CryptoTickerCore

final class SymbolSearchTests: XCTestCase {

    private let universe = [
        TradableSymbol(symbol: "solusdt",  baseAsset: "SOL"),
        TradableSymbol(symbol: "solousdt", baseAsset: "SOLO"),
        TradableSymbol(symbol: "dogusdt",  baseAsset: "DOG"),   // contains "O", not a prefix of "SOL"
        TradableSymbol(symbol: "btcusdt",  baseAsset: "BTC"),
    ]

    func testPrefixMatchesRankAboveSubstring() {
        let result = SymbolSearch.match(query: "sol", in: universe)
        XCTAssertEqual(result.map(\.symbol), ["solusdt", "solousdt"])
    }

    func testCaseInsensitive() {
        XCTAssertEqual(SymbolSearch.match(query: "BTC", in: universe).map(\.symbol), ["btcusdt"])
    }

    func testSubstringMatchIncluded() {
        // "og" is a substring of DOG's base but not a prefix.
        XCTAssertEqual(SymbolSearch.match(query: "og", in: universe).map(\.symbol), ["dogusdt"])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertEqual(SymbolSearch.match(query: "   ", in: universe), [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SymbolSearchTests`
Expected: FAIL — `cannot find 'SymbolSearch' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// CryptoTicker/SymbolSearch.swift
import Foundation

/// Local, case-insensitive search over the cached exchangeInfo list. Binance has no
/// server-side symbol search, so the client filters the full list on each keystroke.
/// Prefix matches on the base asset rank above substring matches.
enum SymbolSearch {
    static func match(query: String, in symbols: [TradableSymbol]) -> [TradableSymbol] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return [] }
        let prefix = symbols.filter { $0.baseAsset.uppercased().hasPrefix(q) }
        let substring = symbols.filter {
            !$0.baseAsset.uppercased().hasPrefix(q) &&
            ($0.baseAsset.uppercased().contains(q) || $0.symbol.uppercased().contains(q))
        }
        return prefix + substring
    }
}
```

- [ ] **Step 4: Register the source in Package.swift**

Add `"SymbolSearch.swift",` to the `sources:` array.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SymbolSearchTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add CryptoTicker/SymbolSearch.swift Tests/CryptoTickerCoreTests/SymbolSearchTests.swift Package.swift
git commit -m "Add SymbolSearch.match (local ranked filter)"
```

---

### Task 4: WebSocketManager — exchangeInfo cache (additive)

Adds the cached symbol list + fetch. Purely additive: no existing call site references it yet, so the package stays green. Not unit-tested (async network); verified by `swift build`.

**Files:**
- Modify: `CryptoTicker/WebSocketManager.swift`

**Interfaces:**
- Consumes: `TradableSymbol`, `ExchangeInfo.parse` (Tasks 1-2)
- Produces (on `WebSocketManager`):
  - `enum ExchangeInfoLoadState: Equatable { case idle, loading, loaded, failed }`
  - `var tradableSymbols: [TradableSymbol]`
  - `var exchangeInfoState: ExchangeInfoLoadState`
  - `func loadTradableSymbolsIfNeeded() async`

- [ ] **Step 1: Add the state properties**

Add near the other `var` state (after `connectionStates`, `WebSocketManager.swift:53`):

```swift
    /// Cached `exchangeInfo` symbol universe for the search popover. Fetched on first
    /// popover open, in-memory for the session.
    var tradableSymbols: [TradableSymbol] = []
    var exchangeInfoState: ExchangeInfoLoadState = .idle
```

And add the enum above the class (after `ConnectionState`, `WebSocketManager.swift:39`):

```swift
enum ExchangeInfoLoadState: Equatable {
    case idle, loading, loaded, failed
}
```

- [ ] **Step 2: Add the fetch method**

Add inside `WebSocketManager` (e.g. after `fetchAllCryptoPrices`… which is removed in Task 5; place it after `fetchPrices(for:)`):

```swift
    /// Fetches the tradable USDT symbol list once. Re-fetches only if idle or a prior
    /// attempt failed. Filtering to TRADING + USDT happens server- and client-side.
    func loadTradableSymbolsIfNeeded() async {
        guard exchangeInfoState == .idle || exchangeInfoState == .failed else { return }
        exchangeInfoState = .loading
        guard let url = URL(string: "\(AppConfiguration.API.binanceBaseURL)/exchangeInfo?symbolStatus=TRADING&showPermissionSets=false") else {
            exchangeInfoState = .failed
            return
        }
        do {
            let (data, _) = try await urlSession.data(from: url)
            let parsed = ExchangeInfo.parse(data)
            guard !parsed.isEmpty else {
                exchangeInfoState = .failed
                return
            }
            tradableSymbols = parsed
            exchangeInfoState = .loaded
        } catch {
            logger.error("Failed to load exchangeInfo: \(error.localizedDescription)")
            exchangeInfoState = .failed
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Commit**

```bash
git add CryptoTicker/WebSocketManager.swift
git commit -m "Add exchangeInfo symbol cache to WebSocketManager"
```

---

### Task 5: Cutover — drop curated table, uniform code display, BTC+ETH default

The atomic change. Removes `CryptoCurrency`, swaps the display model to code-only, changes defaults, swaps the load/toggle guards to `SymbolFormat`. Touches every file that shared the old signatures, so it lands as one commit that keeps `swift test` green. The popover open is a stub here (wired in Task 6).

**Files:**
- Modify: `CryptoTicker/AppConfiguration.swift`
- Modify: `CryptoTicker/DisplayText.swift`
- Modify: `CryptoTicker/WebSocketManager.swift`
- Modify: `CryptoTicker/AppDelegate.swift`
- Delete: `CryptoTicker/CryptoCurrency.swift`
- Delete: `Tests/CryptoTickerCoreTests/SymbolValidationTests.swift`
- Modify: `Package.swift` (remove `CryptoCurrency.swift` from sources)
- Test: `Tests/CryptoTickerCoreTests/DisplayTextTests.swift` (add/replace)

**Interfaces:**
- Consumes: `SymbolFormat.isValid`, `SymbolFormat.displayCode` (Task 1)
- Produces (changed signatures):
  - `MenuRowText.make(glyph:code:price:change:) -> MenuRowText.Row`
  - `StatusBarText.Item(code:price:indicator:)`

- [ ] **Step 1: Write the failing display-builder test**

Check existing tests first: `ls Tests/CryptoTickerCoreTests/`. If a `DisplayTextTests.swift` (or `MenuRowTextTests`/`StatusBarTextTests`) exists, update its expectations to the new signatures below; otherwise create `DisplayTextTests.swift`:

```swift
// Tests/CryptoTickerCoreTests/DisplayTextTests.swift
import XCTest
@testable import CryptoTickerCore

final class DisplayTextTests: XCTestCase {

    func testMenuRowUsesCodeOnly() {
        let row = MenuRowText.make(glyph: "●", code: "SOL", price: "77.58", change: "+0.13%")
        XCTAssertEqual(row.text, "●\tSOL\t$77.58\t+0.13%")
        XCTAssertEqual(row.statusRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(row.changeRange, NSRange(location: (row.text as NSString).length - 6, length: 6))
    }

    func testStatusBarJoinsCodePriceIndicator() {
        let text = StatusBarText.make(items: [
            .init(code: "BTC", price: "63,201", indicator: ""),
            .init(code: "ETH", price: "3,410", indicator: "⚠️"),
        ])
        XCTAssertEqual(text, "BTC 63,201 | ETH 3,410 ⚠️")
    }

    func testStatusBarEmptyIsAppTitle() {
        XCTAssertEqual(StatusBarText.make(items: []), AppConfiguration.UI.appTitle)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DisplayTextTests`
Expected: FAIL — argument labels `icon:`/`name:` no longer match, or `Item(code:…)` not found.

- [ ] **Step 3: Update DisplayText.swift builders**

Replace `MenuRowText.make` (`DisplayText.swift:21-30`) and the `StatusBarText.Item` struct + `make` (`DisplayText.swift:36-53`):

```swift
    static func make(glyph: String, code: String, price: String, change: String) -> Row {
        let text = "\(glyph)\t\(code)\t$\(price)\t\(change)"
        let fullLength = (text as NSString).length
        let changeLength = (change as NSString).length
        return Row(
            text: text,
            statusRange: NSRange(location: 0, length: (glyph as NSString).length),
            changeRange: NSRange(location: fullLength - changeLength, length: changeLength)
        )
    }
```

```swift
    struct Item {
        let code: String
        let price: String
        let indicator: String
    }
```

```swift
    static func make(items: [Item]) -> String {
        guard !items.isEmpty else { return AppConfiguration.UI.appTitle }
        return items.map { "\($0.code) \($0.price) \($0.indicator)" }.joined(separator: "| ")
    }
```

- [ ] **Step 4: Update AppConfiguration.swift**

- Line 44: `static let selectedCryptos = ["btcusdt", "ethusdt"]`
- Line 25: `static let menuTabStops: [CGFloat] = [30, 110, 230]` (glyph → code → price → change; three tabs).

- [ ] **Step 5: Update WebSocketManager.swift**

- Delete `let availableCurrencies = CryptoCurrency.availableCurrencies` (`:66`).
- Delete `getCurrency(for:)` (`:298-300`).
- Delete `fetchAllCryptoPrices()` (`:88-90`) — the menu now lists only selected symbols, which already have prices; the lazy fetch-all is obsolete.
- `loadSelectedCryptos` (`:79-82`) — swap the sanitizer:

```swift
    private func loadSelectedCryptos() {
        let stored = UserDefaults.standard.array(forKey: AppConfiguration.UserDefaultsKeys.selectedCryptos) as? [String] ?? AppConfiguration.Defaults.selectedCryptos
        selectedSymbols = stored.filter { SymbolFormat.isValid($0) }
    }
```

- `toggleCryptoSelection` (`:288-296`) — guard, seed price on add, clean up on remove:

```swift
    func toggleCryptoSelection(_ symbol: String) {
        guard SymbolFormat.isValid(symbol) else { return }
        if let index = selectedSymbols.firstIndex(of: symbol) {
            selectedSymbols.remove(at: index)
            prices.removeValue(forKey: symbol)
            priceChanges.removeValue(forKey: symbol)
        } else {
            selectedSymbols.append(symbol)
            Task { @MainActor in await fetchPrice(for: symbol) }
        }
        saveSelectedCryptos()
        connectWebSockets()
    }
```

Note: `fetchPrice(for:)` is currently `private` (`:101`). Keep it private — `toggleCryptoSelection` is in the same type, so it can call it.

- [ ] **Step 6: Update AppDelegate.swift — menu + status bar**

Replace `createMenu` (`:76-96`) so currency rows are rebuilt on open and a static "Add crypto…" item is added:

```swift
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(createAddCryptoMenuItem())
        menu.addItem(.separator())
        menu.addItem(createQuitMenuItem())
        return menu
    }

    private func createAddCryptoMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Add crypto…", action: #selector(openAddCryptoPopover), keyEquivalent: "")
        item.target = self
        return item
    }

    /// Rebuilds the per-symbol rows above the first separator for the current selection.
    /// The selection is dynamic (search add/remove), so rows are rebuilt on each open;
    /// per-trade updates still refresh in place via `currencyMenuItems` while open.
    private func rebuildCurrencyRows(in menu: NSMenu) {
        for item in currencyMenuItems.values { menu.removeItem(item) }
        currencyMenuItems.removeAll()
        for (offset, symbol) in webSocketManager.selectedSymbols.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(openAddCryptoPopover), keyEquivalent: "")
            item.representedObject = symbol
            item.target = self
            currencyMenuItems[symbol] = item
            configureMenuItem(item, forSymbol: symbol)
            menu.insertItem(item, at: offset)
        }
    }
```

Replace `refreshMenuItems` (`:100-105`) and `refreshMenuItem` (`:109-113`) to iterate symbols:

```swift
    private func refreshMenuItems() {
        for symbol in webSocketManager.selectedSymbols {
            guard let item = currencyMenuItems[symbol] else { continue }
            configureMenuItem(item, forSymbol: symbol)
        }
    }

    private func refreshMenuItem(for symbol: String) {
        guard let item = currencyMenuItems[symbol] else { return }
        configureMenuItem(item, forSymbol: symbol)
    }
```

Replace `configureMenuItem` (`:115-122`) and `attributedMenuTitle` (`:144-165`):

```swift
    private func configureMenuItem(_ item: NSMenuItem, forSymbol symbol: String) {
        let price = webSocketManager.prices[symbol] ?? AppConfiguration.UI.loadingText
        let change = webSocketManager.priceChanges[symbol] ?? ""
        let isConnected = webSocketManager.isConnected(for: symbol)
        item.attributedTitle = attributedMenuTitle(forSymbol: symbol, price: price, change: change, isConnected: isConnected)
    }
```

```swift
    private func attributedMenuTitle(forSymbol symbol: String, price: String, change: String, isConnected: Bool) -> NSAttributedString {
        let statusColor: NSColor = isConnected ? .systemGreen : .systemRed
        let changeColor: NSColor = {
            guard let value = PriceFormatter.percentValue(change) else { return .secondaryLabelColor }
            return value >= 0 ? .systemGreen : .systemRed
        }()

        let row = MenuRowText.make(
            glyph: statusGlyph(isConnected: isConnected),
            code: SymbolFormat.displayCode(for: symbol),
            price: price,
            change: PriceFormatter.percent(change)
        )

        let attributedString = NSMutableAttributedString(string: row.text, attributes: Self.menuBaseAttributes)
        attributedString.addAttribute(.foregroundColor, value: statusColor, range: row.statusRange)
        attributedString.addAttribute(.foregroundColor, value: changeColor, range: row.changeRange)
        return attributedString
    }
```

Replace `createStatusBarDisplayText` (`:185-198`):

```swift
    private func createStatusBarDisplayText() -> String {
        let items = webSocketManager.selectedSymbols.compactMap { symbol -> StatusBarText.Item? in
            guard let price = webSocketManager.prices[symbol] else { return nil }
            return StatusBarText.Item(
                code: SymbolFormat.displayCode(for: symbol),
                price: price,
                indicator: StatusBarText.indicator(for: webSocketManager.connectionStates[symbol])
            )
        }
        return StatusBarText.make(items: items)
    }
```

Delete `toggleCrypto(_:)` (`:202-210`) — rows no longer toggle. Add the popover stub (fully wired in Task 6):

```swift
    @objc private func openAddCryptoPopover() {
        // Wired in Task 6.
    }
```

Update `menuWillOpen` (`:234-248`) — rebuild rows, drop the obsolete fetch-all:

```swift
    func menuWillOpen(_ menu: NSMenu) {
        webSocketManager.isMenuVisible = true
        rebuildCurrencyRows(in: menu)
        refreshMenuItems()
    }
```

Remove the now-unused `lastMenuFetch` property (`:20`) and any remaining reference to `AppConfiguration.UI.menuFetchDebounce` in AppDelegate.

- [ ] **Step 7: Delete CryptoCurrency and its test; update Package.swift**

```bash
git rm CryptoTicker/CryptoCurrency.swift Tests/CryptoTickerCoreTests/SymbolValidationTests.swift
```
Then remove the `"CryptoCurrency.swift",` line from `Package.swift` `sources:`.

- [ ] **Step 8: Run the full suite**

Run: `swift test`
Expected: PASS — all pure-core tests (SymbolFormat, ExchangeInfo, SymbolSearch, DisplayText, PriceFormatter, WebSocketPlan) compile and pass; no references to the deleted `CryptoCurrency`.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Cut over to code-only display; default BTC+ETH; SymbolFormat guard"
```

---

### Task 6: Add-crypto popover UI

The search/add/remove surface. AppKit UI — not unit-testable via SwiftPM; verified by building and running the app in Xcode.

**Files:**
- Create: `CryptoTicker/AddCryptoPopover.swift`
- Modify: `CryptoTicker/AppDelegate.swift` (wire `openAddCryptoPopover`)
- Modify: `Package.swift` (add source, so the file compiles under `swift build`/`swift test`)

**Interfaces:**
- Consumes: `WebSocketManager` (`selectedSymbols`, `tradableSymbols`, `exchangeInfoState`, `loadTradableSymbolsIfNeeded()`, `toggleCryptoSelection(_:)`), `SymbolSearch.match`, `SymbolFormat.displayCode`
- Produces: `final class AddCryptoPopoverController: NSViewController` with `init(manager:onChange:)`

- [ ] **Step 1: Create the popover controller**

```swift
// CryptoTicker/AddCryptoPopover.swift
import Cocoa

/// Search + add/remove surface shown in an NSPopover. Added symbols show a green ✓ (click
/// removes); search results show + (click adds). Binance has no server-side search, so on
/// first appearance it loads the exchangeInfo list once and filters locally per keystroke.
@MainActor
final class AddCryptoPopoverController: NSViewController {
    private let manager: WebSocketManager
    private let onChange: () -> Void
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()

    init(manager: WebSocketManager, onChange: @escaping () -> Void) {
        self.manager = manager
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 320))

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search crypto (e.g. SOL)"
        searchField.target = self
        searchField.action = #selector(searchChanged)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(rowsStack)
        scroll.documentView = doc

        container.addSubview(searchField)
        container.addSubview(statusLabel)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),

            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            rowsStack.topAnchor.constraint(equalTo: doc.topAnchor),
            rowsStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 4),
            rowsStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -4),
            rowsStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
        reload()
        Task { @MainActor in
            await manager.loadTradableSymbolsIfNeeded()
            reload()
        }
    }

    @objc private func searchChanged() {
        if manager.exchangeInfoState == .idle || manager.exchangeInfoState == .failed {
            Task { @MainActor in
                await manager.loadTradableSymbolsIfNeeded()
                reload()
            }
        }
        reload()
    }

    private func reload() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            statusLabel.stringValue = manager.selectedSymbols.isEmpty
                ? "No cryptos yet — search to add."
                : "Your cryptos:"
            for symbol in manager.selectedSymbols {
                rowsStack.addArrangedSubview(makeRow(symbol: symbol, added: true))
            }
            return
        }

        switch manager.exchangeInfoState {
        case .idle, .loading:
            statusLabel.stringValue = "Loading symbols…"
        case .failed:
            statusLabel.stringValue = "Couldn't load symbols. Edit search to retry."
        case .loaded:
            let results = SymbolSearch.match(query: query, in: manager.tradableSymbols)
            statusLabel.stringValue = results.isEmpty ? "No matches." : "Results:"
            for ts in results.prefix(50) {
                let added = manager.selectedSymbols.contains(ts.symbol)
                rowsStack.addArrangedSubview(makeRow(symbol: ts.symbol, added: added))
            }
        }
    }

    private func makeRow(symbol: String, added: Bool) -> NSView {
        let title = "\(added ? "✓ " : "+ ")\(SymbolFormat.displayCode(for: symbol))"
        let button = NSButton(title: title, target: self, action: #selector(rowClicked(_:)))
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = added ? .systemGreen : .labelColor
        button.identifier = NSUserInterfaceItemIdentifier(symbol)
        return button
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard let symbol = sender.identifier?.rawValue else { return }
        manager.toggleCryptoSelection(symbol)
        onChange()
        reload()
    }
}
```

- [ ] **Step 2: Wire the popover in AppDelegate**

Add a stored property near the other state (`AppDelegate.swift:19-22`):

```swift
    private var addCryptoPopover: NSPopover?
```

Replace the Task 5 stub `openAddCryptoPopover` with:

```swift
    @objc private func openAddCryptoPopover() {
        // Let the menu finish closing before anchoring the popover to the status button.
        DispatchQueue.main.async { [weak self] in self?.presentAddCryptoPopover() }
    }

    private func presentAddCryptoPopover() {
        guard let button = statusBarItem.button else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = AddCryptoPopoverController(manager: webSocketManager) { [weak self] in
            self?.updateStatusBarTitle()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        addCryptoPopover = popover
    }
```

- [ ] **Step 3: Register the source in Package.swift**

Add `"AddCryptoPopover.swift",` to the `sources:` array.

- [ ] **Step 4: Verify it compiles**

Run: `swift build` and `swift test`
Expected: builds clean; all tests still pass (no test regression from the additive UI file).

- [ ] **Step 5: Manual test in Xcode**

Open `CryptoTicker.xcodeproj`, Run. Verify:
1. First launch (clear UserDefaults if needed) shows **BTC and ETH** with live prices.
2. Menu → "Add crypto…" opens the popover; typing `sol` lists `SOL` (and other matches), `+` prefix.
3. Click `SOL` → it gains a ✓, appears in the menu with a price shortly after; status bar shows `SOL`.
4. Clear the search → "Your cryptos:" lists BTC, ETH, SOL with ✓; clicking `SOL`'s ✓ removes it (menu row + status entry disappear, socket closes).
5. Kill network, first-open the popover, type → "Couldn't load symbols. Edit search to retry."; restore network, edit search → results load.

- [ ] **Step 6: Commit**

```bash
git add CryptoTicker/AddCryptoPopover.swift CryptoTicker/AppDelegate.swift Package.swift
git commit -m "Add search/add/remove popover"
```

---

## Self-Review

**Spec coverage:**
- Default BTC+ETH → Task 5 (AppConfiguration).
- Popover as single manage surface → Task 6.
- Curated table dropped, uniform baseAsset display → Task 5.
- `SymbolFormat` regex guard + exchangeInfo membership → Tasks 1, 4, 5, 6.
- exchangeInfo fetched once, USDT+TRADING client-side filter → Tasks 2, 4.
- Networking unchanged → confirmed (only `toggleCryptoSelection` gains a guard + price seed).
- exchangeInfo fetch-fail handling → Task 6 (`.failed` state + retry copy).
- Tests for pure core → Tasks 1-3, 5.
- Register new files in Package.swift → each task.

**Placeholder scan:** none — every step has concrete code/commands. The Task 5 popover method is an explicit, labeled stub replaced in Task 6 (not a placeholder).

**Type consistency:** `MenuRowText.make(glyph:code:price:change:)` and `StatusBarText.Item(code:price:indicator:)` are defined in Task 5 and consumed only there and later. `SymbolFormat.displayCode`/`isValid`, `ExchangeInfo.parse`, `SymbolSearch.match`, `TradableSymbol`, `ExchangeInfoLoadState`, `loadTradableSymbolsIfNeeded()` are named identically across producer and consumer tasks.
