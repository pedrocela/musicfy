// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Musicfy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Musicfy",
            path: "Sources/Musicfy",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
