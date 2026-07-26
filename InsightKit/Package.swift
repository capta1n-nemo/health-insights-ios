// swift-tools-version: 5.9
import PackageDescription

// InsightKit is the pure-Swift domain core of the Health Insights app.
//
// It deliberately has NO dependency on HealthKit, SwiftUI, UIKit or SwiftData
// so that every piece of clinical / statistical logic can be unit-tested with a
// plain `swift test` on any platform — no Xcode, simulator, or device required.
//
// The iOS app target imports this package and adapts platform data (HealthKit
// samples, provider payloads) into the canonical types defined here.
let package = Package(
    name: "InsightKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "InsightKit", targets: ["InsightKit"])
    ],
    targets: [
        .target(name: "InsightKit"),
        .testTarget(
            name: "InsightKitTests",
            dependencies: ["InsightKit"]
        )
    ]
)
