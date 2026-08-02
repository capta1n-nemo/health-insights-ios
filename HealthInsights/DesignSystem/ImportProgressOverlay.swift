import SwiftUI

/// Shown while a shared file is being read.
///
/// Exists because of what the reader saw without it: sharing a Shotsy backup
/// froze the app for several seconds and then produced a result alert, so the
/// only feedback during the work was an unresponsive screen. A spinner that
/// says what is happening turns the same wait into a progress report.
struct ImportProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading your file…")
                    .font(.callout.weight(.medium))
                Text("Bringing in your injections and measurements, then re-scoring your cards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 260)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        // The reader cannot usefully do anything mid-import, and letting them
        // start a second one would race the first.
        .transition(.opacity)
    }
}
