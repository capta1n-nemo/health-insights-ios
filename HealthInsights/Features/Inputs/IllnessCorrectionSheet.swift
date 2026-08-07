import SwiftUI
import InsightKit

/// **Telling the app what a day actually was** — backlog `B11-2`, the reader's
/// *"an estimated sickness they can correct — type and severity, similar to how
/// you can correct a work or travel event (same concept - then we can learn
/// from it)."*
///
/// The same concept, deliberately: `EventAnswerSheet` lets the reader confirm or
/// correct a classified calendar event, `CalendarEventJudgement` stores the
/// guess and the answer in separate fields, and the app can therefore say how
/// often it was right. This is that, one level up — about a whole day rather
/// than a block in a calendar — and `IllnessJudgement` keeps the same three
/// fields for the same reason.
///
/// ## Two answers, not one
///
/// **Confirm** and **correct** are different acts and are stored differently.
/// "I looked and you were right" is a label; "I have not looked" is not, and
/// treating them as one would inflate any accuracy figure the app ever
/// computes. So the sheet has an explicit *"That's right"* alongside the
/// pickers.
///
/// ## ⚠️ What the reader is allowed to say that the app is not
///
/// `IllnessKind.correctable` excludes `.unknown` — that case is the app's word
/// for its own ignorance, and offering it to a person answering about their own
/// week would be asking them to shrug. **`.severe` is likewise theirs alone**:
/// `IllnessEstimator.measuredGrade` never returns it, because a detector whose
/// prospective positive predictive value is 4–12%
/// (`docs/illness-detection-evidence-2026-08-07.md`) grading somebody severely
/// ill is the overreach this whole feature is written against.
///
/// Marking a day as anything other than "not ill" writes it into the reader's
/// sick-day record (`AppModel.sickDayLedger`'s entered half), which is the
/// second source that ledger has always had room for and never had.
struct IllnessCorrectionSheet: View {
    let day: Date
    /// The app's guess, carried in so the sheet can store it beside the answer.
    /// ⚠️ Stored only the first time a day is answered — see
    /// `DataStore.recordIllnessReview`.
    let estimate: IllnessEstimate
    /// The reader's previous answer, where they have given one.
    let existing: IllnessJudgement?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var kind: IllnessKind = .notIll
    @State private var severity: CalendarEventClassification.SickSeverity = .unstated
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Day",
                                   value: day.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("The app guessed", value: estimate.assessment.summary)
                } footer: {
                    Text(estimate.uncertainty)
                }

                Section {
                    Picker("What was it?", selection: $kind) {
                        ForEach(IllnessKind.correctable) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    if kind != .notIll {
                        Picker("How bad?", selection: $severity) {
                            ForEach(CalendarEventClassification.SickSeverity.allCases) {
                                Text($0.title).tag($0)
                            }
                        }
                    }
                } footer: {
                    Text(kind == .notIll
                         ? "Saying you were not ill answers the app's guess. It does not remove a day your calendar recorded as illness — change that where it was entered."
                         : "A day you mark here joins your sick-day record, and this card reads it: what you say about a day counts for more than what your overnight readings did.")
                }

                Section {
                    Button("Save my answer") { save(correction: assessment) }
                    // ⚠️ **A distinct act, not the same button with no edits.**
                    // "Confirmed correct" and "not yet looked at" are different
                    // records; this is the only control that writes the first.
                    Button("That's right — leave it as it is") {
                        save(correction: nil, confirmed: true)
                    }
                } footer: {
                    Text("Your answer is stored beside the app's guess, never over it. That is what lets it show you how often it was right — and it is the only way it can learn anything from this.")
                }
            }
            .navigationTitle("Were you ill?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var assessment: IllnessAssessment {
        IllnessAssessment(kind: kind, severity: kind == .notIll ? nil : severity)
    }

    /// Seed from the reader's own previous answer where they gave one, and from
    /// the app's guess otherwise.
    ///
    /// ⚠️ **`.unknown` seeds as `.notIll`**, because `.unknown` is not offered:
    /// a picker whose selection is not among its options renders blank, and a
    /// blank picker over a health question is worse than a wrong default the
    /// reader can see and change.
    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let starting = existing?.effective ?? estimate.assessment
        kind = starting.kind == .unknown ? .notIll : starting.kind
        severity = starting.severity ?? .unstated
    }

    private func save(correction: IllnessAssessment?, confirmed: Bool = false) {
        model.recordIllnessReview(day: day, estimate: estimate,
                                  correction: correction, confirmed: confirmed)
        dismiss()
    }
}
