// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macos_grants",
    // Must match the podspec; SPM defaults an undeclared platform to a version
    // where Swift concurrency does not exist.
    platforms: [.macOS("10.14")],
    products: [.library(name: "macos-grants", targets: ["macos_grants"])],
    // FlutterFramework is the package Flutter generates beside each plugin it
    // links. There is no package called FlutterMacOS, so naming one fails
    // dependency resolution before a line of Swift is compiled.
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "macos_grants",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
