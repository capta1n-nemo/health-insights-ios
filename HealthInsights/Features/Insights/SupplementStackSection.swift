import SwiftUI
import InsightKit

/// **The stack card's own picture: every nutrient, summed, against its published
/// limit.** Backlog Q8 / B3-25.
///
/// Its own file, per the rule — the smallest possible edit to
/// `InsightDetailView` is one `case`.
///
/// ## Why the table is the card
///
/// The card's headline is one number: the largest share of any published upper
/// limit. That is the right *summary* and it is not the finding — the finding is
/// which nutrient, from which bottles, and how near which figure. A card that
/// reported "142%" and made the reader open the Data tab to learn what of would
/// be reporting an alarm without its subject.
///
/// ## What it will not draw
///
/// **No chart, and the reason is the same one `SupplementsDataView` gives.** A
/// stack total is a standing quantity — it changes when a bottle changes, not
/// day by day — so a line through it would draw a step function of the reader's
/// own edits and imply a measurement history that does not exist. The
/// per-nutrient shares are kept as derived series and trend under Generated
/// insights, where a figure with a real daily life belongs. This section is
/// therefore exempt from the substance-shading rule by having no `Chart {}` at
/// all rather than by claiming an exemption.
///
/// ⚠️ **Nothing here tells anyone to do anything.** Every row states a total and
/// the published figure beside it. Exceeding an upper intake level is
/// information; the app does not add an instruction to it, and
/// `SupplementStackWordingTests` holds that against the strings the model
/// produces.
struct SupplementStackSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let stack = model.supplementStackSummary {
            InsightSection(
                title: "Every ingredient, summed",
                icon: "pills",
                trailing: trailing(stack),
                caveat: caveat(stack)) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(stack.totals) { total in
                            SupplementNutrientRow(total: total)
                        }
                        if stack.unrecognisedIngredientCount > 0 {
                            Text("\(stack.unrecognisedIngredientCount) other "
                                 + "\(SectionCaveat.plural(stack.unrecognisedIngredientCount, "ingredient")) "
                                 + "in your stack — herbs, amino acids, probiotics — "
                                 + "are kept as you entered them and are not shown "
                                 + "here. No upper intake level has been published "
                                 + "for them to be shown against.")
                                .font(.caption).foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

            SupplementProductsSection(stack: stack)
        }
    }

    private func trailing(_ stack: SupplementStackModel.Output) -> String? {
        guard let share = stack.highestShare else { return nil }
        return SupplementFormatting.percent(share)
    }

    /// ⚠️ **`partial` whenever anything is unresolved**, which is the honest
    /// classification: some of the inputs to these totals are genuinely absent,
    /// and every one of them makes a total a floor. `.none` otherwise — a sum of
    /// declared amounts is a report of what the labels say, and a section
    /// entitled to say nothing more should say nothing more.
    private func caveat(_ stack: SupplementStackModel.Output) -> SectionCaveat {
        guard stack.unresolvedCount > 0 else { return .none }
        return SectionCaveat.computed(
            .partial,
            "\(stack.unresolvedCount) "
                + "\(SectionCaveat.plural(stack.unresolvedCount, "ingredient")) "
                + "declare no usable amount — a proprietary blend, or a unit that "
                + "cannot be converted without the form named. Those totals are "
                + "marked ≥ and are floors rather than figures. An unknown amount "
                + "is never counted as nought.")
    }
}

/// **Which bottles each figure came from**, because "142% of the zinc limit" is
/// not actionable information until the reader knows which two of their four
/// products are carrying it.
struct SupplementProductsSection: View {
    let stack: SupplementStackModel.Output

    var body: some View {
        InsightSection(
            title: "What it came from",
            trailing: "\(stack.products.count)",
            caveat: .none,
            expansion: .collapsed(preview: preview)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(stack.products) { product in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.subheadline)
                            Text(detail(product))
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
    }

    /// ⚠️ Required by `SectionExpansion.collapsed` and correctly so — a closed
    /// section showing only its title is a locked door. It names the bottles,
    /// because "which of my products has the zinc in it" is the question this
    /// section answers and the reader should be able to decide from the outside
    /// whether they need it opened.
    private var preview: String {
        let names = stack.products.prefix(3).map(\.name).joined(separator: ", ")
        return stack.products.count > 3
            ? "\(names) and \(stack.products.count - 3) more"
            : names
    }

    private func detail(_ product: SupplementProduct) -> String {
        let unstated = product.ingredients.filter { !$0.amount.isKnown }.count
        var text = "\(product.ingredients.count) "
            + "\(SectionCaveat.plural(product.ingredients.count, "ingredient"))"
        if unstated > 0 {
            text += ", \(unstated) with no stated amount"
        }
        text += " · \(product.source.displayName.lowercased())"
        if let caveat = product.source.caveat {
            text += ". \(caveat)"
        }
        return text
    }
}
