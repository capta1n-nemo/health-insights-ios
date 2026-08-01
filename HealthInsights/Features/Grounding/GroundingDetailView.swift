import SwiftUI
import InsightKit

/// The sub-menu behind "View & add details": every fact this card asks for,
/// whether or not it is set, each opening its own entry sheet.
///
/// These rows used to sit inline on the card. They were the "view" half of
/// "View & add" and they are still that — showing the satisfied ones is what
/// lets a mistyped value be corrected, which the old "Add these for a better
/// estimate" card could not do, because it listed only what was missing.
///
/// What changed is *where*: a card says where you stand, and the values you gave
/// live behind the button. Listing them on the card meant the insight screen
/// carried a copy of the first rows of this one.
struct GroundingDetailView: View {
    let kinds: [GroundingKind]
    let unmetRequirements: [GroundingRequirement]

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var groundingKind: GroundingKind?

    private var unmetKinds: Set<GroundingKind> {
        Set(unmetRequirements.map(\.kind))
    }

    private var summary: ContributionSummary {
        ContributionSummary.facts(
            set: kinds.filter { !unmetKinds.contains($0) }.count,
            of: kinds.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Card { GroundedSummary(summary: summary) }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(kinds) { kind in
                                factRow(kind, isUnmet: unmetKinds.contains(kind))
                                if kind != kinds.last { Divider() }
                            }
                        }
                    }
                    Text("Tap any row to set or change it. Nothing here leaves your device.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $groundingKind) { GroundingSheet(kind: $0) }
        }
    }

    private func factRow(_ kind: GroundingKind, isUnmet: Bool) -> some View {
        let input = model.profile.input(kind)
        let rationale = unmetRequirements.first { $0.kind == kind }?.rationale
        return Button {
            groundingKind = kind
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isUnmet ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(isUnmet ? Color.secondary : Theme.good)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.displayName).font(.subheadline)
                    // A stale value is still the best number available and is
                    // still used — what it has stopped buying is confidence. So
                    // it reads as "worth repeating", never as missing.
                    if let input {
                        Text(input.isFresh()
                             ? kind.formatted(input.value)
                             : "\(kind.formatted(input.value)) · worth repeating")
                            .font(.caption)
                            .foregroundStyle(input.isFresh() ? Color.secondary : Theme.warn)
                    } else if let rationale {
                        Text(rationale)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                // Both branches are `Color`. `.tertiary` here would be a
                // `HierarchicalShapeStyle`, and a ternary whose arms are two
                // different ShapeStyle types has nothing to unify to.
                Image(systemName: isUnmet ? "plus.circle.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(isUnmet ? Theme.accent : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
