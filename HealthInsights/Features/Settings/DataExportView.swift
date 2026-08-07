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
/// ## ⚠️ One export. Exactly one. (2026-08-07, backlog B20)
///
/// This screen used to offer **five**: the full JSON, plus separate Inventory,
/// Card outputs and Model internals text files, with the troubleshooting log a
/// sixth surface on another screen. The reader, verbatim:
///
/// > *"I hate having all these different export options in the 'Export my
/// > Data', just have one export option that contains everything. This should
/// > also include troubleshooting, and the data & model improvements. Currently
/// > there is no way to export Data and model improvement data, include that in
/// > the full export."*
///
/// So there is one button. **The three prose reports were not deleted** — each
/// of them was built as a diagnosis instrument and each found a live defect on
/// first use, and the inventory's per-signal coverage table is the most useful
/// single artefact this app produces. They are folded in as named sections of
/// the one file (`HealthDataExport.Reports`), along with `DiagnosticsLog` and
/// the correction record (`HealthDataExport.Improvements`, backlog R4), which
/// had no export path at all.
///
/// The reports themselves are still built by `DataInventory`,
/// `CardStateExport` and `ModelInternalsExport` in InsightKit, where they are
/// tested; this screen is the share sheet around all of it.
struct DataExportView: View {
    @Environment(AppModel.self) private var model
    @State private var fullExport: FullExport?
    @State private var preparingFullExport = false
    @State private var exportFailed: String?

    /// The three prose reports, built once, off the main thread.
    ///
    /// These used to be computed properties, which meant *opening this screen*
    /// walked the full sample set several times over — the inventory sorts
    /// every signal's distribution, the card export scans availability per
    /// declared input, and `signalCount` did yet another full walk — all
    /// synchronously inside `body`. Now the screen appears instantly and the
    /// walk happens once, in the background, feeding both the signal count at
    /// the top and the `reports` section of the export.
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

    /// The build in flight, so two callers wait on one walk.
    ///
    /// ⚠️ **`guard documents == nil` is not enough on its own, and became wrong
    /// the moment the export folded the reports in (B20).** `.task` starts the
    /// build on appear and the button now awaits the same thing; a reader
    /// tapping Prepare while the first walk is still running would find
    /// `documents` still nil and start a second full pass over every sample —
    /// the exact cost this preparation exists to pay only once.
    @State private var documentBuild: Task<Documents, Never>?

    /// Gather main-actor inputs, then build everything detached. The builders
    /// are pure InsightKit functions over Sendable values, so the only
    /// main-thread work left is the state assignment at the end.
    private func prepareDocuments() async {
        guard documents == nil else { return }
        if let documentBuild {
            documents = await documentBuild.value
            return
        }
        let samples = model.samples
        let rawGroups = model.otherDataGroups
        let results = model.results
        let candidates = Dictionary(uniqueKeysWithValues:
            model.engine.models.map { ($0.id, $0.candidateMetrics) })
        // Same fix as `buildFullExport()` below, and the same reason: this is a
        // document the reader hands to someone, not a chart racing to a first
        // frame. The lazy cache would emit "no scored days yet" for every card
        // whose chart happened not to have been drawn — which on a fresh launch
        // is all of them.
        let histories = Dictionary(uniqueKeysWithValues:
            results.map { ($0.id, model.storedScoreHistory(for: $0.id)) })
        // ⚠️ `pending` stays on the LAZY reader on purpose: it answers "is the
        // replay still running", which is a fact about the cache and not about
        // the store. Reading it from SwiftData would always say "not pending".
        let pending = Set(results.map(\.id).filter { model.scoreHistoryIsPending(for: $0) })
        let profile = model.profile
        let events = model.substanceEvents
        let stamp = BuildInfo.summary

        let build = Task.detached(priority: .userInitiated) {
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
        }
        documentBuild = build
        documents = await build.value
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
                Text("Everything the Data tab shows, including the imported fields under \"Other data\" that no card reads yet. It also records which sources are connected and when each last synced, the suggestions you've waved away, your accuracy ratings, the troubleshooting log, and your corrections — never your passwords, sign-in tokens or account details, which cannot go in this file at all. Your own health data: nothing here goes anywhere until you share it yourself. Your corrections are included at whichever level you set in Settings ▸ Data & model improvement, which is also where anything shared automatically would be listed.")
            }

            // ⚠️ **One section, and it stays one.** There were four here — the
            // inventory, the card outputs, the model internals and the JSON —
            // and the reader had to know which answered a question before they
            // had asked it. Everything they held is now inside this one file;
            // see `HealthDataExport.Reports` and `.Improvements`.
            Section {
                if preparingFullExport {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Building it — every reading, so this takes a moment…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await buildFullExport() }
                    } label: {
                        Label("Prepare export", systemImage: "doc.zipper")
                    }
                }
                if let fullExport {
                    ShareLink(item: fullExport,
                              preview: SharePreview("health-insights-export.json")) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                }
                if let exportFailed {
                    Label(exportFailed, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
            } header: {
                Text("Export everything")
            } footer: {
                Text("One file, as JSON, containing all of it: every individual reading; the signal inventory (how many readings each signal has, over what dates, from which device); every card as it reads right now, with its drivers and weighted shares; what the cards judge against — your personal baselines and comparison pools; the troubleshooting log; and your corrections, with what the app guessed and what you said. It runs to tens of megabytes on a long history, so it's a file to share rather than something to paste.")
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

    /// Build the one file.
    ///
    /// `async` since B20, because the prose reports are now part of it and they
    /// are prepared in the background: tapping the button before that finishes
    /// used to be impossible (each report had its own section, which showed its
    /// own spinner), and now it is the normal case. `prepareDocuments()` returns
    /// immediately when they are already built, so the wait is only ever paid
    /// once.
    private func buildFullExport() async {
        exportFailed = nil
        preparingFullExport = true
        await prepareDocuments()
        let prose = documents
        // The troubleshooting log, read on the main actor where it lives. The
        // reader asked for it in the one export by name — it used to be a
        // separate text file on the Troubleshooting screen and nothing else.
        let diagnostics = DiagnosticsLog.shared.exportText()
        let outcomes = model.dataStore.loadPredictionOutcomes()
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
                    // ⚠️ **`dataStore`, NOT `model.scoreHistory(for:)`** — found
                    // 2026-08-07 in the reader's own export, where all 18 cards
                    // exported `history: []` while SwiftData held the rows.
                    //
                    // `AppModel.scoreHistory(for:)` is a **lazy view cache**: it
                    // returns `[]` and queues a background replay when the card's
                    // chart has not been drawn yet, because a 90-day replay per
                    // card is too slow to do on the way to a first frame. That is
                    // right for a view and wrong for an export, which asks about
                    // every card at once and waits for nothing.
                    //
                    // The class is D39's exactly: **the key existed, the data
                    // existed, and the payload was empty** — and no InsightKit
                    // test can catch it, because `HealthDataExportTests` builds
                    // its own bundle rather than going through this caller.
                    //
                    // ⚠️ It is also the reason the app could not learn from
                    // itself: with no exported history there are no
                    // prediction-versus-actual pairs for anything to grade.
                    history: model.storedScoreHistory(for: result.id)
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
            // ⚠️ **The one tier-conditional key in the file, on the reader's own
            // ruling (2026-08-07, D50):** *"if they have full sharing your
            // corrections enabled, it will be enabled for that future feature
            // (server) and the export."*
            //
            // So the whole calendar — including the events they never reviewed —
            // travels at `.full` and at no other tier. **Gated by the same
            // switch that governs `improvements` above**, deliberately: the
            // reader made one choice and it has to mean one thing everywhere.
            //
            // ⚠️ **`[]` rather than omitting the argument.** The key is always
            // present, so a reader opening the file sees an empty array and can
            // tell "I have this turned off" from "this app does not export
            // calendars" — and `verify.sh`'s export lint keeps seeing it passed.
            calendarEvents: model.sharingPreferences.effectiveTier == .full
                ? model.calendarEvents : [],

            // The merged sick-day ledger (§B11-4), on exactly the terms the
            // holiday ledger travels on: dates and grades, never an event's
            // title. A sick day is *what the reader said*, and whoever reads
            // this file must not take it for a confirmed illness.
            sickDays: model.sickDayLedger.periods.map {
                HealthDataExport.SickDay(firstDay: $0.firstDay, lastDay: $0.lastDay,
                                         label: $0.label,
                                         severity: $0.severity?.rawValue,
                                         source: $0.source.rawValue)
            },
            // Every figure the app worked out, day by day. These used to be
            // left out as "a cache that replays from samples" — true on this
            // phone, false of a pooled server-side dataset, which is the only
            // place the norms the reader wants can be built. See
            // `HealthDataExport.exportKey(for:)`, which keeps the superseded
            // reasoning, and `docs/norms-and-telemetry.md`.
            generatedInsights: HealthDataExport.derivedSeries(from: model.derivedSeries),
            // Every tag, with the applicability the app inferred and the method
            // that inferred it (B12-1). The occurrences rather than the distinct
            // summaries: a summary is a count, and the dates are what a norm
            // would ever be built from. See `HealthDataExport.tags`.
            tags: model.tags,
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
            predictionOutcomes: outcomes,
            // The four documents that used to be four separate files on this
            // screen and the next one. Backlog B20 — the reader wants one
            // export, and each of these earns its place inside it rather than
            // beside it. See `HealthDataExport.Reports`.
            reports: HealthDataExport.Reports(
                inventory: prose?.inventory ?? "",
                cardOutputs: prose?.cardOutputs ?? "",
                modelInternals: prose?.modelInternals ?? "",
                diagnostics: diagnostics),
            // What the app guessed, what the reader corrected it to, and the
            // artifact it judged — the reader's "data & model improvement",
            // which had no export path at all (backlog R4). **Shaped by their
            // own R5 tier**, because this is the one part of the file that
            // carries an event's words: `HealthDataExport.Improvements` argues
            // that in full, and `Improvements.build` is where the shaping is
            // tested.
            improvements: HealthDataExport.Improvements.build(
                tier: model.sharingPreferences.effectiveTier,
                judgements: model.calendarJudgements,
                outcomes: outcomes),)
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
