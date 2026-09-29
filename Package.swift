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
        // Renders the note's LaTeX math; vendored and patched, see Vendor/SwiftMath/README.md.
        .target(name: "SwiftMath", path: "Vendor/SwiftMath/Sources/SwiftMath"),
        .executableTarget(name: "StickyCalendar", dependencies: [
            "StickyCalendarCore",
            "SwiftMath",
        ]),
        .testTarget(name: "StickyCalendarCoreTests", dependencies: ["StickyCalendarCore"]),
    ]
)
