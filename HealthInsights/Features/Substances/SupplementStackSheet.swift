import SwiftUI
import InsightKit

/// **The supplement input surface** — backlog Q8 / B3-25.
///
/// The stack, and one screen behind it for each bottle. Reached from the Today
/// `+` menu, from Settings ▸ Add or update data, and from the card's "View &
/// add" — all three through `InputKind.supplement`, which is the whole point of
/// that enum.
///
/// ## Why the entry is a form rather than a scanner
///
/// A Supplement Facts panel is a table of names, numbers and units, and the
/// numbers are the thing that must be right — a mistyped zero is a tenfold
/// error in a total the card then compares against a published limit. So the
/// typed path is the primary one and is complete on its own, offline, forever.
/// Scanning is offered as a way to *fill this form in*, never as a way to skip
/// it: whatever a parse produces lands in these fields for the reader to
/// confirm, which is the same contract `ImportLabView` has for a pathology
/// report.
///
/// ⚠️ **The unit picker is not optional and the form will not let it be.** An
/// amount with no unit is not a quantity, and this app's whole claim about this
/// card is that it converts before it adds. Where a label gives IU, the form
/// asks which *form* too — see `NutrientAmount.converted(to:)` for why an
/// unlabelled IU figure for vitamin A or E cannot honestly be converted.
struct SupplementStackSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: SupplementEntry?
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if model.supplementEntries.isEmpty {
                    Section {
                        Text("Nothing on this phone knows what is in a supplement "
                             + "bottle — no wearable senses it and Apple Health has "
                             + "no record of it. Add what you take and every "
                             + "ingredient is added up across the whole stack and "
                             + "shown against the published upper intake limits for "
                             + "your age. It works with no network at all.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(model.supplementEntries) { entry in
                        Button { editing = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deleteSupplementEntry(id: model.supplementEntries[index].id)
                        }
                    }
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add a supplement", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Your stack")
                } footer: {
                    Text("Servings a day is how much you actually take, not what "
                         + "the label suggests — the totals are built from yours.")
                }

                if let stack = model.supplementStackSummary {
                    totalsSection(stack)
                }
            }
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAdding) {
                SupplementProductEditor(entry: nil)
            }
            .sheet(item: $editing) { entry in
                SupplementProductEditor(entry: entry)
            }
        }
    }

    private func row(_ entry: SupplementEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.product.name)
                Spacer()
                Text(SupplementFormatting.number(entry.servingsPerDay)
                     + " × daily")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(subtitle(entry))
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func subtitle(_ entry: SupplementEntry) -> String {
        let unstated = entry.product.ingredients.filter { !$0.amount.isKnown }.count
        var parts = ["\(entry.product.ingredients.count) "
                     + "\(SectionCaveat.plural(entry.product.ingredients.count, "ingredient"))"]
        if unstated > 0 {
            parts.append("\(unstated) with no stated amount")
        }
        parts.append(entry.product.source.displayName.lowercased())
        return parts.joined(separator: " · ")
    }

    /// The sum, on the same screen as the entry — because the sum is the reason
    /// anybody is typing a label in, and making them close this and find a card
    /// to see it would hide the payoff behind the work.
    @ViewBuilder private func totalsSection(_ stack: SupplementStackModel.Output) -> some View {
        Section {
            ForEach(stack.totals) { total in
                SupplementNutrientRow(total: total)
            }
        } header: {
            Text("What it adds up to")
        } footer: {
            Text(stack.unresolvedCount > 0
                 ? "\(stack.unresolvedCount) \(SectionCaveat.plural(stack.unresolvedCount, "ingredient")) "
                   + "declare no usable amount, so those totals are shown as "
                   + "\"at least\". An unknown amount is never counted as nought. "
                   + "These are published reference figures, not advice."
                 : "Published upper intake limits from the US Dietary Reference "
                   + "Intakes, for your age band. These are reference figures, "
                   + "not advice.")
        }
    }
}

/// One nutrient's total against its published limit.
///
/// ⚠️ **It states the number and the limit and stops.** No instruction, no
/// "consider reducing", no colour that reads as an alarm beyond the app's own
/// warn tint — exceeding an upper limit is information.
struct SupplementNutrientRow: View {
    let total: SupplementStackModel.NutrientTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.nutrient.displayName)
                Spacer()
                Text((total.isComplete ? "" : "≥ ")
                     + SupplementFormatting.amount(total.countedTotal,
                                                   unit: total.nutrient.canonicalUnit))
                    .monospacedDigit()
                    .foregroundStyle(total.isAtOrOverLimit ? Theme.warn : .secondary)
            }
            .font(.subheadline)

            Text(comparison)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !total.isComplete {
                Text("\(total.unresolved.count) "
                     + "\(SectionCaveat.plural(total.unresolved.count, "ingredient")) "
                     + "with no stated amount, so this is a floor: "
                     + (total.unresolved.first?.reason ?? ""))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var comparison: String {
        switch total.limit {
        case .limit(let value):
            var text = "\(SupplementFormatting.percent(total.shareOfLimit ?? 0)) of the "
                + "published upper limit of "
                + "\(SupplementFormatting.amount(value, unit: total.nutrient.canonicalUnit))"
            if let reference = total.recommended.value, let label = total.recommended.label {
                text += "; the \(label) for you is "
                    + SupplementFormatting.amount(reference, unit: total.nutrient.canonicalUnit)
            }
            return text + "."
        case .noLimitPublished(let caution):
            return caution
        case .outsideTable(let missing):
            return "No limit resolved. \(missing)"
        }
    }
}
