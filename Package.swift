// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Loadable",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Loadable",
            targets: ["Loadable"]
        ),
    ],
    dependencies: [
        // Documentation generation for the hosted docs; contributes no code.
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Loadable"
        ),
        .testTarget(
            name: "LoadableTests",
            dependencies: ["Loadable"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
