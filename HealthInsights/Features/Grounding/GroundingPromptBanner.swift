import SwiftUI
import InsightKit

/// A dashboard banner listing the grounding facts the models still need. This is
/// the "prompt me for real readings" surface the app is built around.
struct GroundingPromptBanner: View {
    let items: [(requirement: GroundingRequirement, status: RequirementStatus)]
    let onSelect: (GroundingKind) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Improve your insights", systemImage: "checklist")
                    .font(.headline)
                Text("Add a few real readings so predictions stay accurate.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(items.prefix(4), id: \.requirement.kind) { item in
                    Button {
                        onSelect(item.requirement.kind)
                    } label: {
                        HStack {
                            Image(systemName: item.status == .stale ? "clock.arrow.circlepath" : "plus.circle.fill")
                                .foregroundStyle(item.status == .stale ? Theme.warn : Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.requirement.kind.displayName).font(.subheadline)
                                Text(item.requirement.rationale)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if item.status == .stale {
                                Text("Update").font(.caption2).foregroundStyle(Theme.warn)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
