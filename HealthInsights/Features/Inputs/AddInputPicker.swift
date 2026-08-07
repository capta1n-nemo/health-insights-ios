import SwiftUI
import InsightKit

/// The `+` button's list of inputs, at the full height of the screen.
///
/// ## Why this is a sheet and not a `Menu`
///
/// The `+` used to open a SwiftUI `Menu`, which UIKit renders as a popover
/// anchored to the toolbar button. That popover's height is chosen by the
/// system, not by us: once the list outgrows it, it silently becomes a short
/// scrolling column. The reader, 2026-08-07: *"When you click the '+' button,
/// it gets cut off and you have to scroll through the list of add options..
/// make it stretch the length of the screen instead, why cut it short if you
/// don't need to?"*
///
/// **There is no way to make a `Menu` taller** — the cap is UIKit's. So the
/// affordance changes rather than the styling: a sheet at `.large`, which is
/// the full height of the screen and is the only presentation that grows with
/// its content.
///
/// ## Why `.large` and not a detent sized to the content
///
/// A detent measured from today's rows would be a number that goes stale the
/// next time an `InputKind` ships — and this list is *generated* from
/// `InputKind`, so it grows on its own. `.large` is the one choice that never
/// needs revisiting: it is already the tallest a sheet can be, so a longer list
/// takes more of the space it already had rather than needing a new figure.
///
/// ## Why the rows are one line each
///
/// The Settings screen (`AddDataView`) is the *explaining* surface — it carries
/// each input's description and can afford to scroll. This is the *reaching*
/// surface, opened by someone who already knows what they want to add, so a row
/// is an icon, a name and where they stand on it. At thirteen inputs that is
/// the whole list on one screen with no scrolling, which is what was asked for.
struct AddInputPicker: View {
    /// What the reader picked. Written on tap, read by the presenter *after*
    /// this sheet has gone — see `AddInputToolbar` for why it cannot open the
    /// input sheet itself.
    @Binding var choice: InputKind?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(InputGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.kinds) { kind in
                            row(kind)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // **Density is the other half of the fix.** A full-height sheet
            // that still scrolls has not answered *"why cut it short if you
            // don't need to?"* — so the gaps between the three groups are
            // closed up and the rows are given the minimum tappable height
            // rather than the inset-grouped default, which is ~8pt taller.
            // Together those recover roughly a third of the list's height,
            // which is what puts all thirteen inputs on one screen.
            .listSectionSpacing(4)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationTitle("Add data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // The whole point of the change. Stated rather than left to the
        // default so that nobody "tidies" it into `.medium` later.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// One input: what it is, and where the reader stands on it.
    ///
    /// **A blocked input is shown, disabled, with its reason** — the menu used
    /// to omit it, and `InputKind.unavailableReason` exists precisely because
    /// "an input that vanishes is indistinguishable from one that was never
    /// built". There is room for the reason here; there was not in a popover.
    @ViewBuilder private func row(_ kind: InputKind) -> some View {
        let blocked = kind.unavailableReason != nil && model.activeMedication == nil
        Button {
            guard !blocked else { return }
            choice = kind
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbolName)
                    .font(.body)
                    .foregroundStyle(blocked ? Color.secondary : Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title).foregroundStyle(.primary)
                    if blocked, let reason = kind.unavailableReason {
                        Text(reason).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !blocked, let standing = model.standing(for: kind) {
                    Text(standing)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        // Trimmed from the inset-grouped default of ~11pt. The row still
        // clears 44pt — `defaultMinListRowHeight` above holds the floor, so
        // this takes the padding off without taking the tap target with it.
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// The app's one global add affordance: the `+` button, the picker it opens,
/// and every input sheet either can lead to.
///
/// **Two sheets, one at a time.** Presenting the chosen input's sheet from
/// inside the picker would stack a sheet on a sheet and leave the reader two
/// dismissals deep for a one-step action. So the picker records the choice,
/// closes, and this modifier opens the input from `onDismiss` — the point at
/// which the first presentation has genuinely finished, which is the ordering
/// SwiftUI drops the second sheet if you get wrong.
struct AddInputToolbar: ViewModifier {
    @Binding var active: InputKind?
    @State private var isChoosing = false
    @State private var chosen: InputKind?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isChoosing = true
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $isChoosing) {
                handOff()
            } content: {
                AddInputPicker(choice: $chosen)
            }
            .inputSheet($active)
    }

    /// Open the chosen input, once the picker has genuinely gone.
    ///
    /// **The hop is not decoration.** Setting `active` straight from
    /// `onDismiss` was tried first and the input sheet never appeared: the
    /// picker closed and nothing replaced it. UIKit is still tearing down the
    /// first presentation at that point, and a second one requested inside the
    /// same turn of the run loop is dropped without a word. Seen in the
    /// simulator on 2026-08-07 — no test can catch it, because it is a
    /// presentation race and not a value.
    @MainActor private func handOff() {
        guard let kind = chosen else { return }
        chosen = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            active = kind
        }
    }
}

extension AppModel {
    /// Where the reader stands on one input, in one short phrase.
    ///
    /// Shared by the `+` picker and by Settings ▸ Add or update data, because
    /// two surfaces printing different standings for the same input is the
    /// drift `InputKind` exists to end. Exhaustive, so a new input has to say
    /// what its standing figure is — or say explicitly that it hasn't got one,
    /// which one of these does.
    func standing(for kind: InputKind) -> String? {
        switch kind {
        case .profileFacts:
            let all = GroundingKind.directlyEntered
            let set = all.filter { profile.value($0) != nil }.count
            return "\(set) of \(all.count)"
        case .cuffBloodPressure:
            guard let latest = bloodPressureReadings.first else { return nil }
            return "\(Int(latest.systolic.rounded()))/\(Int(latest.diastolic.rounded()))"
        case .substanceEvent:
            let count = substanceEvents.count
            return count == 0 ? nil : "\(count) logged"
        case .medicationRegimen:
            guard let medication = activeMedication else { return nil }
            return medication.brandName ?? medication.compound?.displayName
        case .medicationDose:
            guard let count = activeMedication?.doses.count, count > 0 else { return nil }
            return count == 1 ? "1 dose" : "\(count) doses"
        case .sideEffect:
            let count = sideEffects.count
            return count == 0 ? nil : "\(count) recorded"
        // Since Q7 a report becomes a store of analytes rather than two
        // cholesterol facts, so both document and typed routes now have a
        // standing to show — and it is the **same** figure for both, because
        // the reader has one set of blood results however they arrived. Showing
        // each route only its own count would read as two separate histories.
        case .bloodTestPhoto, .labResultManual:
            let count = labResults.count
            guard count > 0 else { return nil }
            return count == 1 ? "1 value" : "\(count) values"
        case .ecgImport:
            let count = ecgRecords.count
            return count == 0 ? nil : (count == 1 ? "1 recording" : "\(count) recordings")
        case .fileImport:
            return ShotsyIntegration.lastImportDate.map {
                $0.formatted(.relative(presentation: .named))
            }
        case .bodyMeasurements:
            guard let latest = bodyScans.first else { return nil }
            let sites = latest.measurements.sites.count
            return "\(sites) site\(sites == 1 ? "" : "s"), "
                + latest.capturedAt.formatted(.relative(presentation: .named))
        case .bodyType:
            // The reader's word first, the app's estimate second and marked as
            // such — the row must not read as though they chose something they
            // didn't.
            if let chosen = buildOverrideName { return chosen }
            return estimatedBuildName.map { "\($0) (estimated)" }
        case .screenTime:
            let days = screenTimeDaysRecorded
            return days == 0 ? nil : "\(days) \(days == 1 ? "day" : "days")"
        case .readerIdentity:
            // The name if given, the email count otherwise — the reader's own
            // device is the one place the name renders.
            if let name = readerIdentity.name, !name.isEmpty { return name }
            let emails = readerIdentity.allEmails.count
            return emails == 0 ? nil : "\(emails) email\(emails == 1 ? "" : "s")"
        case .holiday:
            // Entered records only, matching `usedInputs` — this row is about
            // what the reader has given, not what the calendar suggested.
            let count = holidayEntries.count
            return count == 0 ? nil : "\(count) recorded"
        case .eventConfirmation:
            // **What is waiting takes precedence over what has been done.** The
            // standing figure is the reason to tap the row, and "3 waiting" is
            // that reason where "12 answered" is a trophy. Falls back to the
            // total once the queue is empty, so the row still says something on
            // a caught-up phone — and to nil on a fresh install, where a bare
            // "0 waiting" would read as a broken detector rather than a quiet
            // fortnight.
            let feed = EventFeedModel.shared.feed
            if !feed.pending.isEmpty { return "\(feed.pending.count) waiting" }
            let answered = feed.accuracy.scored + feed.accuracy.answeredWithoutAGuess
            return answered == 0 ? nil : "\(answered) answered"
        }
    }
}
