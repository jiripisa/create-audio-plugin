// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "{{APP}}",
    platforms: [
        .macOS(.v27)
    ],
    products: [
        // The macOS app (bundle assembled by build.sh — see development_workflow.md §2).
        .executable(name: "{{APP}}", targets: ["{{APP}}"]),
        // App logic without UI — what `swift test` covers.
        .library(name: "{{APP}}Core", targets: ["{{APP}}Core"]),
        // The Audio Unit and its window (build.sh turns it into {{APP}}.component).
        .library(name: "{{APP}}AU", type: .dynamic, targets: ["{{APP}}AU", "{{APP}}AUView", "{{APP}}AUExports"]),
    ],
    dependencies: [
        // Auto-update: the standard updater for apps outside the App Store;
        // EdDSA-signed appcast on GitHub Pages.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // The sound engine: C++ with a C interface (include/{{APP}}DSP.h).
        .target(
            name: "{{APP}}DSP",
            path: "Sources/{{APP}}DSP"
        ),
        // Apple's AudioUnitSDK (Apache-2.0), vendored: it is not a Swift package.
        .target(
            name: "AudioUnitSDK",
            path: "ThirdParty/AudioUnitSDK",
            exclude: ["LICENSE.txt"],
            sources: ["src"],
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreMIDI"),
            ]
        ),
        // The Audio Unit (AUv2 instrument). build.sh wraps the dylib into {{APP}}.component.
        .target(
            name: "{{APP}}AU",
            dependencies: ["{{APP}}DSP", "AudioUnitSDK"],
            path: "Sources/{{APP}}AU"
        ),
        // The Audio Unit's window in a host: the panel over the unit and its engine. The unit
        // names its class ({{APP}}AUViewFactory) in its CocoaUI property.
        .target(
            name: "{{APP}}AUView",
            dependencies: ["{{APP}}Core", "{{APP}}UI"],
            path: "Sources/{{APP}}AUView"
        ),
        // No code, only what the Audio Unit's dynamic library exports.
        .target(
            name: "{{APP}}AUExports",
            path: "Sources/{{APP}}AUExports",
            linkerSettings: [
                // A plug-in shares the host's process with other plug-ins: export only the
                // factory function the host looks up (AudioUnit-Info.plist, factoryFunction).
                .unsafeFlags(["-Xlinker", "-exported_symbol", "-Xlinker", "_{{APP}}AUFactory"]),
            ]
        ),
        .target(
            name: "{{APP}}Core",
            dependencies: ["{{APP}}DSP"],
            path: "Sources/{{APP}}Core"
        ),
        // The instrument's panel, the same in the app's window and in the plug-in's.
        .target(
            name: "{{APP}}UI",
            dependencies: ["{{APP}}Core"],
            path: "Sources/{{APP}}UI"
        ),
        .executableTarget(
            name: "{{APP}}",
            dependencies: [
                "{{APP}}Core",
                "{{APP}}UI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/{{APP}}",
            linkerSettings: [
                // Embedded frameworks ship in Contents/Frameworks (build.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        // The throwaway prototype (.planning/research/spike) as a C++ reference the
        // engine is compared against in tests. Test-only: never linked into the app.
        .target(name: "{{APP}}Reference", path: "Tests/{{APP}}Reference"),
        .testTarget(
            name: "{{APP}}CoreTests",
            // The Audio Unit too, which the tests run inside their own process, its window's
            // model, and the panel's logic that does not need a window.
            dependencies: ["{{APP}}Core", "{{APP}}DSP", "{{APP}}Reference", "{{APP}}AU", "{{APP}}AUView", "{{APP}}UI"],
            path: "Tests/{{APP}}CoreTests"
        ),
    ],
    // AudioUnitSDK needs C++23.
    cxxLanguageStandard: .cxx2b
)
