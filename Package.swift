// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Emu6502",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Emu6502", targets: ["Emu6502"]),
        .library(name: "C64Core", targets: ["C64Core"]),
        .library(name: "NESCore", targets: ["NESCore"]),
        .executable(name: "C64App", targets: ["C64App"]),
        .executable(name: "NESApp", targets: ["NESApp"]),
    ],
    targets: [
        .target(name: "Emu6502"),
        .target(name: "C64Core", dependencies: ["Emu6502"]),
        .target(name: "NESCore", dependencies: ["Emu6502"]),
        .executableTarget(
            name: "C64App",
            dependencies: ["C64Core"],
            resources: [
                .copy("ROMS"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "NESApp",
            dependencies: ["NESCore"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(name: "Emu6502Tests", dependencies: ["Emu6502"]),
        .testTarget(name: "C64CoreTests", dependencies: ["C64Core"]),
    ]
)
