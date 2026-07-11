// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pinny",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Pinny", targets: ["Pinny"])
    ],
    targets: [
        .executableTarget(
            name: "Pinny",
            path: "Pinny",
            exclude: [
                "Info.plist",
                "Pinny.entitlements",
                "Resources/Assets.xcassets",
                "Resources/IconSource"
            ],
            resources: [
                .copy("Resources/RuntimeAssets")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "PinnyTests",
            dependencies: ["Pinny"],
            path: "PinnyTests",
            swiftSettings: [
                // Full Xcode supplies Testing on its normal search path. The
                // standalone Apple Command Line Tools bundle stores it here.
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
                ]),
                .linkedFramework("Testing")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
