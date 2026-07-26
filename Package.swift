// swift-tools-version:5.9
import PackageDescription

// Test-only harness for the Tickbyte app.
//
// The shippable app is built from Tickbyte.xcodeproj. This package exists so the
// app's logic can be exercised with `swift test` (xcodebuild's IDE plugins are broken
// in this environment). It compiles the *same* source files the Xcode target uses — no
// duplicated code. TickbyteApp.swift is excluded because its `@main` entry point is
// only valid in an executable target and is not needed to test the logic.
let package = Package(
    name: "Tickbyte",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TickbyteCore",
            path: "Tickbyte",
            exclude: [
                "TickbyteApp.swift",
                "Assets.xcassets",
                "Preview Content",
                "Tickbyte.entitlements",
                "Fonts",
            ],
            sources: [
                "WebSocketManager.swift",
                "AppConfiguration.swift",
                "AppDelegate.swift",
                "DisplayText.swift",
                "NothingControls.swift",
                "NothingTheme.swift",
                "PriceFormatter.swift",
                "TickerPanel.swift",
                "WebSocketPlan.swift",
                "Symbol.swift",
            ]
        ),
        .testTarget(
            name: "TickbyteCoreTests",
            dependencies: ["TickbyteCore"],
            path: "Tests/TickbyteCoreTests"
        ),
    ]
)
