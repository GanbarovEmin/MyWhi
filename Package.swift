// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HermesDictate",
    platforms: [
        // MenuBarExtra is macOS 13+. We use newer SwiftUI APIs that are
        // cleanest on macOS 14+. The user's Mac is on 26.x, so this is safe.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HermesDictate", targets: ["HermesDictate"]),
    ],
    targets: [
        .executableTarget(
            name: "HermesDictate",
            path: "Sources/HermesDictate"
        ),
    ]
)
