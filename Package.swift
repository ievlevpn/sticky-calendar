// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StickyCalendar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StickyCalendar", targets: ["StickyCalendar"]),
    ],
    targets: [
        .target(name: "StickyCalendarCore"),
        .executableTarget(name: "StickyCalendar", dependencies: ["StickyCalendarCore"]),
        .testTarget(name: "StickyCalendarCoreTests", dependencies: ["StickyCalendarCore"]),
    ]
)
