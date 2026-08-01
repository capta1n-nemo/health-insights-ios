import SwiftUI
import InsightKit

/// Where one heart-rate-recovery reading sits against the two marks that mean
/// something: the published cut-point and the typical wrist-device figure.
///
/// ## Why a line and not a dial
///
/// A dial implies a score, and there is no validated 0–100 curve for heart rate
/// recovery — inventing one to put beside a number the reader is asked to trust
/// is what this codebase refuses everywhere else. A position on a line makes one
/// claim only: here is your reading, here are the two published marks, this is
/// where it falls between them.
///
/// ## Why the marks are labelled and the bands are not
///
/// Shading a red zone below 12 would read as a diagnosis. The cut-point is a
/// population hazard ratio from a cohort study — a fall of 12 beats or fewer
/// marked roughly double the six-year mortality across 2 428 adults — and one
/// reading after one workout says nothing about one person. The tick is drawn,
/// named and left to speak for itself.
struct RecoveryScale: View {
    let bpm: Double

    /// Fixed, not fitted to the reading. An axis that rescales around whatever
    /// was measured moves the published marks from one visit to the next, and
    /// the marks are the only fixed thing on this chart.
    private let upper = 50.0

    private var fraction: Double { min(1, max(0, bpm / upper)) }
    private var cutPoint: Double { HeartResponseModel.attenuatedRecovery / upper }
    private var typical: Double { HeartResponseModel.typicalRecovery / upper }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(bpm <= HeartResponseModel.attenuatedRecovery
                              ? Theme.warn : Theme.good)
                        .frame(width: max(3, width * fraction))
                    mark(at: cutPoint, in: width)
                    mark(at: typical, in: width)
                }
            }
            .frame(height: 8)

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    label("12", at: cutPoint, in: width)
                    label("26", at: typical, in: width)
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate recovery \(Int(bpm)) beats. "
            + "The published mark is 12 and around 26 is typical.")
    }

    private func mark(at position: Double, in width: CGFloat) -> some View {
        Rectangle()
            .fill(Color(.systemBackground))
            .frame(width: 2, height: 12)
            .offset(x: width * position - 1)
    }

    private func label(_ text: String, at position: Double, in width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.tertiary)
            .offset(x: max(0, width * position - 6))
    }
}
