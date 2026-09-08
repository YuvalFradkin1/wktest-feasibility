// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WKTest",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WKTest",
            path: "Sources/WKTest",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        )
    ]
)
