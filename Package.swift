// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyWhi",
    platforms: [
        // SwiftUI WindowGroup + MenuBarExtra require macOS 13+.
        // WhisperKit requires macOS 14+. AppDelegate uses NSStatusItem
        // (works on macOS 26.x; see MyWhiApp.swift header).
        .macOS(.v14)
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
