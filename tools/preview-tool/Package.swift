// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "preview-tool",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.7.2"),
    ],
    targets: [
        .target(
            name: "PreviewToolLib",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ],
            path: "Sources",
            exclude: ["CLI"]
        ),
        .executableTarget(
            name: "preview-tool",
            dependencies: [
                "PreviewToolLib",
            ],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "PreviewToolTests",
            dependencies: [
                "PreviewToolLib",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "XcodeProj", package: "XcodeProj"),
            ],
            path: "Tests"
        ),
    ]
)
