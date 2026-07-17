// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bezel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bezel", targets: ["Bezel"]),
        .executable(name: "bezel-bridge", targets: ["BezelBridge"]),
        .library(name: "BezelCore", targets: ["BezelCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "BezelCore",
            path: "Sources/BezelCore"
        ),
        .executableTarget(
            name: "BezelBridge",
            dependencies: ["BezelCore"],
            path: "Sources/BezelBridge"
        ),
        .executableTarget(
            name: "Bezel",
            dependencies: [
                "BezelCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "Sources/Bezel",
            exclude: ["Info.plist", "Bezel.entitlements"]
        ),
        .testTarget(
            name: "BezelCoreTests",
            dependencies: ["BezelCore"],
            path: "Tests/BezelCoreTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
