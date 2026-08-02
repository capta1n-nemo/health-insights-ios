import SwiftUI
import InsightKit

/// The shape of a body, as three ratings rather than one label.
///
/// **The override keeps the estimate on screen beside it**, deliberately. A
/// reader who disagrees with the app is not correcting an error so much as
/// telling it something it could not measure — and a disagreement between what
/// somebody believes about their build and what their numbers say is
/// information, not a conflict to resolve by hiding one side.
struct SomatotypeCard: View {
    let somatotype: Somatotype
    @Binding var override: Somatotype.Component?

    private var shown: Somatotype.Component { override ?? somatotype.dominant }

    var body: some View {
        NestedInsightSection(
            title: "Your build",
            trailing: somatotype.isBalanced && override == nil ? "balanced" : shown.displayName,
            caveat: .computed(.partial, "Estimated from your body fat, lean mass and proportions — the published method needs calipers, so these are approximations of it.")
        ) {
            bars
            Text(shown.meaning)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if somatotype.isBalanced && override == nil {
                Text("Two of these are close enough that naming one would be overstating it — most people are mixtures, and yours is a genuine blend.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            overrideRow
        }
    }

    private var bars: some View {
        VStack(spacing: 6) {
            ForEach(Somatotype.Component.allCases) { component in
                HStack(spacing: 8) {
                    Text(component.displayName)
                        .font(.caption)
                        .frame(width: 78, alignment: .leading)
                    GeometryReader { geometry in
                        let rating = somatotype.rating(component)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(component == shown ? Theme.accent : Color.secondary.opacity(0.45))
                                // 1–7 is the scale the method defines, so the
                                // bar is drawn against it rather than against
                                // whichever rating happens to be largest.
                                .frame(width: geometry.size.width * (rating - 1) / 6)
                        }
                    }
                    .frame(height: 8)
                    Text(String(format: "%.1f", somatotype.rating(component)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private var overrideRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set it yourself")
                .font(.caption.weight(.medium))
            Picker("Body type", selection: $override) {
                Text("Use the estimate").tag(Somatotype.Component?.none)
                ForEach(Somatotype.Component.allCases) { component in
                    Text(component.displayName).tag(Somatotype.Component?.some(component))
                }
            }
            .pickerStyle(.menu)
            if override != nil {
                Text("Showing your choice. The estimate above is still drawn from your measurements — where the two disagree, that difference is worth knowing.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
