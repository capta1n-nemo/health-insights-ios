import InsightKit
import SwiftUI

/// **Answering one flagged moment** — the input surface P32 asks for.
///
/// Everything the reader needs to remember what was going on, then the answer.
/// In order: when, why it was flagged (the measured half), the map, and then the
/// options.
///
/// ## Confirm and correct are one gesture, not two
///
/// There is no separate "yes, that's right" button beside a list of
/// alternatives. There is one list with the app's guess at the top of it, and
/// tapping the guess *is* confirming. That is deliberate: a layout with a big
/// green tick beside the guess and a small "or pick something else" link makes
/// agreeing the cheap option, and an app measuring its own accuracy must not put
/// its thumb on that scale.
///
/// The distinction survives where it is measurable rather than where it is
/// visible — `FlaggedEventJudgement` records `isConfirmed` when the reader
/// picked the guess and a `correction` when they did not, which is what
/// `FlaggedEventAccuracy` counts.
struct EventAnswerSheet: View {
    let event: FlaggedEvent

    @State private var model = EventFeedModel.shared
    @State private var choice: EventCause?
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    /// Everything that can be answered: what the detector offered, then the rest
    /// of the vocabulary. **The full list is always reachable** — a reader whose
    /// answer is not in the app's shortlist must never be pushed into the
    /// nearest wrong one.
    private var options: [CauseCandidate] {
        var out = event.candidates
        let offered = Set(out.map(\.cause))
        out += EventCause.allCases
            .filter { !offered.contains($0) }
            .map { CauseCandidate(cause: $0, weight: -1, basis: .alwaysOffered) }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                evidenceSection
                if event.place.canDrawMap { mapSection } else { placeSection }
                optionsSection
                noteSection
                if existingAnswer != nil { reopenSection }
            }
            .navigationTitle("What was this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(choice == nil)
                }
            }
            .onAppear { choice = existingAnswer }
        }
    }

    private var existingAnswer: EventCause? {
        (model.feed.answered + model.feed.needingRereview)
            .first { $0.event.id == event.id }?.judgement.effective
    }

    // MARK: - Why it was flagged

    private var evidenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.headline)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(event.start.formatted(date: .complete, time: .shortened)) — \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(event.evidence.sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Why it was flagged")
        } footer: {
            // The measured/guessed line, said plainly on the screen where the
            // reader is about to be asked to guess with it.
            Text("That much is measured. What it *was* is not — nothing in a heart-rate trace says whether you were nervous, excited or coming down with something, so the app is asking rather than telling.")
        }
    }

    // MARK: - Where

    private var mapSection: some View {
        Section {
            EventPlaceMap(place: event.place)
            Text(event.place.sentence)
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Where you were")
        }
    }

    private var placeSection: some View {
        Section {
            Text(event.place.sentence)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let permission = model.access.sentence {
                Text(permission)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Where you were")
        }
    }

    // MARK: - The answer

    private var optionsSection: some View {
        Section {
            ForEach(options) { candidate in
                Button { choice = candidate.cause } label: {
                    row(candidate)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("What was going on?")
        } footer: {
            Text("The first few are the app's own shortlist, and it says underneath each one what put it there. Everything else the app knows how to record is below them — pick whichever is true, not whichever is nearest.")
        }
    }

    private func row(_ candidate: CauseCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: candidate.cause.symbolName)
                .foregroundStyle(choice == candidate.cause ? Theme.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.cause.displayName).foregroundStyle(.primary)
                // ⚠️ The basis line, on every shortlisted option. A guess from
                // the time of day and a guess from something the reader wrote
                // down look identical without it.
                if candidate.weight >= 0 {
                    Text(candidate.why ?? candidate.basis.sentence)
                        .font(.caption2)
                        .foregroundStyle(candidate.basis.isEvidenceBacked ? .secondary : .tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if choice == candidate.cause {
                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private var noteSection: some View {
        Section {
            TextField("Optional", text: $note, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("Anything else")
        } footer: {
            Text("Stays on this phone. Unlike the numbers, your own words about a flagged half-hour usually describe other people too, so they are left out of the export entirely.")
        }
    }

    private var reopenSection: some View {
        Section {
            Button("Clear my answer", role: .destructive) {
                model.reopen(event)
                dismiss()
            }
        } footer: {
            Text("Puts it back in the queue. The rough place will not come back — it was deleted when you answered, and the app kept no second copy.")
        }
    }

    private func save() {
        guard let choice else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Picking the app's own guess is a confirmation; picking anything else
        // is a correction. Recorded as two different things because
        // `FlaggedEventAccuracy` counts them differently — and because "I agreed"
        // and "I happened to choose the same word" are the same event only when
        // the app offered the word first.
        let agreed = choice == event.guess
        model.answer(event,
                     correction: agreed ? nil : choice,
                     note: trimmed.isEmpty ? nil : trimmed,
                     confirmed: agreed)
        dismiss()
    }
}

/// The feed, presented as a sheet.
///
/// **Named `…Sheet` on purpose**: `verify.sh` requires every `*Sheet` view under
/// `Features/` to be reachable from `AddDataView.swift`'s master switch, which
/// is the check that catches an input nobody declared. This one is declared —
/// `InputKind.eventConfirmation` opens it.
struct EventConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EventConfirmationFeedView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
