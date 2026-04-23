// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-claude-code",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeCode", targets: ["ClaudeCode"]),
    ],
    targets: [
        .target(name: "ClaudeCode"),
        .testTarget(
            name: "ClaudeCodeTests",
            dependencies: ["ClaudeCode"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
