// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BARTTimeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BARTTimeCore", targets: ["BARTTimeCore"])],
    targets: [
        .target(name: "BARTTimeCore", path: "BARTTime/Core", resources: [.process("Resources")]),
        .testTarget(name: "BARTTimeCoreTests", dependencies: ["BARTTimeCore"], path: "Tests", resources: [.process("Fixtures")])
    ]
)
