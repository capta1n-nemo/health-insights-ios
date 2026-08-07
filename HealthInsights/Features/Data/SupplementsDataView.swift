import SwiftUI
import InsightKit

/// **The Data tab's supplement page** — every bottle, everything its label
/// declares, and what the whole stack adds up to. Backlog Q8 / B3-25.
///
/// Built on `DomainDataScaffold`, which `verify.sh` requires of every
/// `*DataView` here: a title, an optional overview, the entries newest first,
/// and an empty state that reads as empty rather than broken.
///
/// ## What the overview carries, and what it deliberately does not
///
/// No chart. `docs/data-conventions.md` says a data page never hand-rolls one,
/// and there is no shared component that fits: a stack total is a **standing**
/// quantity rather than a series — it changes when the reader changes a bottle,
/// not day by day — so a line chart of it would draw a step function of edits
/// and imply a measurement history nobody took. The per-nutrient shares *are*
/// kept as derived series and trend under Generated insights, which is where a
/// figure with a real day-by-day life belongs.
///
/// Instead the overview is the sum itself, per nutrient, against its published
/// limit — which is the one thing this domain has that no other view of it does.
struct SupplementsDataView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.supplements.title,
            entriesHeader: "Products",
            entryCount: model.supplementEntries.count,
            emptyHeadline: "No supplements yet",
            emptyMessage: "Nothing on this phone senses a supplement, so this "
                + "page fills up only when you enter a bottle. Add one from the "
                + "plus menu and everything you take is added up ingredient by "
                + "ingredient against the published upper intake limits.",
            emptySymbol: "pills",
            overview: { overview },
            rows: { rows })
    }

    @ViewBuilder private var overview: some View {
        if let stack = model.supplementStackSummary, !stack.totals.isEmpty {
            Section {
                ForEach(stack.totals) { total in
                    SupplementNutrientRow(total: total)
                }
            } header: {
                Text("Summed across your stack")
            } footer: {
                Text(footer(stack))
            }
        }
    }

    private func footer(_ stack: SupplementStackModel.Output) -> String {
        var text = "Upper intake limits published by the US National Academies"
        if let stage = stack.lifeStage {
            text += ", for ages \(stage.displayName)"
        }
        text += ". They are population reference values for a person who is not "
            + "pregnant or breastfeeding. This page states what your stack "
            + "contains and what the published figure is — it is not advice."
        if stack.unresolvedCount > 0 {
            text += " \(stack.unresolvedCount) "
                + "\(SectionCaveat.plural(stack.unresolvedCount, "ingredient")) "
                + "declare no usable amount, so those totals are floors and are "
                + "marked with ≥."
        }
        return text
    }

    @ViewBuilder private var rows: some View {
        ForEach(model.supplementEntries) { entry in
            NavigationLink {
                SupplementProductDataView(entry: entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.product.name)
                        Spacer()
                        Text(SupplementFormatting.number(entry.servingsPerDay) + " × daily")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(subtitle(entry))
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func subtitle(_ entry: SupplementEntry) -> String {
        var parts: [String] = ["\(entry.product.ingredients.count) "
            + "\(SectionCaveat.plural(entry.product.ingredients.count, "ingredient"))"]
        let unstated = entry.product.ingredients.filter { !$0.amount.isKnown }.count
        if unstated > 0 { parts.append("\(unstated) unstated") }
        if let stoppedOn = entry.stoppedOn {
            parts.append("stopped \(stoppedOn.formatted(.relative(presentation: .named)))")
        }
        parts.append(entry.product.source.displayName.lowercased())
        return parts.joined(separator: " · ")
    }
}

/// One bottle's label, as the reader entered it.
///
/// Read-only, which is the Data tab's convention: it is the record of what was
/// given, and the place to change it is the input surface the whole app opens
/// through `InputKind.supplement`.
struct SupplementProductDataView: View {
    let entry: SupplementEntry

    var body: some View {
        DomainDataScaffold(
            title: entry.product.name,
            entriesHeader: "On the label",
            entryCount: entry.product.ingredients.count,
            emptyHeadline: "No ingredients recorded",
            emptyMessage: "This product was saved without any Supplement Facts "
                + "lines, so there is nothing here to add up. Edit it from the "
                + "plus menu to enter what the label declares.",
            emptySymbol: "pills",
            overview: { overview },
            rows: { rows })
    }

    @ViewBuilder private var overview: some View {
        Section {
            if let brand = entry.product.brand {
                LabeledContent("Brand", value: brand)
            }
            if let serving = entry.product.servingDescription {
                LabeledContent("One serving", value: serving)
            }
            LabeledContent("Servings a day",
                           value: SupplementFormatting.number(entry.servingsPerDay))
            LabeledContent("Started",
                           value: entry.startedOn.formatted(date: .abbreviated, time: .omitted))
            if let stoppedOn = entry.stoppedOn {
                LabeledContent("Stopped",
                               value: stoppedOn.formatted(date: .abbreviated, time: .omitted))
            }
            LabeledContent("Where this came from", value: entry.product.source.displayName)
        } footer: {
            Text(entry.product.source.caveat
                 ?? "Amounts below are per serving, exactly as you entered them "
                    + "from the label. The totals elsewhere multiply them by your "
                    + "servings a day.")
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(entry.product.ingredients) { ingredient in
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ingredient.labelText.isEmpty
                         ? (ingredient.nutrient?.displayName ?? "Unnamed")
                         : ingredient.labelText)
                    Spacer()
                    Text(ingredient.amount.displayText)
                        .font(.caption)
                        .foregroundStyle(ingredient.amount.isKnown ? .secondary : Color(Theme.warn))
                        .monospacedDigit()
                }
                if let nutrient = ingredient.nutrient {
                    Text(nutrient.displayName)
                        .font(.caption2).foregroundStyle(.tertiary)
                } else {
                    // ⚠️ Said out loud rather than left blank. A line that is
                    // simply absent from the totals reads as a bug; a line that
                    // says why it is absent is a finding.
                    Text("Not weighed — no upper intake level is published for it")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
