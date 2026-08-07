import InsightKit
import SwiftUI

/// **The event confirmation feed** — backlog P32, and the reader's own
/// description of it:
///
/// > the app flags an event ("heart rate spiked 30 mins this evening — sexual
/// > activity?") and I confirm or correct it. GPS map, time, why it was flagged.
///
/// All four are on every card here: the question, the map (a circle — see
/// `EventPlaceMap`), the time, and `FlagEvidence.sentence` for why.
///
/// ## The wording is the honesty control
///
/// The app cannot tell arousal from anxiety from an argument from a cold coming
/// on, because nothing in a heart-rate trace carries that label. So every guess
/// is phrased as a question, every option prints the basis it came from — and
/// `CauseCandidate.Basis.timeOfDay.sentence` says in as many words that nothing
/// measured supports it — and the alternatives are rendered at the same weight
/// as the guess rather than buried behind a "not this?" link. A guess offered as
/// a finding would be the failure this whole app is built against; a guess
/// offered as a question is the learning loop the reader asked for.
///
/// ## Rule 7
///
/// It shows with no data and it is never hidden for want of any. The empty state
/// says what the detector is waiting for (`CoverageGate`, through
/// `EventConfirmationFeed.emptyMessage`) rather than sitting blank.
struct EventConfirmationFeedView: View {
    @State private var model = EventFeedModel.shared
    @State private var answering: FlaggedEvent?
    @State private var confirmingErase = false

    var body: some View {
        List {
            permissionSection
            pendingSection
            rereviewSection
            answeredSection
            accuracySection
            privacySection
        }
        .navigationTitle("Flagged moments")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.feedOpened() }
        .sheet(item: $answering) { event in
            EventAnswerSheet(event: event)
        }
    }

    // MARK: - Permission

    /// **The in-feed half of the reader's condition.**
    ///
    /// Q6 required an onboarding step that explains before prompting; this is
    /// the same explanation for a reader who skipped it, arrived from the Data
    /// tab, or installed before the step existed. It never prompts on appear —
    /// the button is the ask, and the paragraph above it is why.
    @ViewBuilder private var permissionSection: some View {
        Section {
            if model.access.isWorthAsking {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Want a map on these?")
                        .font(.subheadline.weight(.semibold))
                    Text(LocationExplanation.body)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Allow location") { model.requestWhileUsing() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)
            } else if let sentence = model.access.sentence {
                Text(sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The second, separate ask — never made from onboarding. See
            // `LocationCapture.requestBackgroundVisits()`.
            if model.canUpgradeToBackgroundVisits {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Most of these happen while the app is closed, so most of them will have no place at all. iOS can pass on arrivals in the background if you let it — same coarse data, same rules, just delivered when it happens.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Also record places while the app is closed") {
                        model.requestBackgroundVisits()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Location")
        }
    }

    // MARK: - The queue

    @ViewBuilder private var pendingSection: some View {
        Section {
            if model.feed.pending.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.hasRun ? "Nothing to ask about" : "Not looked yet",
                          systemImage: model.hasRun ? "checkmark.circle" : "clock")
                        .font(.subheadline.weight(.medium))
                    Text(model.feed.emptyMessage(access: model.access))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let gate = model.feed.gate, let short = gate.shortLabel {
                        ProgressView(value: gate.progress) {
                            Text(short).font(.caption2).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 2)
            } else {
                ForEach(model.feed.pending) { event in
                    Button { answering = event } label: {
                        FlaggedEventRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Waiting for you")
        } footer: {
            Text("The app has a guess and it is often wrong. Your answer is kept separately from its guess, which is the only way it can honestly show you how often it gets these right.")
        }
    }

    @ViewBuilder private var rereviewSection: some View {
        if !model.feed.needingRereview.isEmpty {
            Section {
                ForEach(model.feed.needingRereview) { row in
                    Button { answering = row.event } label: {
                        FlaggedEventRow(event: row.event, answer: row.judgement.effective)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Worth another look")
            } footer: {
                Text("These moved after you answered — the stretch turned out to be longer or shorter than it looked at the time. Your answer is still there; it is just about a slightly different window now.")
            }
        }
    }

    @ViewBuilder private var answeredSection: some View {
        if !model.feed.answered.isEmpty {
            Section {
                ForEach(model.feed.answered) { row in
                    Button { answering = row.event } label: {
                        FlaggedEventRow(event: row.event, answer: row.judgement.effective,
                                        wasCorrected: row.judgement.wasCorrected)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Answered")
            } footer: {
                Text("Tap any of these to change your mind. The rough place is gone — it is deleted the moment you answer — so these show the time and the numbers only.")
            }
        }
    }

    // MARK: - Accuracy

    private var accuracySection: some View {
        Section {
            Text(model.feed.accuracy.sentence)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.feed.accuracy.answeredWithoutAGuess > 0 {
                Text("\(model.feed.accuracy.answeredWithoutAGuess) more you answered where the app had nothing to offer. Those are not counted either way.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("How often it's right")
        } footer: {
            Text("It needs \(FlaggedEventAccuracy.minimumReviewed) answers before that figure means anything, so it stays quiet until then rather than showing you a number built from three.")
        }
    }

    // MARK: - What is held, and getting rid of it

    private var privacySection: some View {
        Section {
            Text(anchorSentence)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Forget my places", role: .destructive) { model.forgetAllPlaces() }
            Button("Delete everything here", role: .destructive) { confirmingErase = true }
        } header: {
            Text("What this holds")
        } footer: {
            Text("Never a location history. At most \(PlaceAnchorSet.maximumAnchors) rough places, each one a circle a few hundred metres across with a count beside it — enough to tell somewhere you always are from somewhere you don't go, and not enough to say where you were on any given day. A flagged moment keeps a rough position only until you answer it, and no longer than \(FlaggedEventRetention.coordinateLifetimeDays) days either way. Nothing here is ever uploaded, and the export carries the numbers and your answers without the place or your notes.")
        }
        .confirmationDialog("Delete everything here?", isPresented: $confirmingErase,
                           titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.forgetEverything() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This really does delete your answers as well as the places — including the corrections the app learns from. It cannot get them back.")
        }
    }

    private var anchorSentence: String {
        let count = model.anchors.anchors.count
        guard count > 0 else {
            return "No places recorded yet."
        }
        let places = count == 1 ? "1 rough place" : "\(count) rough places"
        if let gate = model.anchors.gate, let sentence = gate.sentence {
            return "\(places). \(sentence)"
        }
        return "\(places), which is enough to tell a usual spot from an unusual one."
    }
}

/// One flagged moment, in the list.
private struct FlaggedEventRow: View {
    let event: FlaggedEvent
    var answer: EventCause?
    var wasCorrected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(event.minutes) min")
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            Text(event.headline)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let answer {
                Label {
                    Text(answer.displayName)
                    // ⚠️ Says which of the two it was. A row that showed only
                    // the final answer would make the app look as though it had
                    // been right every time — which is exactly what keeping the
                    // guess and the correction apart exists to prevent.
                    + Text(wasCorrected ? " — you corrected this" : " — you agreed")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: answer.symbolName)
                }
                .font(.caption)
                .foregroundStyle(Theme.accent)
            } else {
                Text(event.question)
                    .font(.caption).foregroundStyle(Theme.accent)
                if event.place.familiarity != .unknown {
                    Text(event.place.sentence)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The paragraph shown **before** any system prompt, in both places that ask.
///
/// One constant rather than two paragraphs: the onboarding step and the feed's
/// own row are the same promise, and the way two copies of a promise go wrong is
/// that one of them gets edited.
enum LocationExplanation {
    static let title = "Where were you?"

    static let body = "When the app flags a stretch it can't explain, knowing roughly where you were often jogs the memory — home, work, somewhere you'd never been. It uses the coarsest thing iOS offers: arrivals at places you actually stop, rounded to a few hundred metres before anything is written down. It keeps that rough position only until you answer the question, and it never builds a location history — at most a dozen circles with a count beside each, so it can tell a usual spot from an unusual one. Nothing leaves your phone. Everything else works without this; you just won't get the map."
}
