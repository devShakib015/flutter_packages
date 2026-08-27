// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "vitals",
  platforms: [.iOS("15.0")],
  products: [
    .library(name: "vitals", targets: ["vitals"])
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework")
  ],
  targets: [
    .target(
      name: "vitals",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework")
      ],
      resources: [.process("PrivacyInfo.xcprivacy")]
    )
  ]
)
