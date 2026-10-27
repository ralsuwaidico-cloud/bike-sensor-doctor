// swift-tools-version:5.9
import PackageDescription
let package = Package(
  name: "CycliftAudit",
  targets: [
    .target(name: "BikeComputer", path: "Sources/BikeComputer"),
    .executableTarget(name: "Harness", dependencies: ["BikeComputer"], path: "Sources/Harness"),
    .testTarget(name: "BikeComputerTests", dependencies: ["BikeComputer"], path: "Tests/BikeComputerTests"),
  ]
)
