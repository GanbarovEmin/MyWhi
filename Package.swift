// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyWhi",
    platforms: [
        // Meeting Mode uses modern macOS audio capture flows, and the
        // Soniqo speech toolchain targets current Apple Silicon systems.
        .macOS("15.0")
    ],
    products: [
        .executable(name: "MyWhi", targets: ["MyWhi"]),
    ],
    dependencies: [
        // WhisperKit — on-device Whisper inference via Argmax Core ML/Metal.
        // Primary transcription engine; faster-whisper (Python) is a fallback.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
        // Sparkle — signed GitHub Releases app updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3"),
    ],
    targets: [
        .executableTarget(
            name: "MyWhi",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MyWhi"
        ),
        .testTarget(
            name: "MyWhiTests",
            dependencies: ["MyWhi"],
            path: "Tests/MyWhiTests"
        ),
    ]
)
