import Foundation
import InsightKit

/// The result of syncing a source: canonical samples we model as insights, plus
/// "other" raw samples we imported but don't yet model (new HealthKit types,
/// extra provider fields, future nutrition/medication/environment data). Keeping
/// both lets us store everything now and wire more into insights later.
struct SyncedData {
    var samples: [HealthMetricSample] = []
    var other: [RawMetricSample] = []
    /// Unparsed provider responses, handed to `IngestionPipeline` before
    /// insights run. A provider's job is to fetch bytes and normalise the
    /// handful of fields it has unit knowledge about; deciding what *else* the
    /// payload contained is the pipeline's, so a field the provider has never
    /// heard of still reaches the vitals layer.
    var payloads: [IngestPayload] = []

    init(samples: [HealthMetricSample] = [],
         other: [RawMetricSample] = [],
         payloads: [IngestPayload] = []) {
        self.samples = samples
        self.other = other
        self.payloads = payloads
    }

    mutating func append(_ o: SyncedData) {
        samples += o.samples
        other += o.other
        payloads += o.payloads
    }
}
