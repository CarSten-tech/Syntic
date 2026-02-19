// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repositoryDirectory = packageDirectory
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let rustLibrarySearchPath = repositoryDirectory.appendingPathComponent("target/debug").path

let package = Package(
    name: "SynticMacOS",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "SynticApp", targets: ["SynticApp"]),
    ],
    targets: [
        .target(
            name: "SynticFFI",
            path: "Sources/SynticFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(["-L", rustLibrarySearchPath]),
                .linkedLibrary("syntic_ffi"),
            ]
        ),
        .executableTarget(
            name: "SynticApp",
            dependencies: ["SynticFFI"],
            path: "Sources/SynticApp"
        ),
        .testTarget(
            name: "SynticAppTests",
            dependencies: ["SynticApp"],
            path: "Tests/SynticAppTests"
        ),
    ]
)
