# Health Insights iOS App

## Primary Verification Commands
- Unit Tests: `cd InsightKit && swift test`
- Build Check: `xcodebuild build -project HealthInsights.xcodeproj -scheme HealthInsights -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`

## Automation Rules
- Fully manage all files, including Xcode project structures, Swift files, and configurations.
- Architecture: Swift 6, SwiftUI, `@Observable` view models (NO `ObservableObject`), `NavigationStack` (NO `NavigationView`), `@MainActor` on view models.
- Treat static attributes (Height, Sex) separately from time-series vitals (Heart Rate, Weight).
- Always run `cd InsightKit && swift test` locally before making any git commit.
- Once pushed to `main`, notify the user that deployment to their iPhone is triggered, then complete the turn immediately.

## Memory Router
- `docs/architecture.md` -> Core data pipeline, BYO-Key API client, and Swift patterns.
- `docs/deployment.md` -> Wi-Fi deployment & CI rules.
- `docs/activeContext.md` -> Current task focus and immediate next steps.
- `docs/progress.md` -> Feature roadmap checklist.

## End of Session Protocol
When the user says "handover", "wrap up", or runs `/handover`:
1. Update `docs/activeContext.md` with recent changes, architectural choices, and next technical steps.
2. Update `docs/progress.md` checklist items.
3. Commit docs to git with message `docs: update active context and progress state`.
