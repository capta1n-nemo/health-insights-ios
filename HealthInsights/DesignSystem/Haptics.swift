import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Small, deliberate haptics for actions with no other physical confirmation.
///
/// Copying to the clipboard is the motivating case: the only feedback was a
/// glyph swap that a finger covers.
enum Haptics {
    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

/// A copy button that confirms itself.
///
/// Replaces two hand-rolled copies of the same pattern, both of which reset via
/// an uncancelled detached `Task` — so rapid taps stacked timers and an early
/// one could clear the confirmation while a later tap still looked fresh — and
/// both of which applied `.labelStyle(.iconOnly)`, hiding the word "Copied"
/// they were setting.
struct CopyButton: View {
    let value: String
    var label: String = "Copy"
    var confirmation: String = "Copied!"
    /// How long the confirmation stays up.
    var duration: Duration = .seconds(2)

    @State private var copied = false
    @State private var reset: Task<Void, Never>?

    var body: some View {
        Button {
            #if canImport(UIKit)
            UIPasteboard.general.string = value
            #endif
            Haptics.tap()
            withAnimation { copied = true }
            reset?.cancel()          // a second tap restarts the clock
            reset = Task {
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                withAnimation { copied = false }
            }
        } label: {
            Label(copied ? confirmation : label,
                  systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.footnote)
        }
        .buttonStyle(.bordered)
        .onDisappear { reset?.cancel() }
    }
}
