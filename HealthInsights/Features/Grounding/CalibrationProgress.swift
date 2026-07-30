import SwiftUI
import InsightKit

/// A compact "N of 5 in the last 30 days" progress row for BP grounding.
struct CalibrationProgress: View {
    let status: BloodPressureEstimator.CalibrationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !status.isGrounded {
                ProgressView(value: Double(status.recentReadings),
                             total: Double(status.required))
                    .tint(Theme.accent)
            }
            HStack(spacing: 6) {
                Image(systemName: status.isGrounded ? "checkmark.seal.fill" : "target")
                    .foregroundStyle(status.isGrounded ? Theme.good : Theme.accent)
                Text(status.guidance)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
