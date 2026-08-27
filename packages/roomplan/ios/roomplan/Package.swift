// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "roomplan",
    // Must match the podspec; SPM defaults an undeclared platform to a version
    // where Swift concurrency does not exist.
    platforms: [.iOS("15.0")],
    products: [.library(name: "roomplan", targets: ["roomplan"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "roomplan",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
