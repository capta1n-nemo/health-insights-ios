import Foundation

/// Creative use of partial data: several wearables (Oura, Hume) only report a
/// nightly *skin-temperature deviation* from your personal baseline — e.g.
/// "+0.3 °C" — not an absolute number. On its own that is hard to read on a
/// chart, and it cannot be compared against a device that does report absolutes.
///
/// This reconstructs an absolute value by adding the deviation to a personal
/// baseline, so the app can hold a real skin-temperature series.
///
/// ## The output is `.skinTemperature`, and that matters
///
/// It used to be written as `.bodyTemperature` — an absolute *core* metric —
/// which erased the fact that it was skin-derived, after which no consumer could
/// tell the two apart. Five things went wrong, all from that one loss of
/// provenance:
///
/// 1. Vitals Check's `bodyTemperature` lower bound was 35.5 °C, *exactly*
///    `defaultBaselineCelsius`, so `value < hardLow` reduced to `deviation < 0`
///    and every cool night read "below the usual healthy range".
/// 2. Its upper bound needed a +2.3 °C deviation, half again beyond what the app
///    itself calls the outer edge of plausible, so a real febrile night was
///    invisible.
/// 3. The reconstruction is *added* to the samples, and a constant shift shifts
///    the mean without touching the spread — so the deviation and its
///    reconstruction carried identical z-scores and one signal was penalised
///    twice.
/// 4. Baselines were learned from core absolutes, so a user with a thermometer
///    reading had skin deviations added to a *core* baseline.
/// 5. Worst: the reconstructed series competed with a real thermometer for the
///    same metric, and `primary(from:)` picks the source with the most history —
///    so a wearable's long run of nights displaced a genuine 38.5 °C fever and
///    the card read "All normal".
///
/// The baseline is learned from absolute *skin* readings the user has (Whoop,
/// Withings type 73, Apple's sleeping wrist temperature) and otherwise falls
/// back to a resting skin-temperature default.
public enum TemperatureReconstructor {

    /// Typical resting *skin* temperature baseline (°C) when nothing better is
    /// known. Skin runs cooler than the 37 °C core figure.
    public static let defaultBaselineCelsius = 35.5

    /// Learn a personal baseline from absolute *skin*-temperature samples, if any.
    ///
    /// Deliberately not `.bodyTemperature`: adding a skin deviation to a core
    /// baseline produces a number that is neither, and a user with one
    /// thermometer reading would have every night of ring data shifted a degree
    /// and a half too warm.
    public static func baseline(from samples: [HealthMetricSample]) -> Double {
        let absolutes = samples.samples(of: .skinTemperature).map(\.value)
        return Baseline.mean(absolutes) ?? defaultBaselineCelsius
    }

    /// Turn each skin-temperature *deviation* sample into an absolute
    /// `skinTemperature` sample by adding the learned baseline.
    ///
    /// Every deviation is mapped; nothing is skipped. That is safe because the
    /// result is a derived series in its own metric, and `VitalSignsCheck`
    /// deliberately declines to score it alongside the deviation it came from
    /// (see `Spec.supersededBy`) rather than counting one signal twice.
    public static func reconstruct(from samples: [HealthMetricSample]) -> [HealthMetricSample] {
        let deviations = samples.samples(of: .skinTemperatureDeviation)
        guard !deviations.isEmpty else { return [] }
        let base = baseline(from: samples)

        return deviations.map { dev in
            HealthMetricSample(
                type: .skinTemperature,
                value: base + dev.value,
                start: dev.start,
                end: dev.end,
                source: dev.source
            )
        }
    }

    /// Convenience: samples with reconstructed absolute skin temperatures merged
    /// in. Core `bodyTemperature` readings are never touched.
    public static func withReconstructedTemperature(_ samples: [HealthMetricSample]) -> [HealthMetricSample] {
        samples + reconstruct(from: samples)
    }
}
