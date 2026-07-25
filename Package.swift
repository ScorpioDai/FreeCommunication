// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FreeCommunication",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FreeCommunication", targets: ["FreeCommunication"])
    ],
    targets: [
        .executableTarget(
            name: "FreeCommunication",
            path: ".",
            exclude: [
                "Backend",
                "Vendor",
                "script",
                ".codex",
                ".git",
                "Tests",
                "dist",
                "README.md",
                "ARCHIVING.md",
                "PROJECT_NOTES.md",
                "FreeCommunication-1.3.2-source.zip",
                "FreeCommunication-1.3.2.app.zip",
                "FreeCommunication.iconset"
            ],
            sources: [
                "App",
                "Models",
                "Stores",
                "Services",
                "Support",
                "Views"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FreeCommunicationTests",
            dependencies: ["FreeCommunication"],
            path: "Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)
