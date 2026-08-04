import XCTest
@testable import InsightKit

/// **One instrument, one vote.**
///
/// The reader runs a Shortcut mirroring Oura's VO₂max, HRV, resting heart rate,
/// SpO2 and temperature into Apple Health under a name containing no "oura", so
/// `deviceFamily`'s name rule filed it as `apple_health` and the same ring
/// counted twice — doubling its weight in every daily mean and able to flip
/// `VitalReader`'s winner-take-all tie-break. That is where the ±13-year
/// week-to-week sawtooth in the fitness-age history came from.
final class MirrorCollapseTests: XCTestCase {

    private func sample(_ value: Double, source: MetricSource,
                        minutesAgo: Int = 0,
                        type: MetricType = .vo2Max) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: TestClock.now.addingTimeInterval(-Double(minutesAgo) * 60),
                           source: source)
    }

    /// A source whose display name gives `deviceFamily` nothing to match, so it
    /// falls through to `apple_health` — exactly the shortcut's shape.
    private var mirror: MetricSource {
        MetricSource(id: "apple_health/shortcut", displayName: "Automation via Apple Health")
    }

    func testTheMirrorFallsThroughToAppleHealth() {
        XCTAssertEqual(mirror.deviceFamily, "apple_health",
                       "if this ever stops being true the defect this file guards has changed shape")
        XCTAssertEqual(MetricSource.oura.deviceFamily, "oura")
    }

    /// The defect: two families, one value, two votes.
    func testAMirroredReadingCountsOnce() {
        let kept = MultiSource.deduplicate([
            sample(44.2, source: .oura),
            sample(44.2, source: mirror)
        ])
        XCTAssertEqual(kept.count, 1, "the same reading counted twice — the ring got two votes")
    }

    /// And the copy that survives is the real instrument, so the per-source
    /// breakdown and the export name the thing that actually measured it.
    func testTheDirectSourceSurvivesRatherThanTheMirror() throws {
        let kept = MultiSource.deduplicate([
            sample(44.2, source: mirror),
            sample(44.2, source: .oura)
        ])
        XCTAssertEqual(try XCTUnwrap(kept.first).source.deviceFamily, "oura",
                       "the Apple Health copy survived and the real instrument was dropped")
    }

    /// **Two genuinely different devices must both keep their vote.** A watch
    /// and a ring disagree by more than illness does; collapsing them would be
    /// far worse than the defect being fixed.
    func testTwoRealDevicesThatDisagreeBothSurvive() {
        let watch = MetricSource(id: "apple_health/watch", displayName: "Apple Watch")
        let kept = MultiSource.deduplicate([
            sample(44.2, source: .oura),
            sample(41.8, source: watch)
        ])
        XCTAssertEqual(kept.count, 2, "two instruments measuring differently are two observations")
    }

    /// Same value, different minutes, is two observations — not a mirror. A
    /// mirror copies the instant as well as the number.
    func testTheSameValueAtADifferentTimeIsNotAMirror() {
        let kept = MultiSource.deduplicate([
            sample(44.2, source: .oura, minutesAgo: 0),
            sample(44.2, source: mirror, minutesAgo: 90)
        ])
        XCTAssertEqual(kept.count, 2)
    }

    /// The daily mean is where the double vote did its damage: averaging a
    /// value with itself is a no-op, but averaging it with a *different*
    /// instrument's value and then counting the mirror again pulls the mean
    /// toward whichever instrument happens to be mirrored.
    func testTheDailyMeanIsNotDraggedByTheMirror() throws {
        let watch = MetricSource(id: "apple_health/watch", displayName: "Apple Watch")
        let withMirror = MultiSource.deduplicate([
            sample(44.0, source: .oura),
            sample(44.0, source: mirror),
            sample(38.0, source: watch)
        ])
        let values = withMirror.map(\.value).sorted()
        XCTAssertEqual(values, [38.0, 44.0],
                       "the mirrored copy is still in the pool, so 44 is weighted twice against the watch")
    }
}
