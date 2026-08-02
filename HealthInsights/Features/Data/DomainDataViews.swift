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
