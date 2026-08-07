import SwiftUI
import InsightKit

/// **The review the reader asked for — and the thing that keeps a tag out of a
/// score until they have done it.** Backlog `B12-3`.
///
/// Their instruction, 2026-08-07: activity-related tags *"become candidates for
/// cards at the next review — not wired automatically."* A candidate that nobody
/// can see is not a candidate, it is a dropped requirement; so this page is the
/// whole of `B12-3`. It lists every tag whose category names a card it could
/// contribute to, says what it could contribute to, and takes the reader's
/// answer.
///
/// ## The one thing this page must never do is flatter itself
///
/// A review screen with a switch on every row reads as a settings screen, and a
/// reader who flips "Should count" would reasonably believe their kayaking is now
/// in their fitness score. **It is not, and this page says so on every row and in
/// its own header.** Wiring a self-reported word into a computed figure is a
/// change to the app — new inputs, a weight, an uncertainty, an export entry —
/// not a boolean somebody toggled. `TagCardCandidate.isWiredToAnyCard` is
/// `false`, a test holds it there, and this page is honest about it in prose
/// rather than relying on the reader to guess.
///
/// So "Should count" means *noted for whoever builds it*. That is a smaller
/// promise than a toggle implies, and it is the true one.
struct TagCardCandidatesView: View {
    @Environment(AppModel.self) private var model

    private var candidates: [TagCardCandidate] { model.tagCardCandidates }

    var body: some View {
        let all = candidates
        DomainDataScaffold(
            title: "Card candidates",
            entriesHeader: "Candidates",
            entryCount: all.count,
            emptyHeadline: "No candidates yet",
            // ⚠️ Standing rule 7 — an empty state says what it is waiting for.
            // Both halves are actionable by the reader, which is why they are
            // spelled out rather than reduced to "nothing here".
            emptyMessage: "A tag becomes a candidate once the app has worked out what it is about and that subject matches a card — a sport becomes a Fitness candidate, a sick day a Symptom radar one. Sync your ring, or place a tag yourself on the Tags page, and it will appear here.",
            emptySymbol: "questionmark.folder",
            overview: {
                if !all.isEmpty { overviewSection(all) }
            },
            rows: {
                ForEach(all) { candidate in
                    CandidateRow(candidate: candidate)
                }
            })
    }

    @ViewBuilder private func overviewSection(_ all: [TagCardCandidate]) -> some View {
        Section {
            Text("These tags are about something a card already measures. **None of them is being used**, and none will start being used because of anything on this page.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("A tag is a word you typed. Nothing measured it and nothing has checked it against anything, so letting one move a score is a decision about your own data rather than a setting — which is why you are being asked instead of told. Your answer here is kept and read at the next review.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(standing(all))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("What this is")
        }
    }

    /// How far through the review the reader is, said plainly.
    private func standing(_ all: [TagCardCandidate]) -> String {
        let unreviewed = model.tagCandidateDecisions.unreviewedCount(among: all)
        guard unreviewed > 0 else {
            return "You have answered for all \(all.count) of them."
        }
        if unreviewed == all.count {
            return "\(all.count) waiting for an answer."
        }
        return "\(unreviewed) of \(all.count) still waiting for an answer."
    }
}

/// One candidate tag, what it could feed, and the reader's verdict.
private struct CandidateRow: View {
    @Environment(AppModel.self) private var model
    let candidate: TagCardCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                // No `lineLimit` — a tag's whole subject is its name, the lesson
                // `DataTabView.rawFieldRow` and `TagsDataView` both already carry.
                Text(candidate.summary.name)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(candidate.summary.count)×")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Label(candidate.applicability.rawValue,
                  systemImage: candidate.applicability.symbolName)
                .font(.caption).foregroundStyle(.secondary)
            Text(candidate.candidateNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // **The provenance, again, and not as a formality.** How the app
            // decided this tag's subject is exactly what a reader needs to judge
            // whether it should feed anything — a stem match on their own word is
            // a different proposition from a language model's guess.
            Text(provenanceLine)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Should this count?", selection: Binding(
                get: { candidate.decision },
                set: { model.setTagCandidateDecision($0, forTagKey: candidate.summary.key) })) {
                ForEach(TagCardCandidateDecision.allCases) { option in
                    Label(option.title, systemImage: option.symbolName).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            // ⚠️ The line that stops the picker reading as a switch. Every one of
            // the three says, in its own words, that nothing is using this tag.
            Text(candidate.decision.detail)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var provenanceLine: String {
        let mapping = candidate.summary.mapping
        switch mapping.method {
        case .reader, .unresolved:
            return mapping.rationale
        default:
            let percent = Int((mapping.confidence * 100).rounded())
            return "\(mapping.method.title) · \(percent)% confident."
        }
    }
}
