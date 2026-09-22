// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macos_grants",
    // Must match the podspec; SPM defaults an undeclared platform to a version
    // where Swift concurrency does not exist.
    platforms: [.macOS("10.14")],
    products: [.library(name: "macos-grants", targets: ["macos_grants"])],
    dependencies: [.package(name: "FlutterMacOS", path: "../FlutterMacOS")],
    targets: [
        .target(
            name: "macos_grants",
            dependencies: [.product(name: "FlutterMacOS", package: "FlutterMacOS")]
        )
    ]
)
