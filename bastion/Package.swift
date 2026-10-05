// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bastion",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Bastion",
            path: "Sources/Bastion",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
