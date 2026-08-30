// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HushPort",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "HushPortCore", targets: ["HushPortCore"]),
        .library(name: "HushPortRingBuffer", targets: ["HushPortRingBuffer"]),
        .executable(name: "HushPortMac", targets: ["HushPortMac"]),
        .executable(name: "HushPortIOS", targets: ["HushPortIOS"]),
    ],
    targets: [
        .target(name: "HushPortCore"),
        .target(
            name: "HushPortRingBuffer",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "HushPortMac",
            dependencies: ["HushPortCore", "HushPortRingBuffer"],
            exclude: ["HushPortMac.entitlements", "Info.plist"]
        ),
        .executableTarget(
            name: "HushPortIOS",
            dependencies: ["HushPortCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "HushPortCoreTests",
            dependencies: ["HushPortCore", "HushPortRingBuffer"]
        ),
    ]
)
