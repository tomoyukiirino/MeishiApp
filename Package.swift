// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeishiApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MeishiApp",
            targets: ["MeishiApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "MeishiApp",
            dependencies: ["ZIPFoundation"],
            path: "MeishiApp"
        )
    ]
)
