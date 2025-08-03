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
            targets: ["OfflineFirstFramework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint", from: "0.54.0"),
        .package(url: "https://github.com/Quick/Quick", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble", from: "13.0.0"),
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.8.1"),
        .package(url: "https://github.com/ReactiveX/RxSwift", from: "6.6.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "7.10.1"),
        .package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", from: "3.8.0"),
        .package(url: "https://github.com/airbnb/lottie-ios", from: "4.3.3"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.1"),
        .package(url: "https://github.com/danielgindi/Charts", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "OfflineFirstFramework",
            dependencies: [
                "Alamofire",
                "RxSwift",
                "Kingfisher",
                "CocoaLumberjack",
                "Lottie",
                "SwiftyJSON",
                "Charts"
            ],
            path: "Sources/OfflineFirstFramework",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release)),
                .unsafeFlags(["-warn-implicit-override"])
            ]
        ),
        .testTarget(
            name: "OfflineFirstFrameworkTests",
            dependencies: [
                "OfflineFirstFramework",
                "Quick",
                "Nimble"
            ],
            path: "Tests/OfflineFirstFrameworkTests",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "OfflineFirstExample",
            dependencies: ["OfflineFirstFramework"],
            path: "Examples/OfflineFirstExample"
        )
    ],
    swiftSettings: [
        .enableUpcomingFeature("BareSlashRegexLiterals"),
        .enableUpcomingFeature("ConciseMagicFile"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("ForwardTrailingClosures"),
        .enableUpcomingFeature("ImplicitOpenExistentials"),
        .enableUpcomingFeature("StrictConcurrency")
    ]
)
