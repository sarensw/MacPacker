// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "App", targets: ["App"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Settings", targets: ["Settings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.2.1"),
        .package(url: "https://github.com/kumamotone/XADMasterSwift.git", branch: "main"),
        .package(url: "https://github.com/tsolomko/BitByteData.git", from: "2.0.0"),
        .package(url: "https://github.com/tsolomko/SWCompression.git", from: "4.8.0"),
        .package(url: "https://github.com/tailbeat/TailBeatKit.git", from: "0.10.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                "Core"
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "XADMasterSwift", package: "XADMasterSwift"),
                "BitByteData",
                "SWCompression",
                .product(name: "TailBeatKit", package: "TailBeatKit")
            ]
        ),
        .target(
            name: "Settings",
            dependencies: [
                "App",
                "Core"
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                "TailBeatKit"
            ],
            resources: [
                .copy("TestArchives/defaultArchive.zip")
            ]
        )
    ]
)
