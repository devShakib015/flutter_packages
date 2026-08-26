// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "vitals",
  platforms: [.iOS("15.0")],
  products: [
    .library(name: "vitals", targets: ["vitals"])
  ],
  targets: [
    .target(
      name: "vitals",
      resources: [.process("PrivacyInfo.xcprivacy")]
    )
  ]
)
