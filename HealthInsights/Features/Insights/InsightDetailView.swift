import SwiftUI
import Charts
import InsightKit

struct InsightDetailView: View {
    let insightID: InsightID
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?

    private var result: InsightResult? { model.result(for: insightID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let result {
                    headerCard(result)
                    if !result.unmetRequirements.isEmpty {
                        requirementsCard(result)
                    }
                    if !result.drivers.isEmpty {
                        driversCard(result)
                    }
                    if insightID == .bloodPressure {
                        bloodPressureLogLink
                    }
                    trendCard
                    disclaimerCard
                } else {
                    ContentUnavailableView("Not available", systemImage: "questionmark")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(result?.title ?? "Insight")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $groundingKind) { GroundingSheet(kind: $0) }
    }

    private func headerCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let score = result.score {
                        ScoreDial(score: score, label: result.headline, size: 96)
                    } else {
                        VStack(alignment: .leading) {
                            Text(result.headline).font(.largeTitle.weight(.bold))
                        }
                    }
                    Spacer()
                    ConfidenceBadge(confidence: result.confidence)
                }
                Text(result.explanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requirementsCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Add these for a better estimate", systemImage: "exclamationmark.circle")
                    .font(.headline)
                ForEach(result.unmetRequirements) { req in
                    Button { groundingKind = req.kind } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(req.kind.displayName).font(.subheadline)
                                Text(req.rationale).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func driversCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's driving this").font(.headline)
                ForEach(result.drivers, id: \.self) { d in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6)
                            .foregroundStyle(Theme.accent)
                        Text(d).font(.subheadline)
                    }
                }
            }
        }
    }

    @ViewBuilder private var trendCard: some View {
        let metric = primaryMetric
        let breakdown = model.breakdown(metric)
        if !breakdown.sources.isEmpty {
            NavigationLink {
                MetricDetailView(metric: metric)
            } label: {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(metric.displayName).font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        MultiSourceChart(breakdown: breakdown, window: 2 * 24 * 3600)
                        SourceBreakdown(breakdown: breakdown)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var bloodPressureLogLink: some View {
        NavigationLink {
            BloodPressureLogView()
        } label: {
            Card {
                HStack {
                    Image(systemName: "list.bullet.rectangle").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("View & add readings").font(.subheadline.weight(.semibold))
                        Text("Log cuff readings with dates — the estimate needs a few")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var disclaimerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("These insights are for information only and are not a medical diagnosis or advice. Talk to a clinician about any health decisions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var primaryMetric: MetricType {
        switch insightID {
        case .cardiovascularRisk: return .bloodPressureSystolic
        case .heartHealth: return .restingHeartRate
        case .bloodPressure: return .bloodPressureSystolic
        case .readiness: return .heartRateVariabilityRMSSD
        case .substanceImpact: return .restingHeartRate
        }
    }
}
