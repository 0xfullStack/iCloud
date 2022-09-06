// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iCloud+Radius",
    platforms: [
        .iOS(.v13), .macOS(.v12), .tvOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "iCloud",
            targets: ["iCloud"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
         .package(url: "https://github.com/pengpengliu/BIP39", from: "1.0.1"),
         .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .upToNextMinor(from: "1.4.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "iCloud",
            dependencies: [
                .byName(name: "BIP39"),
                .byName(name: "CryptoSwift")
            ]),
        .testTarget(
            name: "iCloudTests",
            dependencies: ["iCloud"]),
    ]
)
