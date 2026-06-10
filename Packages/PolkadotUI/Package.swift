// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PolkadotUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "PolkadotUI",
            targets: ["PolkadotUI"]
        )
    ],
    dependencies: [
        .package(path: "../UIDependencies"),
        .package(path: "../FoundationExt"),
        .package(path: "../UIKitExt"),
        .package(
            url: "https://github.com/paritytech/polkadot-app-design-system-ios",
            from: "0.0.21"
        )
    ],
    targets: [
        .target(
            name: "PolkadotUI",
            dependencies: [
                "UIDependencies",
                "FoundationExt",
                "UIKitExt",
                .product(name: "DesignSystem", package: "polkadot-app-design-system-ios")
            ],
            resources: [
                .process("Typography/Fonts"),
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PolkadotUITests",
            dependencies: ["PolkadotUI"],
            path: "Tests"
        )
    ]
)
