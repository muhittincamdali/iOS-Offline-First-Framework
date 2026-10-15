// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OfflineFirstFramework",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "OfflineFirstFramework", targets: ["OfflineFirstFramework"])
    ],
    targets: [
        .target(
            name: "OfflineFirstFramework",
            path: "Sources/OfflineFirstFramework"
        ),
        .testTarget(
            name: "OfflineFirstFrameworkTests",
            dependencies: ["OfflineFirstFramework"]
        )
    ]
)
