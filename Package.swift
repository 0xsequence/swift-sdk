// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Swift SDK",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Swift SDK",
            targets: ["Swift SDK"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.16.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
             name: "Swift SDK",
             dependencies: [
                 .product(name: "libsecp256k1", package: "secp256k1.swift")
             ]
         ),
        .testTarget(
            name: "Swift SDKTests",
            dependencies: ["Swift SDK"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
