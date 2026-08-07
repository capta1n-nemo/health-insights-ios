import SwiftUI
import InsightKit
import UniformTypeIdentifiers

/// Export everything the Data tab knows about, so it can be handed back to
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
    @State private var preparingFullExport = false
    @State private var exportFailed: String?

    /// The three shareable documents, built once, off the main thread.
    ///
    /// These used to be computed properties, which meant *opening this screen*
    /// walked the full sample set several times over — the inventory sorts
    /// every signal's distribution, the card export scans availability per
    /// declared input, and `signalCount` did yet another full walk — all
    /// synchronously inside `body`, and again on every tap ("copy takes
    /// ages"). Now the screen appears instantly, each section shows it is
    /// preparing, and copy pastes a string that already exists.
    struct Documents: Sendable {
        let inventory: String
        let cardOutputs: String
        let modelInternals: String
        let signalCount: Int
    }
    @State private var documents: Documents?
    @State private var showingImporter = false
    @State private var importMessage: String?

    /// Bringing data *in*, opposite the export rows below.
    ///
    /// The share sheet is the main route — the reader exports from Shotsy and
    /// sends it here — and this picker is the fallback for a file already saved
    /// to Files. Both land in the same `importSharedFile`, so there is one
    /// import path rather than two that can diverge.
    @ViewBuilder private var importSection: some View {
        Section {
            Button {
                showingImporter = true
            } label: {
                Label("Import a Shotsy backup", systemImage: "square.and.arrow.down")
            }
            if let importMessage {
                Text(importMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Bring data in")
        } footer: {
            Text("In Shotsy, use its export and share the file to Health Insights — your injections, weight and body-composition history come across. You can also pick a file you've already saved. Sharing the same backup twice is safe: nothing is imported twice.")
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.json, .text],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { importMessage = await model.importSharedFile(at: url) }
            case .failure(let error):
                importMessage = "Couldn't open that file: \(error.localizedDescription)"
            }
        }
    }

    private var unmodelledCount: Int { model.otherDataGroups.count }

    /// Gather main-actor inputs, then build everything detached. The builders
    /// are pure InsightKit functions over Sendable values, so the only
    /// main-thread work left is the state assignment at the end.
    private func prepareDocuments() async {
        guard documents == nil else { return }
        let samples = model.samples
        let rawGroups = model.otherDataGroups
        let results = model.results
        let candidates = Dictionary(uniqueKeysWithValues:
            model.engine.models.map { ($0.id, $0.candidateMetrics) })
        let histories = Dictionary(uniqueKeysWithValues:
            results.map { ($0.id, model.scoreHistory(for: $0.id)) })
        let pending = Set(results.map(\.id).filter { model.scoreHistoryIsPending(for: $0) })
        let profile = model.profile
        let events = model.substanceEvents
        let stamp = BuildInfo.summary

        let built = await Task.detached(priority: .userInitiated) {
            Documents(
                inventory: DataInventory.markdown(samples: samples, rawGroups: rawGroups),
                cardOutputs: CardStateExport.markdown(
                    results: results, candidates: candidates, histories: histories,
                    pendingHistories: pending, samples: samples, profile: profile,
                    buildStamp: stamp, now: Date()),
                modelInternals: ModelInternalsExport.markdown(
                    samples: samples, events: events,
                    raw: rawGroups.flatMap(\.samples),
                    buildStamp: stamp, now: Date()),
                signalCount: DataInventory.rows(samples: samples, rawGroups: rawGroups).count)
        }.value
        documents = built
    }

    /// Share/copy controls for one prepared document, or a "preparing" row
    /// that says what the wait is while the build runs.
    @ViewBuilder private func documentControls(_ text: String?, title: String,
                                               copiedFlag: Binding<Bool>) -> some View {
        if let text {
            ShareLink(item: text, preview: SharePreview(title)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.string = text
                copiedFlag.wrappedValue = true
            } label: {
                Label(copiedFlag.wrappedValue ? "Copied" : "Copy",
                      systemImage: copiedFlag.wrappedValue ? "checkmark" : "doc.on.doc")
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparing — reading your history…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        List {
            importSection

            Section {
                if let documents {
                    LabeledContent("Signals", value: "\(documents.signalCount)")
                } else {
                    LabeledContent("Signals") { ProgressView() }
                }
                LabeledContent("Not yet modelled", value: "\(unmodelledCount)")
                LabeledContent("Readings", value: "\(model.samples.count + model.otherDataGroups.reduce(0) { $0 + $1.samples.count })")
            } header: {
                Text("What's in here")
            } footer: {
                // The claim here is still true and is deliberately kept (B8 R6):
                // this file goes nowhere until the reader taps Share, and it is
                // a different thing from the model-improvement tiers — those
                // shape a small, stated payload; this is the whole record,
                // handed over by hand.
                // The wording tracks what the file actually holds. It now also
                // carries which sources are connected and when each last
                // synced, so saying only "never account details or tokens"
                // would be true but would understate it — see
                // `HealthDataExport.Connection`.
                Text("Everything the Data tab shows, including the imported fields under \"Other data\" that no card reads yet. It also records which sources are connected and when each last synced, the suggestions you've waved away, and your accuracy ratings — never your passwords, sign-in tokens or account details, which cannot go in this file at all. Your own health data: nothing here goes anywhere until you share it yourself. This file is separate from Settings ▸ Data & model improvement, which is where anything shared automatically would be listed.")
            }

            Section {
                documentControls(documents?.inventory,
                                 title: "Health Insights — data inventory",
                                 copiedFlag: $copied)
            } header: {
                Text("Inventory")
            } footer: {
                Text("One line per signal: how many readings, over what dates, from which device, and the range of values. Small enough to paste into a message — this is the one to send.")
            }

            Section {
                documentControls(documents?.cardOutputs,
                                 title: "Health Insights — card outputs",
                                 copiedFlag: $copiedCards)
            } header: {
                Text("Card outputs")
            } footer: {
                Text("Every card as it reads right now — score, drivers, weighted shares, and whether each declared input actually has data — stamped with the build that produced it. This is the one to send when a card looks wrong: it shows what you're seeing, not what the code intends.")
            }

            Section {
                documentControls(documents?.modelInternals,
                                 title: "Health Insights — model internals",
                                 copiedFlag: $copiedInternals)
            } header: {
                Text("Model internals")
            } footer: {
                Text("What the cards judge against: the personal baseline behind every \"vs your normal\" figure (with how much history it holds), the substance comparison pools with their sizes, and the last month of nights per source. Send this with the card outputs when the question is why a card judged something.")
            }

            Section {
                if preparingFullExport {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Building the JSON — every reading, so this is the slow one…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        buildFullExport()
                    } label: {
                        Label("Prepare full export", systemImage: "doc.zipper")
                    }
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
        .task { await prepareDocuments() }
    }

    /// One `MedicationRecord` in export shape, or nil when it carries no
    /// recognisable compound. Shared by the active regimen and the finished
    /// ones so the two can never drift into different shapes.
    private static func exported(_ record: MedicationRecord) -> HealthDataExport.Medication? {
        record.compound.map { compound in
            HealthDataExport.Medication(
                compound: compound.rawValue,
                brandName: record.brandName,
                startedOn: record.startedOn,
                doses: record.doses
                    .sorted { $0.takenAt < $1.takenAt }
                    .map { .init(takenAt: $0.takenAt, milligrams: $0.milligrams,
                                 injectionSite: $0.injectionSite,
                                 isInferred: $0.isInferred,
                                 confirmedAt: $0.confirmedAt) })
        }
    }

    /// The app's five-case `IntegrationStatus` narrowed to the four-value,
    /// no-free-text `ConnectionState` the export can hold.
    ///
    /// ⚠️ **The two cases that carry a `String` deliberately drop it.**
    /// `.unavailable(reason:)` and `.error(_)` quote whatever the provider said,
    /// and an OAuth failure body is exactly where an access token turns up
    /// without anyone having decided to export one. The export type has no field
    /// for the text, so this switch cannot pass it on even by accident — see
    /// `HealthDataExport.ConnectionState`, and `OAuthTokens`, which gave up
    /// `Codable` for the same reason.
    ///
    /// Exhaustive on purpose: a new `IntegrationStatus` case does not compile
    /// until it says what the export should call it.
    private static func exported(_ status: IntegrationStatus) -> HealthDataExport.ConnectionState {
        switch status {
        case .notConnected: return .notConnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .unavailable: return .unavailable
        case .error: return .error
        }
    }

    private func buildFullExport() {
        exportFailed = nil
        preparingFullExport = true
        // Everything the app holds, not just the measured series — the logged
        // domains, the profile facts and each card's own output travel too. See
        // `HealthDataExport`, whose domain switch is what keeps a future
        // connector's data from being quietly left out of this file.
        let bundle = HealthDataExport(
            generatedAt: Date(),
            build: BuildInfo.summary,
            samples: model.samples,
            unmodelled: model.otherDataGroups.flatMap(\.samples),
            substances: model.substanceEvents,
            medication: model.activeMedication.flatMap(Self.exported),
            // Every finished course as well. `activeMedication` alone was
            // dropping them, and the reader could not tell — see
            // `HealthDataExport.previousMedication`.
            previousMedication: model.allMedications
                .filter { !$0.isActive }
                .compactMap(Self.exported),
            sideEffects: model.sideEffects.map {
                .init(name: $0.name, severity: $0.severity, date: $0.date)
            },
            symptoms: model.symptoms,
            bodyScans: model.bodyScans,
            profile: model.profile,
            derivedScores: model.results.map { result in
                HealthDataExport.DerivedScore(
                    card: result.id.rawValue, title: result.title,
                    score: result.score, primaryValue: result.primaryValue,
                    headline: result.headline,
                    confidence: result.confidence.rawValue,
                    history: model.scoreHistory(for: result.id)
                        .map { .init(date: $0.date, score: $0.score) })
            },
            // Every logged bleeding day. The derived cycles stay out by design —
            // see `HealthDataExport.cycles`, which also records why omitting this
            // argument was invisible to the export's own tests.
            cycles: model.cycleDays,
            // The merged ledger, not the raw rows — the deduplicated record is
            // the data point, and detected periods carry dates only (never an
            // event's title), which is what lets this key exist at all.
            holidays: model.holidayLedger.periods.map {
                HealthDataExport.Holiday(firstDay: $0.firstDay, lastDay: $0.lastDay,
                                         label: $0.label, source: $0.source.rawValue)
            },
            // Every figure the app worked out, day by day. These used to be
            // left out as "a cache that replays from samples" — true on this
            // phone, false of a pooled server-side dataset, which is the only
            // place the norms the reader wants can be built. See
            // `HealthDataExport.exportKey(for:)`, which keeps the superseded
            // reasoning, and `docs/norms-and-telemetry.md`.
            generatedInsights: HealthDataExport.derivedSeries(from: model.derivedSeries),
            // Which sources are connected and when each last delivered — the
            // provenance every other key in the file rests on, and held nowhere
            // that leaves the phone otherwise (Keychain and SwiftData). **Never
            // the credential**: `HealthDataExport.Connection` has no field a
            // token could occupy, and `exported(_:)` above discards the free
            // text on the two statuses that carry it.
            connections: model.registry.integrations.map { integration in
                HealthDataExport.Connection(
                    integration: integration.id,
                    state: Self.exported(model.status(for: integration)),
                    lastSync: {
                        if case .connected(let lastSync) = model.status(for: integration) {
                            return lastSync
                        }
                        return nil
                    }())
            },
            // The reader telling the app it was wrong to raise something. Not
            // recomputable from anything else here — a judgement, not a
            // derivation.
            suggestionDismissals: model.suggestionDismissals,
            // The two model-improvement ledgers. Both were on the phone and in
            // no export key at all until backlog Q10.
            feedback: model.dataStore.loadFeedback().map {
                HealthDataExport.Feedback(card: $0.insight, rating: $0.rating,
                                          modelVersion: $0.modelVersion,
                                          cohort: $0.cohort, recordedAt: $0.at)
            },
            // The raw predicted/actual pairs, as the device holds them. The
            // coarsened, DP-noised `TelemetryEvent` is a different type and is
            // what would be transmitted if sharing were ever switched on.
            predictionOutcomes: model.dataStore.loadPredictionOutcomes())
        Task {
            // Detached: the JSON encode runs to tens of megabytes, and it used
            // to run synchronously on the main thread behind a button that
            // gave no sign anything was happening.
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try bundle.json() }
            }.value
            preparingFullExport = false
            switch outcome {
            case .success(let data): fullExport = FullExport(data: data)
            case .failure(let error):
                // Said out loud rather than leaving a button that silently does
                // nothing — a share sheet that never appears reads as a broken app.
                exportFailed = "Couldn't build the export: \(error.localizedDescription)"
            }
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
/// The Data tab already has this, but reaching it means scrolling past every
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
                            // See `RawMetricGroup.latestReal`.
                            if let latest = group.latestReal {
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
