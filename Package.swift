// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperShot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SuperShotCore",
            targets: ["SuperShotCore"]
        ),
        .executable(
            name: "SuperShot",
            targets: ["SuperShot"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SuperShotCore",
            dependencies: [],
            path: "Sources/SuperShotCore"
        ),
        .executableTarget(
            name: "SuperShot",
            dependencies: ["SuperShotCore"],
            path: "Sources/SuperShot"
        )
    ]
)
