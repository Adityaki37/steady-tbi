// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SteadyCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "SteadyCore", targets: ["SteadyCore"])],
    targets: [
        .target(name: "SteadyCore", path: "Steady", exclude: ["AppStore.swift", "SteadyApp.swift", "ContentView.swift", "CloudClient.swift", "AccountView.swift", "SurvivorProfileView.swift", "SteadyResources", "Assets.xcassets"], sources: ["Domain.swift"]),
        .testTarget(name: "SteadyCoreTests", dependencies: ["SteadyCore"], path: "Tests")
    ]
)
