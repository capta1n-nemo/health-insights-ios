import SwiftUI
import InsightKit

/// The "what would ever leave my phone" screen. Sharing is **off by default** and
/// nothing is transmitted at all in this build — this view exists so the model-
/// improvement pipeline is fully inspectable before any network step is added.
struct TelemetryOutboxView: View {
    @Environment(AppModel.self) private var model

    private var optIn: Binding<Bool> {
        Binding(get: { model.telemetryOptIn }, set: { model.telemetryOptIn = $0 })
    }

    var body: some View {
        List {
            Section {
                Toggle("Share anonymous model-improvement data", isOn: optIn)
            } footer: {
                Text("Off by default. Even when on, **nothing is transmitted in this build** — the network step isn't built yet. This screen shows exactly what *would* be sent.")
            }

            Section("What would be shared") {
                bullet("A broad group (e.g. male · 30–39 · low-risk region) — never your identity.")
                bullet("The model version and how far off it was, as a rounded percentage with random noise added.")
                bullet("A coarse week, and thumbs up/down ratings.")
            }
            Section("What is never shared") {
                bullet("Your name, device, or any identifier.")
                bullet("Any raw reading — heart rate, blood pressure, weight, sleep, substances.")
                bullet("Your exact age or date — only a 10-year band.")
            }

            let events = model.telemetryOutbox()
            Section {
                if events.isEmpty {
                    Text("Nothing yet. As you log real readings (e.g. a cuff blood pressure after an estimate) and rate insights, anonymised error metrics will collect here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                        eventRow(e)
                    }
                }
            } header: {
                Text("Preview: \(events.count) item\(events.count == 1 ? "" : "s") that would be sent")
            } footer: {
                Text("Transmission is disabled — these never leave your phone.")
            }
        }
        .navigationTitle("Data & model improvement")
        .navigationBarTitleDisplayMode(.inline)
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
            }
        } ?? raw
    }
}
