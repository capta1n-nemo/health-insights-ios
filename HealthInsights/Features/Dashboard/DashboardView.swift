import SwiftUI
import InsightKit

/// The Today tab: scoped to right now — last night's sleep/readiness, today's
/// vitals, prompts, and the "daily" insight cards. Longer-horizon analysis lives
/// on the Insights tab.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var showSubstanceLog = false

    private var dailyResults: [InsightResult] {
        model.results.filter { $0.id.cadence == .daily && $0.primaryValue != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    summaryCard
                    suggestionCard
                    LastNightCard()
                    VitalsGlance()
                    if !model.outstandingGrounding.isEmpty {
                        GroundingPromptBanner(items: model.outstandingGrounding) { kind in
                            groundingKind = kind
                        }
                    }
                    ForEach(dailyResults, id: \.id) { result in
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSubstanceLog = true
                    } label: {
                        Label("Log", systemImage: "plus.circle")
                    }
                }
            }
            .sheet(item: $groundingKind) { kind in
                GroundingSheet(kind: kind)
            }
            .sheet(isPresented: $showSubstanceLog) {
                SubstanceLogView()
            }
        }
    }

    /// The single best-founded suggestion, dismissible.
    ///
    /// Today had no suggestions at all — the engine shipped and this surface was
    /// never built, so the only place to see them was a tab you had to go
    /// looking for. One, not five: Today is a glance and the ranking already
    /// says which one is best-founded.
    ///
    /// Dismissing is safe rather than destructive because the full list lives on
    /// Insights and keeps what you waved away. It comes back here when a *new*
    /// finding appears — a new finding has a new id, so it was never dismissed —
    /// or after thirty days, whichever is first. See `SuggestionVisibility`.
    @ViewBuilder private var suggestionCard: some View {
        if let suggestion = model.suggestionVisibility.today.first {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.circle")
                            .foregroundStyle(Theme.accent)
                        Text(suggestion.title).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button {
                            model.dismissSuggestion(id: suggestion.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss this suggestion")
                    }
                    Text(suggestion.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let insight = suggestion.insight {
                        NavigationLink {
                            InsightDetailView(insightID: insight)
                        } label: {
                            Text("See the card").font(.caption.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                    Text(greeting).font(.headline)
                    Spacer()
                    if model.isSyncing { ProgressView() }
                }
                Text(model.todaySummary.isEmpty
                     ? "Pull to refresh to generate today's summary."
                     : model.todaySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Says when the data last moved. A pull-to-refresh inside the
                // thirty-second floor returns without syncing, and a gesture that
                // appears to do nothing reads as a bug — this is what makes it
                // read as "already up to date" instead.
                if let refreshed = model.lastRefreshedAt, !model.isSyncing {
                    Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Your snapshot"
        }
    }
}

/// Oura-style "last night" summary shown on Today: previous night's sleep and
/// this morning's readiness. Only appears once there's something to show.
struct LastNightCard: View {
    @Environment(AppModel.self) private var model

    private var sleepHours: Double? { model.latest(.sleepDurationHours) }
    private var readiness: InsightResult? {
        model.results.first { $0.id == .readiness && $0.score != nil }
    }

    var body: some View {
        if sleepHours != nil || readiness != nil {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Last night", systemImage: "moon.stars.fill")
                        .font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        if let s = sleepHours {
                            stat(value: String(format: "%.1f h", s), label: "Sleep",
                                 icon: "bed.double.fill")
                        }
                        if let r = readiness, let score = r.score {
                            stat(value: "\(Int(score.rounded()))", label: "Readiness · \(r.headline)",
                                 icon: "bolt.heart.fill")
                        }
                        if let hrv = model.latest(.heartRateVariabilityRMSSD) ?? model.latest(.heartRateVariabilitySDNN) {
                            stat(value: "\(Int(hrv.rounded())) ms", label: "HRV", icon: "waveform.path.ecg")
                        }
                    }
                }
            }
        }
    }

    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.accent).font(.callout)
            Text(value).font(.title3.weight(.semibold))
                .minimumScaleFactor(0.8).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
    }
}

/// A compact, horizontally-scrolling row of the user's latest vitals — a quick
/// glance, Apple Health / Oura style. Only shows metrics that actually have data.
struct VitalsGlance: View {
    @Environment(AppModel.self) private var model

    private struct Vital: Identifiable {
        let id = UUID()
        let metric: MetricType
        let icon: String
        let value: Double
    }

    private var vitals: [Vital] {
        let specs: [(MetricType, String)] = [
            (.restingHeartRate, "heart"),
            (.heartRateVariabilityRMSSD, "waveform.path.ecg"),
            (.heartRateVariabilitySDNN, "waveform.path.ecg"),
            (.vo2Max, "figure.run"),
            (.bodyMass, "scalemass"),
            (.sleepDurationHours, "bed.double")
        ]
        var seen = Set<MetricType>()
        var out: [Vital] = []
        for (metric, icon) in specs where !seen.contains(metric) {
            if let value = model.latest(metric) {
                out.append(Vital(metric: metric, icon: icon, value: value))
                seen.insert(metric)
                // Only one HRV tile, whichever source is present.
                if metric == .heartRateVariabilityRMSSD { seen.insert(.heartRateVariabilitySDNN) }
            }
        }
        return out
    }

    var body: some View {
        let items = vitals
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { vital in
                        NavigationLink {
                            MetricDetailView(metric: vital.metric)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: vital.icon)
                                    .foregroundStyle(Theme.accent)
                                Text(formatted(vital))
                                    .font(.title3.weight(.semibold))
                                    .contentTransition(.numericText())
                                Text(vital.metric.displayName)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 108, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func formatted(_ vital: Vital) -> String {
        switch vital.metric {
        case .bodyMass: return String(format: "%.1f kg", vital.value)
        case .sleepDurationHours: return String(format: "%.1f h", vital.value)
        case .vo2Max: return String(format: "%.0f", vital.value)
        default: return "\(Int(vital.value.rounded())) \(vital.metric.unit)"
        }
    }
}

/// A dashboard tile for one insight: dial or big headline + a driver line.
struct InsightCard: View {
    @Environment(AppModel.self) private var model
    let result: InsightResult

    /// Silent unless the score has moved past its own usual spread — see
    /// `ScoreChangeChip`.
    private var change: ScoreChange? { model.scoreChange(for: result.id) }

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
                    HStack(spacing: 6) {
                        Text(result.headline).font(.title3.weight(.semibold))
                        if let change, change.isMeaningful {
                            ScoreChangeChip(change: change)
                        }
                    }
                    if let first = result.drivers.first {
                        Text(first).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    } else if !result.unmetRequirements.isEmpty {
                        Text("Tap to add the details needed")
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(result.title): \(result.headline). \(changeSpeech)\(result.drivers.first ?? "")")
        }
    }

    /// Folded into the card's combined label, because the chip's own label is
    /// unreachable once `accessibilityElement(children: .combine)` has merged it.
    private var changeSpeech: String {
        guard let change, change.isMeaningful else { return "" }
        return "\(change.direction == .up ? "Up" : "Down") \(Int(abs(change.delta).rounded())) points \(change.comparison). "
    }

    private var iconName: String {
        switch result.id {
        case .cardiovascularRisk: return "waveform.path.ecg"
        case .heartHealth: return "heart.fill"
        case .heartAge: return "hourglass"
        case .bloodPressure: return "gauge.medium"
        case .readiness: return "bolt.heart"
        case .substanceImpact: return "wineglass"
        case .sleepQuality: return "moon.stars.fill"
        case .cardioFitness: return "figure.run"
        case .cardioTrajectory: return "chart.line.uptrend.xyaxis"
        case .bodyComposition: return "figure.arms.open"
        case .restingHeartRateTrend: return "heart.text.square"
        case .vitalSigns: return "stethoscope"
        case .energy: return "bolt.batteryblock"
        case .healthWatch: return "sensor.fill"
        case .sleepDebt: return "moon.zzz"
        case .peerStanding: return "chart.bar.xaxis"
        case .circadianConsistency: return "clock.badge.checkmark"
        }
    }
}
