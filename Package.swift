// swift-tools-version:5.9
import PackageDescription

// Test-only harness for the CryptoTicker app.
//
// The shippable app is built from CryptoTicker.xcodeproj. This package exists so the
// app's logic can be exercised with `swift test` (xcodebuild's IDE plugins are broken
// in this environment). It compiles the *same* source files the Xcode target uses — no
// duplicated code. CryptoTickerApp.swift is excluded because its `@main` entry point is
// only valid in an executable target and is not needed to test the logic.
let package = Package(
    name: "CryptoTicker",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CryptoTickerCore",
            path: "CryptoTicker",
            exclude: [
                "CryptoTickerApp.swift",
                "Assets.xcassets",
                "Preview Content",
                "CryptoTicker.entitlements",
            ],
            sources: [
                "WebSocketManager.swift",
                "AppConfiguration.swift",
                "AppDelegate.swift",
                "DisplayText.swift",
            ]
        ),
        .testTarget(
            name: "CryptoTickerCoreTests",
            dependencies: ["CryptoTickerCore"],
            path: "Tests/CryptoTickerCoreTests"
        ),
    ]
)
