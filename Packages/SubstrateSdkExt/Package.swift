// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SubstrateSdkExt",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "SubstrateSdkExt",
            targets: ["SubstrateSdkExt"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/novasamatech/substrate-sdk-ios",
            from: "5.7.0"
        )
    ],
    targets: [
        .target(
            name: "SubstrateSdkExt",
            dependencies: [
                .product(name: "SubstrateSdk", package: "substrate-sdk-ios"),
                .product(name: "SubstrateStorageQuery", package: "substrate-sdk-ios"),
                .product(name: "SubstrateStorageSubscription", package: "substrate-sdk-ios"),
            ]
        )
    ]
)
