import Foundation
import InsightKit

/// The result of syncing a source: canonical samples we model as insights, plus
/// "other" raw samples we imported but don't yet model (new HealthKit types,
/// extra provider fields, future nutrition/medication/environment data). Keeping
/// both lets us store everything now and wire more into insights later.
struct SyncedData {
    var samples: [HealthMetricSample] = []
    var other: [RawMetricSample] = []

    init(samples: [HealthMetricSample] = [], other: [RawMetricSample] = []) {
        self.samples = samples
        self.other = other
    }

    mutating func append(_ o: SyncedData) {
        samples += o.samples
        other += o.other
    }
}
