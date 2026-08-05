// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Papercuts",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PapercutsCore", targets: ["PapercutsCore"]),
        .executable(name: "PapercutsMenuBar", targets: ["PapercutsMenuBar"])
    ],
    targets: [
        .target(name: "PapercutsCore"),
        .executableTarget(name: "PapercutsMenuBar", dependencies: ["PapercutsCore"]),
        .testTarget(name: "PapercutsCoreTests", dependencies: ["PapercutsCore"])
    ]
)
