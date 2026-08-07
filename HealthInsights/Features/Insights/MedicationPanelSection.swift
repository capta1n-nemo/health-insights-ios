import SwiftUI
import Charts
import InsightKit

/// **What the drug is doing** — backlog `R24` and `B3-21`.
///
/// `MedicationSection` reads weight against the dose ladder. This is the other
/// two questions:
///
/// - **`R24`, intake versus expenditure.** Both are dated series, so this is
///   Substance Impact's before/after shape with a different pair of quantities.
///   The two deltas are reported **separately**, and the expected honest finding
///   is *"the drug moved what you eat, not what you burn"*.
/// - **`B3-21`, folded onto days-since-dose.** Fourteen tirzepatide doses laid
///   on top of each other say what day three looks like; a line against the
///   calendar says only what happened. Every bin carries **how many doses it
///   rests on**.
///
/// ## The two claims this section is built to refuse
///
/// ⚠️ **"Mounjaro speeds up your metabolism" must never appear here.** No such
/// effect is established, and a rising intake-over-expenditure ratio during
/// treatment is far more likely a food log that got worse as appetite fell.
/// `MedicationDoseResponse` never combines the two figures, and
/// `MedicationDoseResponseTests` asserts that no arm of its sentence machine can
/// produce the claim on any combination of the deltas.
///
/// ⚠️ **Apple's basal energy is not "your metabolism".** It is a formula the
/// phone evaluated from height, weight, age and sex — modelled dressed as
/// measured. Nothing here reads it. The two series are what the reader *logged
/// eating* and what the watch *measured them burning moving*, and each row says
/// which of those it is.
struct MedicationPanelSection: View {
    @Environment(AppModel.self) private var model
    @State private var selected: MetricType?

    /// What is worth folding. Deliberately a stated list rather than every
    /// metric the app holds: a fold needs something that plausibly moves inside
    /// a dose cycle, and height or vascular age moving across seven days would
    /// be measuring the passage of time.
    private static let foldable: [MetricType] = [
        .bodyMass, .dietaryEnergy, .activeEnergyBurned, .stepCount,
        .restingHeartRate, .heartRate, .heartRateVariabilityRMSSD,
        .sleepDurationHours, .sleepEfficiency, .exerciseMinutes,
        .respiratoryRate, .bodyFatPercentage
    ]

    private var doses: [AdministeredDose] {
        model.activeMedication?.doses.map(\.administered) ?? []
    }

    var body: some View {
        if doses.isEmpty {
            EmptyView()
        } else {
            contrastSection
            Divider()
            foldSection
        }
    }

    // MARK: - R24: what you eat, and what you burn

    @ViewBuilder private var contrastSection: some View {
        let contrast = MedicationDoseResponse.contrast(doses: doses, samples: model.samples)
        InsightSection(
            title: "What you eat, and what you burn",
            trailing: contrast?.intake.map {
                String(format: "%+.0f kcal a day eaten", $0.delta)
            },
            caveat: .computed(.partial, MedicationDoseResponse.notMetabolism),
            expansion: .collapsed(preview: contrast?.sentence
                                  ?? "Needs a logged stretch either side of your first dose.")
        ) {
            if let contrast {
                Text(contrast.sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(contrast.rows) { row in
                    Divider()
                    contrastRow(row)
                }
                if contrast.hasAnything {
                    // count-in-copy: exempt — "two" is the structure of the
                    // section, not the size of a collection: intake and
                    // expenditure are exactly the two quantities this contrast
                    // is, and the whole point of the sentence is that they are
                    // never combined into one. count-in-copy: exempt
                    Text("Reported as two numbers on purpose. One figure combining them — a ratio, a net — would be a claim about your metabolism, and neither of these measures one.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("There is no first dose to divide on yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func contrastRow(_ row: MedicationDoseResponse.BeforeAfter) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(.caption.weight(.medium))
                Spacer(minLength: 8)
                Text(String(format: "%+.0f kcal a day", row.delta))
                    .font(.caption.weight(.semibold)).monospacedDigit()
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 2) {
                GridRow {
                    figure(String(format: "%.0f", row.beforeMean), "Before")
                    figure(String(format: "%.0f", row.afterMean), "After")
                    figure("\(row.beforeDays) / \(row.afterDays)", "Days each side")
                    figure(row.z.map { String(format: "%+.1f SD", $0) } ?? "—",
                           "Vs your spread")
                }
            }
            // **Which of these the reader typed.** The whole confound lives
            // here: appetite falling is exactly when a food log gets patchier,
            // so a fall in logged intake is partly a fall in logging.
            Text(row.isSelfReported
                 ? "You logged this. \(MedicationDoseResponse.intakeIsSelfReported)"
                 : "Your watch measured this while you moved. It is not, and does not stand in for, everything your body spends in a day.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if !row.moved {
                Text("Inside your own day-to-day spread before you started, so this section will not call it a change.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .gridColumnAlignment(.leading)
    }

    // MARK: - B3-21: folded onto days since the dose

    @ViewBuilder private var foldSection: some View {
        let folds = MedicationDoseResponse.folds(doses: doses, samples: model.samples,
                                                 metrics: Self.foldable)
        let cycle = MedicationDoseResponse.cycleDays(doses: doses)
        InsightSection(
            title: "What the drug is doing",
            trailing: cycle.map { "\(doses.count) doses · \($0)-day cycle" },
            caveat: .computed(.fitted, "Every reading is placed by how many days it was after the dose before it, then averaged across doses. That is timing, not cause: anything that happens on the same weekday as your injection lands in the same bin."),
            expansion: .collapsed(preview: folds.isEmpty
                                  ? "Needs readings spread across the days of a dose cycle."
                                  : "\(folds.count) \(SectionCaveat.plural(folds.count, "signal")) folded onto days since a dose.")
        ) {
            if folds.isEmpty {
                Text("Nothing yet has readings landing on more than one day of your dose cycle, so there is no within-cycle shape to draw.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let shown = folds.first { $0.metric == selected } ?? folds[0]
                Picker("Signal", selection: Binding(
                    get: { shown.metric },
                    set: { selected = $0 })) {
                    ForEach(folds) { fold in
                        Text(fold.metric.displayName).tag(fold.metric)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)

                DoseCycleChart(fold: shown)
                binTable(shown)
                Text(honestyLine(for: shown))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sideEffectFold
        }
    }

    /// **The dose count is the finding's honesty, so it is a column and not a
    /// footnote.** A mean of two doses and a mean of fourteen draw identically.
    private func binTable(_ fold: MedicationDoseResponse.Fold) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Day")
                Text("Average").gridColumnAlignment(.trailing)
                Text("Doses").gridColumnAlignment(.trailing)
                Text("Readings").gridColumnAlignment(.trailing)
            }
            .font(.caption2).foregroundStyle(.secondary)
            Divider()
            ForEach(fold.bins) { bin in
                GridRow {
                    Text("\(bin.offset)").font(.caption).monospacedDigit()
                    Text(String(format: "%.1f", bin.mean))
                        .font(.caption.weight(.medium)).monospacedDigit()
                    Text("\(bin.doses)").font(.caption).monospacedDigit()
                    Text("\(bin.readings)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }

    private func honestyLine(for fold: MedicationDoseResponse.Fold) -> String {
        let swing = fold.swingInSDs.map { String(format: "%.1f", $0) } ?? "—"
        return "Across the cycle this moves \(swing) of its own day-to-day spread, "
            + "and its thinnest day rests on \(fold.weakestBinDoses) "
            + SectionCaveat.plural(fold.weakestBinDoses, "dose")
            + ". A shape built from one or two doses at some point on the cycle is a "
            + "coincidence with a line through it."
    }

    @ViewBuilder private var sideEffectFold: some View {
        let effects = model.sideEffects.map { (name: $0.name, severity: $0.severity, date: $0.date) }
        if let fold = MedicationDoseResponse.sideEffectFold(doses: doses, effects: effects) {
            Divider()
            NestedInsightSection(
                title: "Side effects, by day of the cycle",
                trailing: "\(fold.recordCount) "
                    + SectionCaveat.plural(fold.recordCount, "record"),
                caveat: .computed(.partial, "Counts, not severities. Averaging \(fold.recordCount) records over \(fold.cycleDays) days would be one or two records a day dressed as a trend.")
            ) {
                ForEach(Array(fold.counts.enumerated()), id: \.offset) { offset, count in
                    HStack(spacing: 8) {
                        Text("Day \(offset)")
                            .font(.caption2).monospacedDigit()
                            .frame(width: 46, alignment: .leading)
                        GeometryReader { geometry in
                            let peak = max(1, fold.counts.max() ?? 1)
                            Capsule()
                                .fill(Theme.accent.opacity(count == 0 ? 0.12 : 0.55))
                                .frame(width: max(2, geometry.size.width
                                                  * CGFloat(count) / CGFloat(peak)))
                        }
                        .frame(height: 10)
                        Text("\(count)")
                            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// One signal's within-cycle shape.
///
/// **substance-shading: exempt — the x axis is days since a dose, not calendar
/// time.** A shaded stretch says "something was logged between these two dates",
/// and there are no dates here to land it on; every occasion in the log has been
/// folded onto the same seven days. Same exemption `FitnessProjectionChart`
/// carries for plotting months ahead.
///
/// It also does not pan, which is the §9b exemption: there is no window to strand
/// the reader in, the domain is the whole cycle by construction, and no header
/// above it is derived from a visible range.
private struct DoseCycleChart: View {
    let fold: MedicationDoseResponse.Fold

    var body: some View {
        Chart {
            cycleMarks
        }
        .chartXAxis {
            AxisMarks(values: fold.bins.map(\.offset)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let offset = value.as(Int.self) { Text("\(offset)") }
                }
            }
        }
        .chartYScale(domain: domain)
        .frame(height: 150)
        .accessibilityLabel("\(fold.metric.displayName) by day since dose, "
                            + "across \(fold.doseCount) doses")
    }

    /// The visible extent, from the data rather than a round number above it,
    /// with a tenth of the range as breathing room at each end.
    private var domain: ClosedRange<Double> {
        let means = fold.bins.map(\.mean)
        guard let lo = means.min(), let hi = means.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.1, 0.001)
        return (lo - pad)...(hi + pad)
    }

    /// ⚠️ **Explicit `-> some ChartContent`.** Without it a `RuleMark` plus
    /// `LineMark` plus `PointMark` chain can resolve to `Chart3DContent` on this
    /// SDK, compile clean, and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private var cycleMarks: some ChartContent {
        // The flat line the shape is read against. Dashed, because it is a
        // reference level rather than a measured series — the app's one meaning
        // for a dash.
        RuleMark(y: .value("Across the cycle", fold.treatedMean))
            .lineStyle(Theme.projectedStroke)
            .foregroundStyle(.secondary)
        ForEach(fold.bins) { bin in
            LineMark(x: .value("Days since dose", bin.offset),
                     y: .value(fold.metric.displayName, bin.mean))
                // Linear, never curved: a curve between two day-averages invents
                // values for hours nobody averaged.
                .interpolationMethod(.linear)
                .foregroundStyle(Theme.accent)
        }
        ForEach(fold.bins) { bin in
            PointMark(x: .value("Days since dose", bin.offset),
                      y: .value(fold.metric.displayName, bin.mean))
                .foregroundStyle(Theme.accent)
                // Bigger where more doses back it. The thinnest bin is what the
                // whole shape is only as good as, and a uniform dot hides that.
                .symbolSize(by: .value("Doses", bin.doses))
        }
    }
}
