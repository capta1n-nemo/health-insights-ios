import SwiftUI
import InsightKit

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    summaryCard
                    if !model.outstandingGrounding.isEmpty {
                        GroundingPromptBanner(items: model.outstandingGrounding) { kind in
                            groundingKind = kind
                        }
                    }
                    ForEach(model.results, id: \.id) { result in
                        NavigationLink {
                            InsightDetailView(insightID: result.id)
                        } label: {
                            InsightCard(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .refreshable { await model.refresh() }
            .sheet(item: $groundingKind) { kind in
                GroundingEntryView(kind: kind)
            }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Your snapshot").font(.headline)
                    Spacer()
                    if model.isSyncing { ProgressView() }
                }
                Text(model.todaySummary.isEmpty
                     ? "Pull to refresh to generate today's summary."
                     : model.todaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A dashboard tile for one insight: dial or big headline + a driver line.
struct InsightCard: View {
    let result: InsightResult

    var body: some View {
        Card {
            HStack(spacing: 16) {
                if let score = result.score {
                    ScoreDial(score: score, size: 72)
                } else {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.12)).frame(width: 72, height: 72)
                        Image(systemName: iconName).foregroundStyle(Theme.accent).font(.title2)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(result.title).font(.headline)
                        Spacer()
                        ConfidenceBadge(confidence: result.confidence)
                    }
                    Text(result.headline).font(.title3.weight(.semibold))
                    if let first = result.drivers.first {
                        Text(first).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else if !result.unmetRequirements.isEmpty {
                        Text("Tap to add the details needed")
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var iconName: String {
        switch result.id {
        case .cardiovascularRisk: return "waveform.path.ecg"
        case .heartHealth: return "heart.fill"
        case .bloodPressure: return "gauge.medium"
        }
    }
}
