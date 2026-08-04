import SwiftUI
import InsightKit

/// The read-only detail pages for the logged data domains — substances,
/// medication, side effects. Each is a `DomainDataScaffold`, so they share one
/// shape: an optional overview chart built from a shared chart component, then
/// the entries newest first, then a standard empty state.
///
/// **Viewing, not adding.** These opened the wrong place before — the substance
/// *add* page, the Body Composition *card* — because there was no read surface
/// distinct from the write one. Adding stays in the sheets the `+` menu and the
/// card's "View & add" open; these are where the reader reviews what those
/// added.

// MARK: - Substances

struct SubstanceDataView: View {
    @Environment(AppModel.self) private var model

    private var events: [SubstanceEvent] {
        model.substanceEvents.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.substances.title,
            entriesHeader: "Entries",
            entryCount: events.count,
            emptyHeadline: "Nothing logged yet",
            emptyMessage: "Substances you log appear here, with the cardiovascular load they still carry.",
            emptySymbol: "wineglass",
            overview: {
                let points = model.substanceLoadSeries()
                if points.count > 1 {
                    Section {
                        SubstanceLoadChart(points: points)
                    } header: {
                        Text("Cardiovascular load")
                    } footer: {
                        Text(DataDomain.substances.summary)
                    }
                }
            },
            rows: {
                ForEach(events) { event in
                    HStack {
                        Text(event.substance.displayName)
                        Spacer()
                        Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            })
    }
}

// MARK: - Medication

struct MedicationDataView: View {
    @Environment(AppModel.self) private var model

    private var doses: [DoseLogRecord] {
        (model.activeMedication?.doses ?? []).sorted { $0.takenAt > $1.takenAt }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.medication.title,
            entriesHeader: "Doses",
            entryCount: doses.count,
            emptyHeadline: "No doses yet",
            emptyMessage: "Doses you log or import appear here, with how much is still in your system.",
            emptySymbol: "syringe",
            overview: {
                if let medication = model.activeMedication, let compound = medication.compound {
                    let points = model.medicationCurve()
                    if points.count > 1 {
                        Section {
                            MedicationCurveChart(points: points, compound: compound)
                        } header: {
                            Text(medication.brandName ?? compound.displayName)
                        } footer: {
                            Text(DataDomain.medication.summary)
                        }
                    }
                }
            },
            rows: {
                ForEach(doses) { dose in
                    doseRow(dose)
                }
            })
    }

    private func doseRow(_ dose: DoseLogRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dose.takenAt.formatted(date: .abbreviated, time: .omitted))
                if let site = dose.injectionSite {
                    Text(site).font(.caption).foregroundStyle(.secondary)
                }
                if dose.isInferred && dose.confirmedAt == nil {
                    // Dashed everywhere else it appears; here it is a word,
                    // because a list row has no line to dash.
                    Text("Estimated — not yet confirmed")
                        .font(.caption2).foregroundStyle(Theme.warn)
                }
            }
            Spacer()
            Text("\(dose.milligrams.formatted()) mg")
                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

// MARK: - Derived scores

/// Every number the app worked out — each card's score, and the clinical
/// estimate behind it where there is one (a 10-year risk percentage, a heart
/// age). Read-only by definition: nothing here was entered or measured.
///
/// Kept apart from the measured metrics for the reason the modelled medication
/// level is: presenting a computed number beside sensed ones invites reading it
/// as a measurement. The footer says so once, plainly.
struct DerivedScoreDataView: View {
    @Environment(AppModel.self) private var model

    private var scored: [InsightResult] {
        model.results.filter { $0.score != nil }
            .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.derivedScores.title,
            entriesHeader: "Cards",
            entryCount: scored.count,
            emptyHeadline: "Nothing scored yet",
            emptyMessage: "Once a card can produce a number from your data, it appears here with the estimate behind it.",
            emptySymbol: "function",
            overview: {
                Section {
                    Text(DataDomain.derivedScores.summary)
                        .font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text("These are outputs, not readings. Each is computed from the measurements and details in the sections above — change those and these move.")
                }
            },
            rows: {
                ForEach(scored, id: \.id) { result in
                    NavigationLink {
                        InsightDetailView(insightID: result.id)
                    } label: {
                        row(result)
                    }
                }
            })
    }

    private func row(_ result: InsightResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.title)
                Spacer()
                if let score = result.score {
                    Text("\(Int(score.rounded()))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            // The card's own quantity in its own units — a risk percentage, a
            // heart age — which is a different number from the 0–100 dial and
            // is the one a clinician would recognise.
            HStack(spacing: 6) {
                Text(result.headline)
                    .font(.caption).foregroundStyle(.tertiary)
                Text("· \(result.confidence.rawValue)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Side effects

struct SideEffectDataView: View {
    @Environment(AppModel.self) private var model

    private var effects: [SideEffectRecord] {
        model.sideEffects.sorted { $0.date > $1.date }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.sideEffects.title,
            entriesHeader: "Recorded",
            entryCount: effects.count,
            emptyHeadline: "Nothing recorded yet",
            emptyMessage: "Side effects you record or import appear here, worst first when they share a day.",
            emptySymbol: "cross.case",
            rows: {
                ForEach(effects, id: \.persistentModelID) { effect in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(effect.name)
                            Text(effect.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(effect.severity)/10")
                            .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            model.deleteSideEffect(effect)
                        }
                    }
                }
            })
    }
}

/// Symptoms the reader has tagged, newest first.
///
/// Read-only, unlike its neighbours, and deliberately: every one of these came
/// out of Apple Health, so the place to correct one is the Health app. A delete
/// here would remove the app's promoted copy and the next sync would bring it
/// straight back — a control that appears to work and does not.
struct SymptomDataView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.symptoms.title,
            entriesHeader: "Tagged",
            entryCount: model.symptoms.count,
            emptyHeadline: "Nothing tagged yet",
            emptyMessage: "Symptoms you tag in the Health app appear here. Days you recorded *not* having something are kept too — an absence you confirmed is worth more than silence.",
            emptySymbol: "list.clipboard",
            rows: {
                ForEach(model.symptoms) { event in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.type.title)
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.severity.title)
                            .font(.subheadline)
                            // A recorded absence is dimmer than an occurrence:
                            // it is real data and it is not an event.
                            .foregroundStyle(event.severity.isPresent ? .secondary : .tertiary)
                    }
                }
            })
    }
}
