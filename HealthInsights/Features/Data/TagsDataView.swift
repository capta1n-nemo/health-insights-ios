import SwiftUI
import InsightKit

/// **The Tags page — where a tag lives primarily.**
///
/// The reader's framing, 2026-08-07: a tag *"will live primarily in its tags
/// section, and whatever it is (eg Kayaking) will have an 'applicability' of
/// 'Activity & mobility'"*. So this page is organised by applicability, and
/// every group carries its own "what this is" sentence (standing rule 11) — a
/// reader must never meet "Activity & mobility" as a bare heading over their own
/// word.
///
/// ## What the row says, and why it says so much
///
/// An applicability is an **inference**, and this repo's rule is that a modelled
/// thing is never dressed as a measured one. So each row prints the method that
/// decided it — *from the tag's own type*, *matched on this device*, *worked out
/// on this device*, *you said so* — and its confidence. That is not decoration:
/// it is the difference between the app saying "Oura calls this alcohol" and the
/// app saying "a language model read one word and guessed".
///
/// ## The reader can overrule it, and their answer sticks
///
/// A picker on each row writes a `.reader` mapping, which outranks every other
/// method in `TagMappingRank` — so the next sync re-classifying the same word
/// cannot quietly undo it.
///
/// ⚠️ **The picker is not an `InputKind`, and that is deliberate.** `InputKind`
/// is for data the reader *gives* the app about themselves — a weight, a dose, a
/// side effect — and the four surfaces it drives (the `+` menu, Settings ▸ Add
/// or update data, a card's "View & add", the "Improve your health" nudge) would
/// all read as nonsense for this. Correcting a heading the app inferred is a
/// **review**, and the app already has that pattern: `CalendarEventJudgement`
/// lets the reader disagree with the work/personal/travel classifier and is not
/// an `InputKind` either. Load `add-data-or-input` before deciding otherwise.
///
/// ⚠️ **No card is fed from here.** `TagApplicability.candidateNote` prints
/// which card a group *could* contribute to, marked "not used yet", because the
/// reader was explicit that activity tags become *candidates at the next
/// review* rather than inputs. Wiring one is a decision, not a follow-up.
struct TagsDataView: View {
    @Environment(AppModel.self) private var model

    /// Computed once per body pass and handed to the three places that need it.
    /// `distinctTags()` walks every occurrence, and this page asked for it three
    /// times — for the count, for the groups, and for the unplaced tally.
    private var summaries: [TagSummary] { model.tags.distinctTags() }

    private var groups: [(applicability: TagApplicability, tags: [TagSummary])] {
        model.tags.groupedByApplicability()
    }

    var body: some View {
        let all = summaries
        DomainDataScaffold(
            title: DataDomain.tags.title,
            entriesHeader: "Tags",
            entryCount: all.count,
            emptyHeadline: "No tags yet",
            emptyMessage: "Tags you add in Oura — a sport, a late night, a sick day — appear here once your ring has synced, grouped by what each one is about.",
            emptySymbol: "tag",
            overview: {
                if !all.isEmpty { overviewSection(all) }
            },
            rows: {
                // `DomainDataScaffold` owns the one `Section`, so a group's
                // heading is a *row* rather than a section header — deliberately
                // the scaffold's shape rather than this page inventing its own,
                // which is the convention `verify.sh` enforces.
                ForEach(groups, id: \.applicability) { group in
                    groupHeadingRow(group.applicability)
                    ForEach(group.tags) { summary in
                        TagRow(summary: summary,
                               applicability: group.applicability)
                    }
                }
            })
    }

    /// What this page is, and — honestly — what decided the headings on it.
    @ViewBuilder private func overviewSection(_ all: [TagSummary]) -> some View {
        Section {
            Text(DataDomain.tags.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text(methodStanding(all))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("What this is")
        }
    }

    /// One sentence about where these classifications came from.
    ///
    /// **Names the tags it could not place**, rather than letting the reader
    /// wonder why some sit under "Not yet classified". A feature that silently
    /// does less on hardware with no on-device model is a feature that reads as
    /// broken; saying so, and offering the menu, is the honest alternative.
    private func methodStanding(_ all: [TagSummary]) -> String {
        let unplaced = all.filter { $0.mapping.applicability == .unclassified }.count
        let base = unplaced == 0
            ? "Every tag here has been placed."
            : "\(unplaced) tag\(unplaced == 1 ? " has" : "s have") not been placed. \(unplaced == 1 ? "It is" : "They are") still kept exactly as you wrote \(unplaced == 1 ? "it" : "them")."
        return base + " Grouping is worked out on this device — from your ring's own tag types, from the words in the tag, and where neither settles it, by the on-device language model. Nothing about a tag is sent anywhere. Tap any tag to change its group."
    }

    @ViewBuilder private func groupHeadingRow(_ applicability: TagApplicability) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(applicability.rawValue, systemImage: applicability.symbolName)
                .font(.caption.weight(.semibold))
            Text(applicability.summary)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = applicability.candidateNote {
                Text(note)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One tag, its dates, how it was placed, and a way to disagree.
private struct TagRow: View {
    @Environment(AppModel.self) private var model
    let summary: TagSummary
    let applicability: TagApplicability

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                // No `lineLimit`: a tag's whole subject is its name, and this
                // is the row the Data tab already learned that lesson on (see
                // `DataTabView.rawFieldRow`).
                Text(summary.name)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(summary.count)×")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Text(datesLine)
                .font(.caption).foregroundStyle(.secondary)
            // **The provenance, on the row.** Standing rule 6: an estimate
            // states its own uncertainty, and this heading is an estimate.
            Text(provenanceLine)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("What this tag is about", selection: Binding(
                get: { applicability },
                set: { model.setTagApplicability($0, forTagKey: summary.key) })) {
                ForEach(TagApplicability.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var datesLine: String {
        let last = summary.lastUsed.formatted(.relative(presentation: .named))
        guard summary.count > 1 else { return "Last used \(last)" }
        return "Last used \(last) · first \(summary.firstUsed.formatted(date: .abbreviated, time: .omitted))"
    }

    private var provenanceLine: String {
        let percent = Int((summary.mapping.confidence * 100).rounded())
        switch summary.mapping.method {
        case .reader:
            return summary.mapping.rationale
        case .unresolved:
            return summary.mapping.rationale
        default:
            return "\(summary.mapping.method.title) · \(percent)% confident. \(summary.mapping.rationale)"
        }
    }
}
