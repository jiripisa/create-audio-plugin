// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Foo",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The macOS app (bundle assembled by build.sh — see development_workflow.md §2).
        .executable(name: "Foo", targets: ["Foo"]),
        // App logic without UI — what `swift test` covers.
        .library(name: "FooCore", targets: ["FooCore"]),
    ],
    targets: [
        .target(
            name: "FooCore",
            path: "Sources/FooCore"
        ),
        .executableTarget(
            name: "Foo",
            dependencies: [
                "FooCore",
            ],
            path: "Sources/Foo",
            linkerSettings: [
                // Embedded frameworks ship in Contents/Frameworks (build.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "FooCoreTests",
            dependencies: ["FooCore"],
            path: "Tests/FooCoreTests"
        ),
    ]
)
