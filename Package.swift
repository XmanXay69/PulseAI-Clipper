// swift-tools-version:5.10
import PackageDescription

// PULSE — AI video clipping & short-form editor for macOS.
//
// Layering:
//   PulseCore   – pure Swift models + algorithms (timeline, projects, transcripts,
//                 clip generation, captions, layouts, export config, AI abstraction).
//                 No Apple media frameworks, fully unit-testable.
//   PulseEngine – macOS media engine (AVFoundation, VideoToolbox, Vision, Speech,
//                 CoreImage/Metal compositor, export, analysis pipeline).
//   PulseApp    – SwiftUI/AppKit desktop application.
let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PULSE", targets: ["PulseApp"]),
        .library(name: "PulseCore", targets: ["PulseCore"]),
        .library(name: "PulseEngine", targets: ["PulseEngine"]),
    ],
    targets: [
        .target(name: "PulseCore"),
        .target(name: "PulseEngine", dependencies: ["PulseCore"]),
        .executableTarget(name: "PulseApp", dependencies: ["PulseCore", "PulseEngine"]),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
        .testTarget(name: "PulseEngineTests", dependencies: ["PulseEngine", "PulseCore"], exclude: ["Fixtures"]),
    ]
)
