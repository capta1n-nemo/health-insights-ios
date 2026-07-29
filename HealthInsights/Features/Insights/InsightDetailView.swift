import SwiftUI
import Charts
import InsightKit

struct InsightDetailView: View {
    let insightID: InsightID
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var feedbackGiven = false
    @State private var timeframe: Timeframe = .month

    private var window: TimeInterval { timeframe.window ?? 60 * 60 * 24 * 366 * 12 }

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
                    feedbackCard(result)
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
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.displayName).font(.headline)
                    Picker("Timeframe", selection: $timeframe) {
                        ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    MultiSourceChart(breakdown: breakdown, window: window)
                    SourceBreakdown(breakdown: breakdown)
                    NavigationLink {
                        MetricDetailView(metric: metric)
                    } label: {
                        HStack {
                            Text("Open full history").font(.caption)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
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

    // Discreet, only-in-detail feedback loop: rate accuracy and (optionally)
    // enter the real value, which trains/refines the model over time.
    @ViewBuilder private func feedbackCard(_ result: InsightResult) -> some View {
        if result.primaryValue != nil {
            Card {
                if feedbackGiven {
                    Label("Thanks — this helps improve the model over time.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.good)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Was this accurate?").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Button {
                                model.recordFeedback(insightID, accurate: true); feedbackGiven = true
                            } label: { Label("Accurate", systemImage: "hand.thumbsup") }
                            Button {
                                model.recordFeedback(insightID, accurate: false); feedbackGiven = true
                            } label: { Label("Not accurate", systemImage: "hand.thumbsdown") }
                        }
                        .font(.caption).buttonStyle(.bordered)

                        if let kind = groundingPromptKind(result) {
                            Button {
                                groundingKind = kind
                            } label: {
                                Text("Have the real number? Enter it →")
                                    .font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which "real value" to invite for this insight (its first unmet input, or a
    /// cuff reading for blood pressure).
    private func groundingPromptKind(_ result: InsightResult) -> GroundingKind? {
        if let first = result.unmetRequirements.first { return first.kind }
        return insightID == .bloodPressure ? .cuffSystolic : nil
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
        case .sleepQuality: return .sleepDurationHours
        case .cardioFitness: return .vo2Max
        case .bodyComposition: return .bodyMass
        case .restingHeartRateTrend: return .restingHeartRate
        }
    }
}
