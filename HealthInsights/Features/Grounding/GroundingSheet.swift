import SwiftUI
import InsightKit

/// Presents the right editor for a grounding kind: blood-pressure kinds open the
/// dated **reading log**; everything else uses the single-value entry sheet.
/// Use this everywhere instead of `GroundingEntryView` directly so cuff BP is
/// always the multi-reading experience.
struct GroundingSheet: View {
    let kind: GroundingKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch kind {
        case .cuffSystolic, .cuffDiastolic:
            NavigationStack {
                BloodPressureLogView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        default:
            GroundingEntryView(kind: kind)
        }
    }
}
