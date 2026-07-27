import Foundation

/// Creative use of partial data: several wearables (Oura, Whoop, Hume) only
/// report a nightly *skin-temperature deviation* from your personal baseline —
/// e.g. "+0.3 °C" — not an absolute number. On its own that's hard to reason
/// about and can't be written back into Apple Health as a temperature.
///
/// This reconstructs an absolute value by adding the deviation to a personal
/// baseline, so the app (and Apple Health) can hold a real temperature series.
/// The baseline is learned from any absolute readings the user does have, and
/// otherwise falls back to a sensible resting skin-temperature default.
public enum TemperatureReconstructor {

    /// Typical resting *skin* temperature baseline (°C) when nothing better is
    /// known. Skin runs cooler than the 37 °C core figure.
    public static let defaultBaselineCelsius = 35.5

    /// Learn a personal baseline from absolute body-temperature samples, if any.
    public static func baseline(from samples: [HealthMetricSample]) -> Double {
        let absolutes = samples.samples(of: .bodyTemperature).map(\.value)
        return Baseline.mean(absolutes) ?? defaultBaselineCelsius
    }

    /// Turn each skin-temperature *deviation* sample into an absolute
    /// `bodyTemperature` sample by adding the learned baseline. Deviation samples
    /// that already coincide with an absolute reading are skipped so we don't
    /// double-count.
    public static func reconstruct(from samples: [HealthMetricSample]) -> [HealthMetricSample] {
        let deviations = samples.samples(of: .skinTemperatureDeviation)
        guard !deviations.isEmpty else { return [] }
        let base = baseline(from: samples)

        return deviations.map { dev in
            HealthMetricSample(
                type: .bodyTemperature,
                value: base + dev.value,
                start: dev.start,
                end: dev.end,
                source: dev.source
            )
        }
    }

    /// Convenience: samples with reconstructed absolute temperatures merged in.
    public static func withReconstructedTemperature(_ samples: [HealthMetricSample]) -> [HealthMetricSample] {
        samples + reconstruct(from: samples)
    }
}
