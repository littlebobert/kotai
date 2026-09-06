// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Kotai",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Kotai", targets: ["Kotai"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.26.0"
        ),
        .package(
            url: "https://github.com/swift-server/async-http-client.git",
            from: "1.29.0"
        ),
        .package(
            url: "https://github.com/apple/swift-nio-extras.git",
            from: "1.35.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Kotai",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KotaiTests",
            dependencies: [
                "Kotai",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ]
)
