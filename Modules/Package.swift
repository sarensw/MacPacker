// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Modules",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "Core", targets: ["Core"]),
    ],
    dependencies: [
        
    ],
    targets: [
        .target(name: "Core")
    ]
)
