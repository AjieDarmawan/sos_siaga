// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiagaSOS",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SiagaSOS", targets: ["SiagaSOS"])],
    targets: [
        .target(name: "SiagaSOS"),
        // Uji tanpa XCTest (mesin CI tanpa Xcode penuh): `swift run siagasos-selftest`
        .executableTarget(name: "siagasos-selftest", dependencies: ["SiagaSOS"]),
    ]
)
