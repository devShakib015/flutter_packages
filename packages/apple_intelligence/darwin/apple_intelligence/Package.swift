// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "apple_intelligence",
    // Must match the podspec. SPM defaults an undeclared platform to macOS
    // 10.13, where Swift concurrency does not exist.
    platforms: [
        .iOS("15.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "apple-intelligence", targets: ["apple_intelligence"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "apple_intelligence",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
