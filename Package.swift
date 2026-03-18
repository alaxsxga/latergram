// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Latergram",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "LatergramCore", targets: ["LatergramCore"]),
        .library(name: "LatergramPrototype", targets: ["LatergramPrototype"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.10.0"
        ),
        .package(
            url: "https://github.com/supabase/supabase-swift",
            from: "2.0.0"
        )
    ],
    targets: [
        .target(
            name: "LatergramCore",
            path: "Sources/LatergramCore"
        ),
        .target(
            name: "LatergramPrototype",
            dependencies: [
                "LatergramCore",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/LatergramPrototype"
        ),
        .testTarget(
            name: "LatergramCoreTests",
            dependencies: ["LatergramCore"],
            path: "Tests/LatergramCoreTests"
        )
    ]
)
