import SwiftUI
import InsightKit
import UniformTypeIdentifiers

/// Export everything the Vitals tab knows about, so it can be handed back to
/// whoever is building the app.
///
/// This is a development feedback loop, and it exists because of a specific
/// recurring failure: nobody working on this app can see the user's data, so
/// "what signals do we have?" has always been answered by reading the *parsers*.
/// That has been wrong before — a bedtime sat recorded as unavailable for
/// several sessions while it was in every payload, being discarded at ingest.
///
/// The report itself is built by `DataInventory` in InsightKit, where it is
/// tested; this screen is the share sheet around it.
struct DataExportView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false
    @State private var copiedCards = false
    @State private var copiedInternals = false
    @State private var fullExport: FullExport?
    @State private var exportFailed: String?

    /// The inventory, built on demand. Cheap next to the full export — it walks
    /// the samples once and keeps only per-signal aggregates.
    private var inventory: String {
        DataInventory.markdown(samples: model.samples,
                               rawGroups: model.otherDataGroups)
    }

    /// What every card is showing right now — the recalibration document.
    /// Built by `CardStateExport` in InsightKit, where it is tested; aggregates
    /// and wording only, so it stays paste-sized on any history.
    private var cardOutputs: String {
        CardStateExport.markdown(
            results: model.results,
            candidates: Dictionary(uniqueKeysWithValues:
                model.engine.models.map { ($0.id, $0.candidateMetrics) }),
            histories: Dictionary(uniqueKeysWithValues:
                model.results.map { ($0.id, model.scoreHistory(for: $0.id)) }),
            pendingHistories: Set(model.results.map(\.id)
                .filter { model.scoreHistoryIsPending(for: $0) }),
            samples: model.samples,
            profile: model.profile,
            buildStamp: BuildInfo.summary,
            now: Date())
    }

    /// What the cards judge against — baselines, comparison pools, derived
    /// nights. Built by `ModelInternalsExport` in InsightKit, where it is tested.
    private var modelInternals: String {
        ModelInternalsExport.markdown(samples: model.samples,
                                      events: model.substanceEvents,
                                      buildStamp: BuildInfo.summary,
                                      now: Date())
    }

    private var signalCount: Int {
        DataInventory.rows(samples: model.samples,
                           rawGroups: model.otherDataGroups).count
    }

    private var unmodelledCount: Int { model.otherDataGroups.count }

    var body: some View {
        List {
            Section {
                LabeledContent("Signals", value: "\(signalCount)")
                LabeledContent("Not yet modelled", value: "\(unmodelledCount)")
                LabeledContent("Readings", value: "\(model.samples.count + model.otherDataGroups.reduce(0) { $0 + $1.samples.count })")
            } header: {
                Text("What's in here")
            } footer: {
                Text("Everything the Vitals tab shows, including the imported fields under \"Other data\" that no card reads yet. Your own health data — it stays on this phone until you share it, and it never contains account details or tokens.")
            }

            Section {
                ShareLink(item: inventory,
                          preview: SharePreview("Health Insights — data inventory")) {
                    Label("Share inventory", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = inventory
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy inventory",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Inventory")
            } footer: {
                Text("One line per signal: how many readings, over what dates, from which device, and the range of values. Small enough to paste into a message — this is the one to send.")
            }

            Section {
                ShareLink(item: cardOutputs,
                          preview: SharePreview("Health Insights — card outputs")) {
                    Label("Share card outputs", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = cardOutputs
                    copiedCards = true
                } label: {
                    Label(copiedCards ? "Copied" : "Copy card outputs",
                          systemImage: copiedCards ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Card outputs")
            } footer: {
                Text("Every card as it reads right now — score, drivers, weighted shares, and whether each declared input actually has data — stamped with the build that produced it. This is the one to send when a card looks wrong: it shows what you're seeing, not what the code intends.")
            }

            Section {
                ShareLink(item: modelInternals,
                          preview: SharePreview("Health Insights — model internals")) {
                    Label("Share model internals", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = modelInternals
                    copiedInternals = true
                } label: {
                    Label(copiedInternals ? "Copied" : "Copy model internals",
                          systemImage: copiedInternals ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("Model internals")
            } footer: {
                Text("What the cards judge against: the personal baseline behind every \"vs your normal\" figure (with how much history it holds), the substance comparison pools with their sizes, and the last month of nights per source. Send this with the card outputs when the question is why a card judged something.")
            }

            Section {
                Button {
                    buildFullExport()
                } label: {
                    Label("Prepare full export", systemImage: "doc.zipper")
                }
                if let fullExport {
                    ShareLink(item: fullExport,
                              preview: SharePreview("health-insights-export.json")) {
                        Label("Share full export", systemImage: "square.and.arrow.up")
                    }
                }
                if let exportFailed {
                    Label(exportFailed, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
            } header: {
                Text("Full export")
            } footer: {
                Text("Every individual reading, as JSON. This runs to tens of megabytes on a long history, so it's a file to share rather than something to paste. Only needed when a question turns on the actual values.")
            }

            Section {
                NavigationLink {
                    OtherDataListView(groups: model.otherDataGroups)
                } label: {
                    Label("Browse what isn't modelled yet", systemImage: "tray.full")
                }
            } footer: {
                Text("The fields a provider sends that no insight reads. This is the list worth mining for new cards.")
            }
        }
        .navigationTitle("Export my data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func buildFullExport() {
        exportFailed = nil
        do {
            let data = try DataInventory.fullExportJSON(samples: model.samples,
                                                        rawGroups: model.otherDataGroups)
            fullExport = FullExport(data: data)
        } catch {
            // Said out loud rather than leaving a button that silently does
            // nothing — a share sheet that never appears reads as a broken app.
            exportFailed = "Couldn't build the export: \(error.localizedDescription)"
        }
    }
}

/// The JSON payload, wrapped so `ShareLink` hands over a real `.json` file
/// rather than a wall of text pasted into the message body.
private struct FullExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("health-insights-export.json")
    }
}

/// A plain list of the unmodelled identifiers, newest-reporting first.
///
/// The Vitals tab already has this, but reaching it means scrolling past every
/// modelled metric; here it is the point of the screen.
private struct OtherDataListView: View {
    let groups: [RawMetricGroup]

    var body: some View {
        List {
            if groups.isEmpty {
                ContentUnavailableView("Nothing unmodelled",
                                       systemImage: "checkmark.circle",
                                       description: Text("Every imported field is already a first-class metric."))
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.displayName).font(.subheadline)
                        Text(group.id)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text("\(group.samples.count) readings")
                            if let latest = group.latest {
                                Text("· latest \(latest.formattedValue)")
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Not yet modelled")
        .navigationBarTitleDisplayMode(.inline)
    }
}
