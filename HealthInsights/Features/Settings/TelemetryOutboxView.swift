import SwiftUI
import InsightKit

/// **The "what would ever leave my phone" screen.**
///
/// ⚠️ **Nothing is transmitted in this build.** There is no endpoint, no upload
/// and no networking behind any switch on this screen. It exists ahead of any
/// transmission on purpose: the shape of what would leave has to be inspectable,
/// testable and switchable *before* anything can go, or the first send is also
/// the first time anybody looks at it.
///
/// It shows two separate things, and conflating them is the mistake
/// `docs/norms-and-telemetry.md` warns about:
///
/// 1. **Accuracy telemetry** — a coarse cohort and a DP-noised error percentage,
///    carrying no values at all. Answers *"is the model getting better?"*. Its
///    switch is **off by default** and always has been.
/// 2. **Your corrections** — what the app guessed, what you said, and the item
///    it judged. Answers *"why was the model wrong?"*, and it needs the content
///    to answer it. Backlog B8 R5: two tiers, **both on by default at the
///    reader's explicit instruction**, each switchable off.
///
/// The worked examples below are built by the real shaping code
/// (`SharingExample`), not written by hand, so what this screen promises cannot
/// drift from what the app would actually do.
struct TelemetryOutboxView: View {
    @Environment(AppModel.self) private var model

    private var optIn: Binding<Bool> {
        Binding(get: { model.telemetryOptIn }, set: { model.telemetryOptIn = $0 })
    }

    private func tierBinding(_ tier: SharingTier) -> Binding<Bool> {
        Binding(get: { model.sharingPreferences.isEnabled(tier) },
                set: { enabled in
                    var updated = model.sharingPreferences
                    updated.setEnabled(enabled, for: tier)
                    model.sharingPreferences = updated
                })
    }

    var body: some View {
        List {
            Section {
                Text("Nothing is sent anywhere in this build — there is no server to send it to. These switches decide the **shape** of what would be shared once there is one, and everything below is the real thing, built by the same code that would build the payload.")
                    .font(.subheadline)
            }

            sharingTiers
            ForEach(SharingTier.allCases) { workedExample(for: $0) }
            correctionPreview
            accuracyTelemetry
            outboxPreview
        }
        .navigationTitle("Data & model improvement")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The two tiers

    private var sharingTiers: some View {
        Section {
            ForEach(SharingTier.allCases) { tier in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(tier.title, isOn: tierBinding(tier))
                    Text(tier.summary)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Sharing your corrections")
        } footer: {
            Text(model.sharingPreferences.sharesNothing
                 ? "Both are off, so no correction of yours would be shared at all — not even its shape."
                 : "Both start on. Turn either off and it stays off. **Full** includes **Metadata only**, so with both on, a correction would go out in full.")
        }
    }

    /// One tier, shown as the actual record it produces.
    private func workedExample(for tier: SharingTier) -> some View {
        Section {
            recordRow(SharingExample.calendarCorrection(under: tier))
            recordRow(SharingExample.estimateCorrection(under: tier))
        } header: {
            Text("\(tier.title) — an example")
        } footer: {
            Text(tier == .full
                 ? "A made-up meeting and a made-up reading, not yours. Under Full, the event's own words and the value you measured go with the correction — that is what makes it possible to work out *why* the app got it wrong."
                 : "The same two corrections with every word and every reading removed. What is left is the shape: how long, how many, which way the guess was wrong, and by how much. **A difference, never a value** — nobody holding this could work out what your blood pressure was.")
        }
    }

    /// A shared record, exactly as it would go: the sentence, then every field
    /// it carries.
    private func recordRow(_ record: SharedRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.summary).font(.subheadline)
            if !record.changes.isEmpty {
                ForEach(record.changes, id: \.axis) { change in
                    HStack(spacing: 6) {
                        Text(change.axisLabel.capitalized)
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(change.from) → \(change.to)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            if record.fields.isEmpty {
                Text("No further detail is attached.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(record.fields, id: \.name) { field in
                    HStack(alignment: .top) {
                        Text(field.label).font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        // Amber marks anything about *you* rather than about
                        // the model — your words, or a reading off your body.
                        // The reader should be able to see at a glance which
                        // rows the metadata tier would remove.
                        Text(field.value.display)
                            .font(.caption2.monospaced())
                            .foregroundStyle(field.value.isContent ? Theme.warn : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if record.content.isEmpty {
                    Label("Nothing here is about you — only about the model",
                          systemImage: "checkmark.shield")
                        .font(.caption2).foregroundStyle(Theme.good)
                } else {
                    Label("\(record.content.count) field\(record.content.count == 1 ? "" : "s") about you: \(record.freeText.count) in your words, \(record.readings.count) measured",
                          systemImage: "text.quote")
                        .font(.caption2).foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// What is actually sitting here right now, under the tier in force.
    private var correctionPreview: some View {
        let records = model.correctionOutbox()
        return Section {
            if model.sharingPreferences.sharesNothing {
                Text("Both tiers are off, so nothing of yours is queued.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if records.isEmpty {
                Text("Nothing yet. Corrections collect here as you confirm or correct what the app worked out about a calendar event, and as you log a real reading after the app estimated one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                    recordRow(record)
                }
            }
        } header: {
            Text("Your corrections: \(records.count) item\(records.count == 1 ? "" : "s")")
        } footer: {
            Text("Your own corrections, shaped by the tier above. **None of this is transmitted** — the network step does not exist.")
        }
    }

    // MARK: - The older, narrower stream

    private var accuracyTelemetry: some View {
        Group {
            Section {
                Toggle("Share anonymous accuracy data", isOn: optIn)
            } header: {
                Text("Accuracy telemetry")
            } footer: {
                Text("A separate, much narrower stream: a broad group and how far off the model was, with no values and no words in it at all. **Off by default**, and unchanged by the switches above — it answers whether the model is improving, which is a different question from why it was wrong.")
            }

            Section("What it would share") {
                bullet("A broad group (e.g. male · 30–39 · low-risk region) — never your identity.")
                bullet("The model version and how far off it was, as a rounded percentage with random noise added.")
                bullet("A coarse week, and thumbs up/down ratings.")
            }
            Section("What it never shares") {
                bullet("Your name, device, or any identifier.")
                bullet("Any raw reading — heart rate, blood pressure, weight, sleep, substances.")
                bullet("Your exact age or date — only a 10-year band.")
            }
        }
    }

    private var outboxPreview: some View {
        let events = model.telemetryOutbox()
        return Section {
            if events.isEmpty {
                Text("Nothing yet. As you log real readings (e.g. a cuff blood pressure after an estimate) and rate insights, anonymised error metrics will collect here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                    eventRow(e)
                }
            }
        } header: {
            Text("Accuracy preview: \(events.count) item\(events.count == 1 ? "" : "s")")
        } footer: {
            Text("Transmission is disabled — nothing on this screen has left your phone.")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6)
                .foregroundStyle(Theme.accent)
            Text(text).font(.subheadline)
        }
    }

    private func eventRow(_ e: TelemetryEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(prettyInsight(e.insightID)).font(.subheadline.weight(.semibold))
                Spacer()
                if let err = e.signedErrorPercent {
                    Text(String(format: "%+.0f%% error", err)).monospacedDigit()
                        .font(.caption).foregroundStyle(.secondary)
                } else if let rating = e.rating {
                    Image(systemName: rating == "accurate" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(rating == "accurate" ? Theme.good : Theme.warn)
                }
            }
            Text("\(e.sex) · \(e.ageBand) · \(e.ethnicity) · \(e.region)")
                .font(.caption2).foregroundStyle(.secondary)
            Text(e.modelVersion).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func prettyInsight(_ raw: String) -> String {
        InsightID(rawValue: raw).map { id in
            switch id {
            case .readiness: return "Readiness"
            case .sleep: return "Sleep"
            case .energy: return "Energy"
            case .substanceImpact: return "Substance impact"
            case .nutrition: return "Nutrition"
            case .metabolism: return "Metabolism"
            case .heartHealth: return "Heart health"
            case .fitness: return "Fitness"
            case .cardiovascularRisk: return "Heart attack & stroke risk"
            case .bloodPressure: return "Blood pressure"
            case .bodyComposition: return "Body composition"
            case .symptomRadar: return "Symptom radar"
            case .sustainedLoad: return "Stress load"
            case .gait: return "How you walked"
            case .biologicalAge: return "Biological age"
            case .mentalHealth: return "Mental health"
            case .workImpact: return "Work impact"
            case .travelDrain: return "Travel drain"
            case .socialBattery: return "Social battery"
            case .soundExposure: return "Sound you took on"
            }
        } ?? raw
    }
}
