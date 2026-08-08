import Foundation

/// **A sitting, not a reading, is the unit of blood pressure in this app.**
///
/// Four readings taken one after another on a Sunday morning are *one*
/// observation of one person's blood pressure, not four. Everything downstream
/// that counts readings — the calibration count, the ± on the estimate, the
/// weight a day carries in a trend — is counting the wrong thing when it counts
/// them separately, and it is wrong in the flattering direction: **any ± derived
/// from a reading count is too narrow by roughly √n.** Cuffing four times in a
/// morning does not make the morning four times better known; it makes *that
/// morning* better known by a factor of two, and the app's confidence in the
/// person by nothing at all.
///
/// Measured on the reader's own export, 2026-08-08 (shapes only — no readings
/// are quoted here, see `docs/privacy-and-ip.md`):
///
/// - 52 systolic samples are really **42 distinct readings on 16 calendar days**
///   once the two duplication defects in `BloodPressureSittings.deduplicate` are
///   taken out.
/// - Those 42 fall into **20 sittings, 11 of them with more than one reading**.
/// - Pooled within-sitting SD is **9.6 mmHg**, so about **28%** of the
///   sitting-to-sitting variance in the record is the cuff rather than the
///   person. Within-sitting spreads of **21–30 mmHg** occur.
///
/// That last figure is the whole argument for this type existing. A card that
/// treats each reading as an independent observation of the reader is
/// attributing a quarter of its own noise to their physiology.
public struct BloodPressureSitting: Sendable, Equatable, Identifiable {

    /// One cuff reading inside a sitting.
    ///
    /// ⚠️ Deliberately **not** `Identifiable`: its date is not unique. Two
    /// readings sharing a timestamp to the second is the exact case `ordinal`
    /// exists to describe, and handing them the same `id` is how a SwiftUI
    /// `ForEach` silently drops one of them.
    public struct Entry: Sendable, Equatable {
        public let date: Date
        public let systolic: Double
        public let diastolic: Double
        /// The source's display name, exactly as `BloodPressureEstimator.Reading`
        /// carries it — so a sitting can say *"first two from the cuff, third via
        /// Apple Health"* without a second provenance vocabulary.
        public let source: String

        /// Which reading of the sitting this was: 1, 2, 3…
        ///
        /// ⚠️ **`nil` means the position is unknown, not that it is missing.**
        /// When two readings in a sitting share a timestamp to the second — which
        /// happens once in the reader's real record — nothing in the data says
        /// which came first, and a cuff's readings *drift downwards* across a
        /// sitting, so an invented order would be read as a physiological
        /// direction. The tie nils only the tied entries; unambiguous positions
        /// on either side of it keep their number.
        public let ordinal: Int?

        public init(date: Date, systolic: Double, diastolic: Double,
                    source: String, ordinal: Int? = nil) {
            self.date = date
            self.systolic = systolic
            self.diastolic = diastolic
            self.source = source
            self.ordinal = ordinal
        }
    }

    /// Oldest → newest, with `ordinal` recomputed by the initialiser so it can
    /// never disagree with the order it is stored in.
    public let entries: [Entry]

    /// The first entry's date.
    public let start: Date

    /// **The first entry's date, and that is the point.**
    ///
    /// `BloodPressureEstimator.Reading.id` is a fresh `UUID()` per call
    /// (`BloodPressureEstimator.swift:45`), so the same reading recomputed twice
    /// is two different identities — fine for a list rendered once, useless for
    /// anything that has to survive a recompute (selection, a chart's highlighted
    /// point, a dismissed disagreement warning). A sitting's start is a fact
    /// about the data, so it is stable by construction.
    public var id: Date { start }

    /// `nil` for an empty sitting: a sitting with no readings in it is not a
    /// thing this app has any use for, and every property below would have to
    /// invent a value for it.
    public init?(entries: [Entry]) {
        guard !entries.isEmpty else { return nil }
        // Fully-determined ordering, tie-broken on the values and then the
        // source, so two runs over the same data produce the same array. Swift's
        // `sort` is not stable, and a sitting whose entries reshuffle between
        // recomputes would make `id` stable and `entries[0]` not.
        let ordered = entries.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.systolic != b.systolic { return a.systolic < b.systolic }
            if a.diastolic != b.diastolic { return a.diastolic < b.diastolic }
            return a.source < b.source
        }
        var perSecond: [Int: Int] = [:]
        for entry in ordered { perSecond[BloodPressureSittings.second(entry.date), default: 0] += 1 }
        self.entries = ordered.enumerated().map { index, entry in
            let tied = (perSecond[BloodPressureSittings.second(entry.date)] ?? 0) > 1
            return Entry(date: entry.date, systolic: entry.systolic,
                         diastolic: entry.diastolic, source: entry.source,
                         ordinal: tied ? nil : index + 1)
        }
        self.start = ordered[0].date
    }

    public var count: Int { entries.count }

    /// The sitting's systolic — **the median, never the mean.**
    ///
    /// `Baseline.median` (`Baseline.swift:82`) has a 50% breakdown point;
    /// `Baseline.mean` (`Baseline.swift:10`) has none. In a two-reading sitting a
    /// single 30 mmHg outlier *is* half the sitting, and the mean hands it half
    /// the answer: 120 and 150 average to 135, a number neither cuff ever showed
    /// and a whole ACC/AHA band away from both. Sittings here run 2–4 readings,
    /// which is precisely the size at which one bad cuff placement dominates a
    /// mean and cannot move a median past its neighbour.
    public var systolic: Double {
        Baseline.median(entries.map(\.systolic)) ?? entries[0].systolic
    }

    public var diastolic: Double {
        Baseline.median(entries.map(\.diastolic)) ?? entries[0].diastolic
    }

    /// Widest systolic gap inside the sitting, in mmHg.
    ///
    /// **The number the reader sees, and it is never averaged away.** The median
    /// above is the app's best single answer; this is how much the cuff disagreed
    /// with itself while producing it, and the two must be shown together or the
    /// median reads as a precision the record does not support. Spreads of 21–30
    /// mmHg occur in the reader's own sittings.
    public var systolicSpread: Double {
        let values = entries.map(\.systolic)
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    /// Whether the sitting's own readings disagree by more than the distance
    /// between two clinical bands.
    ///
    /// **10 mmHg** because that is wider than every gap in the published ACC/AHA
    /// systolic ladder below crisis — normal→elevated is 120, elevated→stage 1 is
    /// 130, stage 1→stage 2 is 140 (`BloodPressureEstimator.Category.of`). A
    /// sitting spreading further than 10 contains readings that fall in different
    /// bands, so *which category the reader is in* depends on which of their own
    /// cuff readings you pick. That is a fact about the sitting worth saying out
    /// loud, not a fact to average.
    public static let disagreementThreshold: Double = 10

    public var disagreesWithItself: Bool { systolicSpread > Self.disagreementThreshold }

    /// How well this sitting pins the reader's blood pressure, in mmHg.
    ///
    /// `pooledWithinSD / √n` — the standard error of the sitting's centre. The √n
    /// is the entire point of the type: **a lone reading visibly carries the whole
    /// pooled SD**, four readings halve it, and no amount of cuffing in one
    /// morning drives it to zero, because the pooled SD is measured *within*
    /// sittings and says nothing about how much this morning differs from next
    /// Tuesday.
    ///
    /// Pass `BloodPressureSittings.pooledWithinSD(_:).sd` — and pass the reader's
    /// own learned figure where there is one, since 9.6 mmHg is this reader's
    /// cuff and not a constant of nature.
    public func standardError(pooledWithinSD: Double) -> Double {
        pooledWithinSD / Double(entries.count).squareRoot()
    }
}

/// Turning a pile of samples into sittings: **dedupe first, then cluster.**
public enum BloodPressureSittings {

    // MARK: - Clustering

    /// The gap that separates two sittings.
    ///
    /// ⚠️ **Measured, not picked.** On the reader's export the inter-reading gap
    /// distribution is cleanly bimodal: **22 gaps under 4 minutes, then nothing
    /// at all until 68 minutes.** There are no gaps in between to be wrong about,
    /// which is why **every threshold from 5 to 60 minutes yields the identical
    /// 20 sittings, 11 of them multi-reading**. 15 minutes sits in the middle of
    /// that plateau rather than at either edge of it, so this constant is a
    /// choice with no consequence — the honest kind of magic number.
    ///
    /// It is a `TimeInterval` parameter anyway, because the plateau is a property
    /// of *this* reader's cuffing habit and a reader who takes a reading every
    /// half hour would have a different one. A test pins the invariance across
    /// 5, 15 and 60 minutes so a future change that starts caring about the exact
    /// value fails loudly.
    public static let defaultWindow: TimeInterval = 15 * 60

    /// Every sitting in the record, **newest first** — matching
    /// `BloodPressureEstimator.pairedReadings`, so a list of sittings and a list
    /// of readings never scroll in opposite directions. Entries *within* a
    /// sitting run oldest → newest, so `ordinal` 1 is first.
    public static func sittings(from samples: [HealthMetricSample],
                                window: TimeInterval = defaultWindow) -> [BloodPressureSitting] {
        sittings(from: BloodPressureEstimator.pairedReadings(from: samples), window: window)
    }

    /// The same, from readings already paired.
    ///
    /// ⚠️ **Deduplicates again even though `pairedReadings` now does it too.**
    /// That is not redundancy worth removing: the sitting is the unit the reader
    /// is shown, a duplicate that reaches it doubles a sitting's `n` and
    /// therefore *narrows* `standardError` by √2 while widening `systolicSpread`
    /// by nothing — a confident-looking wrong answer. The pass is idempotent and
    /// costs one linear walk.
    public static func sittings(from readings: [BloodPressureEstimator.Reading],
                                window: TimeInterval = defaultWindow) -> [BloodPressureSitting] {
        // `deduplicate` returns oldest-first, which is the order clustering needs.
        let ordered = deduplicate(readings)
        var groups: [[BloodPressureEstimator.Reading]] = []
        for reading in ordered {
            // Measured against the *previous reading*, not the sitting's start:
            // the bimodal distribution above is a distribution of inter-reading
            // gaps, and anchoring on the start would split a slow six-reading
            // sitting in half at an arbitrary point.
            if let previous = groups.last?.last,
               reading.date.timeIntervalSince(previous.date) <= window {
                groups[groups.count - 1].append(reading)
            } else {
                groups.append([reading])
            }
        }
        return groups.compactMap { group in
            BloodPressureSitting(entries: group.map {
                .init(date: $0.date, systolic: $0.systolic,
                      diastolic: $0.diastolic, source: $0.source)
            })
        }
        .sorted { $0.start > $1.start }
    }

    // MARK: - Deduplication

    /// Two duplication defects, both live in the reader's record as of
    /// 2026-08-08, both silent, and neither one visible as an obviously wrong
    /// number anywhere on screen:
    ///
    /// 1. **One 2020-10-05 Withings reading appears ten times at an identical
    ///    timestamp.** Ten copies of one moment, counted ten times towards
    ///    calibration and drawn ten times on top of each other on the chart.
    /// 2. **A 2026-03-03 reading appears twice** — once as `apple_health/withings`
    ///    and once as `withings`. ⚠️ **This one recurs by construction**: it
    ///    happens to *every* reading whenever the direct Withings integration and
    ///    Apple Health sync are both switched on, which silently doubles the
    ///    weight of every Withings reading in the record.
    ///
    /// Returned **oldest first**, which is what clustering wants.
    ///
    /// The survivor of any collapse is chosen by provenance rather than by
    /// arrival order — see `prefers(_:over:)` — so the result does not depend on
    /// which integration happened to sync first.
    public static func deduplicate(_ readings: [BloodPressureEstimator.Reading])
        -> [BloodPressureEstimator.Reading] {
        let ordered = readings.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            if a.source != b.source { return prefers(a.source, over: b.source) }
            if a.systolic != b.systolic { return a.systolic < b.systolic }
            return a.diastolic < b.diastolic
        }

        var kept: [BloodPressureEstimator.Reading] = []
        var seen: Set<Key> = []
        for reading in ordered {
            // **Rule 1 — the same reading, byte for byte.** Source-blind on
            // purpose: defect 2's two copies differ *only* in their source
            // string, so a key that included it would preserve exactly the
            // duplicate it was written to remove.
            let key = Key(reading)
            if seen.contains(key) { continue }
            // **Rule 2 — the same reading down two paths.** Rule 1 already
            // catches the mirror when both paths carry identical numbers, which
            // is the usual case; this covers the one where a unit round-trip on
            // the way through has moved a value by under a millimetre of
            // mercury. It requires the sources to be *related* and the numbers to
            // agree, so two genuinely different readings that happen to share a
            // second both survive — which is the case `Entry.ordinal` describes.
            if isMirrorOfSomethingKept(reading, in: kept) { continue }
            seen.insert(key)
            kept.append(reading)
        }
        return kept
    }

    /// Whole seconds since the epoch. The finest resolution two integrations can
    /// be expected to agree on — Apple Health round-trips a date through a
    /// `Double`, and asking for equality below a second would let defect 2's
    /// mirror through on a floating-point hair.
    static func second(_ date: Date) -> Int { Int(date.timeIntervalSince1970.rounded()) }

    /// Rule 1's identity: whole seconds, whole mmHg, no source.
    ///
    /// Whole mmHg because cuffs report whole mmHg — every sub-unit difference in
    /// the record comes from a conversion on the way in, never from the
    /// instrument.
    private struct Key: Hashable {
        let second: Int
        let systolic: Int
        let diastolic: Int
        init(_ reading: BloodPressureEstimator.Reading) {
            self.second = BloodPressureSittings.second(reading.date)
            self.systolic = Int(reading.systolic.rounded())
            self.diastolic = Int(reading.diastolic.rounded())
        }
    }

    /// How far two copies of one reading may disagree and still be one reading,
    /// in mmHg. One: a cuff reports whole numbers, so anything at or under a
    /// single millimetre of mercury is the sync path's arithmetic rather than the
    /// instrument's. Two real readings from one sitting differ by far more —
    /// the pooled within-sitting SD is 9.6 mmHg.
    static let mirrorTolerance: Double = 1

    /// The shortest source name that may be matched as a prefix or suffix.
    ///
    /// ⚠️ Every string has `""` as a prefix, and a one- or two-character source
    /// id would relate to half the record. Three is the shortest real id in
    /// `MetricSource`.
    static let minimumSourceLength = 3

    private static func isMirrorOfSomethingKept(
        _ reading: BloodPressureEstimator.Reading,
        in kept: [BloodPressureEstimator.Reading]) -> Bool {
        // `kept` is time-ordered, so only the tail sharing this second can match.
        var index = kept.count - 1
        let target = second(reading.date)
        while index >= 0, second(kept[index].date) == target {
            let candidate = kept[index]
            if related(candidate.source, reading.source),
               abs(candidate.systolic - reading.systolic) <= mirrorTolerance,
               abs(candidate.diastolic - reading.diastolic) <= mirrorTolerance {
                return true
            }
            index -= 1
        }
        return false
    }

    /// Whether two source labels name the same path to the same instrument.
    ///
    /// One being a prefix or suffix of the other is what the duplication actually
    /// looks like, at both levels the app labels a source at: the ids
    /// `withings` and `apple_health/withings` (suffix), and the display names
    /// "Withings" and "Withings via Apple Health" (prefix) — `MetricSource`
    /// builds the second from the first in `appleHealthDevice(_:)`. So one rule
    /// covers both, and it keeps working if a caller hands over ids instead.
    ///
    /// ⚠️ It is deliberately *not* a containment test. "Withings via Apple
    /// Health" and "Omron via Apple Health" share a substring and are two
    /// different cuffs; neither is a prefix or a suffix of the other.
    static func related(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        guard x.count >= minimumSourceLength, y.count >= minimumSourceLength else { return false }
        return x == y || x.hasPrefix(y) || x.hasSuffix(y) || y.hasPrefix(x) || y.hasSuffix(x)
    }

    /// Which of two labels for one reading is kept.
    ///
    /// **The direct integration outranks the Apple Health mirror**, because the
    /// mirror is a copy of it — same instrument, one more hop, and the hop is
    /// where the timestamp and the rounding get touched. Length then alphabet
    /// break the remaining ties, so the answer never depends on sync order.
    static func prefers(_ a: String, over b: String) -> Bool {
        let aMirror = isAppleHealthMirror(a), bMirror = isAppleHealthMirror(b)
        if aMirror != bMirror { return !aMirror }
        if a.count != b.count { return a.count < b.count }
        return a < b
    }

    /// Matches both the id form (`apple_health/…`) and the display form
    /// (`… via Apple Health`) that `MetricSource.appleHealthDevice(_:)` produces.
    static func isAppleHealthMirror(_ source: String) -> Bool {
        let n = source.lowercased()
        return n.contains("apple health") || n.contains("apple_health")
    }

    // MARK: - Pooled within-sitting spread

    /// The ± to use when the record cannot supply one, in mmHg.
    ///
    /// **8, and deliberately conservative rather than accurate.** It is below the
    /// 9.6 mmHg this reader's own sittings show, so a reader with fewer than
    /// three multi-reading sittings is not handed a *wider* error bar than the
    /// data would eventually justify — but it is well above the ISO 81060-2
    /// validation limit of ±5 mmHg (`BloodPressureEstimator.Drift.isoMeanErrorLimit`),
    /// because that limit describes a monitor against a reference in a clinic,
    /// not the same person cuffing themselves twice on a sofa.
    ///
    /// This is what `Drift.uncertaintyFloor(pooledWithinSD:readings:)` divides by
    /// √n when the reader has not yet cuffed twice in a sitting often enough to
    /// have taught the app their own figure.
    public static let fallbackWithinSD: Double = 8

    /// Multi-reading sittings needed before the reader's own figure is trusted.
    ///
    /// Three, because a pooled SD from one or two sittings is a statement about
    /// one or two mornings. The reader has 11.
    public static let minimumSittingsToLearn = 3

    /// The reader's own within-sitting spread, pooled across every sitting that
    /// has more than one reading in it — **and whether it was actually learned.**
    ///
    /// ⚠️ **`learned` is not a detail.** A card printing "±8" from the fallback
    /// and a card printing "±9.6" from this reader's own eleven sittings look
    /// identical on screen and mean completely different things; without this
    /// flag the UI has no way to say *"this is a default, cuff twice in a sitting
    /// and the app will learn yours"*. `BloodPressureEstimator` has been bitten by
    /// exactly this shape before — see `statedUncertainty`, where two different
    /// ± values reached one screen with nothing to distinguish them.
    ///
    /// Pooled by degrees of freedom — `√(Σ(nᵢ−1)sᵢ² / Σ(nᵢ−1))` — so a
    /// four-reading sitting counts for three times as much as a two-reading one,
    /// which is what "pooled" means and is why a single 30 mmHg sitting cannot
    /// speak for the record on its own.
    ///
    /// ⚠️ **Classical `Baseline.standardDeviation` here, not `Baseline.robustScale`,
    /// and that is a decision rather than an oversight.** `robustScale`
    /// (`Baseline.swift:117`) exists to stop an excursion inflating a spread that
    /// something else is being judged against. Inside a sitting there is nothing
    /// to be robust *against*: the spread **is** the quantity being measured, and
    /// a 50%-breakdown estimator would quietly discard the 21–30 mmHg sittings
    /// that are the entire evidence for this number being 9.6 rather than 5. The
    /// robustness this type needs is in `BloodPressureSitting.systolic`, where the
    /// median keeps one bad cuff placement out of the *answer* — a different
    /// question, given the two estimators, exactly as `Baseline.deviation`
    /// documents.
    public static func pooledWithinSD(_ sittings: [BloodPressureSitting])
        -> (sd: Double, learned: Bool) {
        let multi = sittings.filter { $0.entries.count >= 2 }
        guard multi.count >= minimumSittingsToLearn else { return (fallbackWithinSD, false) }
        var weightedVariance = 0.0
        var degreesOfFreedom = 0.0
        for sitting in multi {
            guard let sd = Baseline.standardDeviation(sitting.entries.map(\.systolic)) else { continue }
            let dof = Double(sitting.entries.count - 1)
            weightedVariance += dof * sd * sd
            degreesOfFreedom += dof
        }
        guard degreesOfFreedom > 0 else { return (fallbackWithinSD, false) }
        let pooled = (weightedVariance / degreesOfFreedom).squareRoot()
        // ⚠️ Exactly zero means every multi-reading sitting repeated itself to
        // the millimetre, which is a cuff replaying its last reading rather than
        // evidence of a perfect one. Dividing by it in `standardError` would
        // claim a sitting known without error.
        guard pooled > 0 else { return (fallbackWithinSD, false) }
        return (pooled, true)
    }
}
