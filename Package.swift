// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FreeCommunication",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
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
                "README.zh-CN.md",
                "LICENSE",
                "NOTICE",
                "THIRD_PARTY_NOTICES.md",
                "CONTRIBUTING.md",
                "docs",
                "ARCHIVING.md",
                "PROJECT_NOTES.md",
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
