// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FlightReminder",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FlightReminder", targets: ["FlightReminder"])
    ],
    targets: [
        .executableTarget(
            name: "FlightReminder",
            path: "Sources/FlightReminder"
        )
    ],
    swiftLanguageVersions: [.v5]
)
