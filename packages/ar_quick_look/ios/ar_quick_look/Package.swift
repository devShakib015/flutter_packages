// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ar_quick_look",
    // Must match the podspec; SPM defaults an undeclared platform to a version
    // without Swift concurrency.
    platforms: [.iOS("15.0")],
    products: [.library(name: "ar-quick-look", targets: ["ar_quick_look"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "ar_quick_look",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
