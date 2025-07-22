// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "craftos3",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "craftos3",
            targets: ["craftos3"])
    ],
    dependencies: [
        .package(name: "SDL3", path: "Packages/SDL3"),
        .package(name: "Lua", path: "Packages/Lua"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(name: "craftos3", dependencies: [
            .product(name: "SDL3", package: "SDL3"),
            .product(name: "Lua", package: "Lua"),
            .product(name: "LuaLib", package: "Lua"),
        ]),
        .testTarget(
            name: "craftos3Tests",
            dependencies: ["craftos3"]),
    ]
)
