// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OfflineFirstFramework",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "OfflineFirstFramework",
            targets: ["OfflineFirstFramework"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint", from: "0.54.0"),
        .package(url: "https://github.com/Quick/Quick", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble", from: "13.0.0"),
        .package(url: "https://github.com/ReactiveX/RxSwift", from: "6.6.0"),
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", from: "3.8.0")
    ],
    targets: [
        .target(
            name: "OfflineFirstFramework",
            dependencies: [
                "RxSwift",
                .product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack")
            ],
            path: "Sources/OfflineFirstFramework",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "OfflineFirstFrameworkTests",
            dependencies: [
                "OfflineFirstFramework",
                "Quick",
                "Nimble"
            ],
            path: "Tests/OfflineFirstFrameworkTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
