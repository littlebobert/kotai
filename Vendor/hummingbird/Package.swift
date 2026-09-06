// swift-tools-version:6.1

import PackageDescription

var swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

#if compiler(>=6.3)
swiftSettings.append(
    .enableExperimentalFeature(
        "AvailabilityMacro=hummingbird 2.0:macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, Android 28"
    )
)
#else
swiftSettings.append(
    .enableExperimentalFeature(
        "AvailabilityMacro=hummingbird 2.0:macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0"
    )
)
#endif

let package = Package(
    name: "hummingbird",
    platforms: [.macOS(.v11), .iOS(.v15), .macCatalyst(.v15), .tvOS(.v15), .visionOS(.v1)],
    products: [
        .library(name: "Hummingbird", targets: ["Hummingbird"]),
        .library(name: "HummingbirdCore", targets: ["HummingbirdCore"]),
        .library(name: "HummingbirdTesting", targets: ["HummingbirdTesting"]),
    ],
    traits: [
        .trait(name: "ConfigurationSupport", description: "Enable support for swift-configuration package."),
        .default(enabledTraits: ["ConfigurationSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-configuration.git", from: "1.0.2", traits: []),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.9.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.34.1"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.14.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-service-context.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-system.git", from: "1.8.1"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.30.0"),
    ],
    targets: [
        .target(
            name: "Hummingbird",
            dependencies: [
                .byName(name: "HummingbirdCore"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Configuration", package: "swift-configuration", condition: .when(traits: ["ConfigurationSupport"])),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Tracing", package: "swift-distributed-tracing"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationEssentialsCompat", package: "swift-nio"),
                .product(name: "ServiceContextModule", package: "swift-service-context"),
                .product(name: "SystemPackage", package: "swift-system"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HummingbirdCore",
            dependencies: [
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "Configuration", package: "swift-configuration", condition: .when(traits: ["ConfigurationSupport"])),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTPTypes", package: "swift-nio-extras"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(
                    name: "NIOTransportServices",
                    package: "swift-nio-transport-services",
                    condition: .when(platforms: [.macOS, .iOS, .macCatalyst, .tvOS, .visionOS])
                ),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "HummingbirdTesting",
            dependencies: [
                .byName(name: "Hummingbird"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOHTTPTypes", package: "swift-nio-extras"),
                .product(name: "NIOHTTPTypesHTTP1", package: "swift-nio-extras"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
