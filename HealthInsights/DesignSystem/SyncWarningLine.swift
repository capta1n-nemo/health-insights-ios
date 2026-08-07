import SwiftUI

/// **"Connected" and "reading anything" are two different claims.** Backlog D10.
///
/// The unhappy paths were walked on the simulator on 2026-08-07 and every one
/// of them ended in the same place: a green line saying the source was fine.
///
/// - Apple Health with *Don't Allow* tapped — `requestAuthorization` succeeds
///   either way, because HealthKit tells an app nothing about a read refusal —
///   produced **"Synced 22 seconds ago"**, in `Theme.good`, next to a heart.
/// - An OAuth provider whose grant no longer covers a single collection returns
///   an empty `SyncedData` rather than throwing, so its row said the same.
///
/// `IntegrationStatus` cannot express this. It answers *is it connected*, and
/// in both cases the honest answer to that question is yes. What was missing
/// was the second sentence, and this is it: the status line keeps its meaning,
/// and the silence gets said out loud underneath it.
///
/// ## Amber, and never in place of the status
///
/// `Theme.warn` rather than `Theme.bad`: nothing is broken. The connection
/// holds, the credentials are good, the last sync completed — it simply
/// brought nothing back, and the reader is the only one who can find out why.
/// Drawn *below* the status rather than replacing it, because "connected" is
/// still true and overwriting it would trade one wrong sentence for another.
///
/// Draws nothing when there is nothing to say, so a healthy row is unchanged.
struct SyncWarningLine: View {
    let warning: String?

    /// Take the structured form when there is one, so the row keeps the *what
    /// to do* half that a bare summary drops.
    ///
    /// ⚠️ The action is appended only when `SyncTrouble` supplies one. A `nil`
    /// action means there is nothing the reader can do — a tunnel, a rate limit
    /// — and a row that fills that silence with "try reconnecting" is the thing
    /// this whole area of the app exists to stop.
    init(trouble: SyncTrouble?) {
        warning = trouble.map { t in
            t.action.map { "\(t.summary) \($0)" } ?? t.summary
        }
    }

    init(warning: String?) { self.warning = warning }

    var body: some View {
        if let warning {
            // `HStack(alignment: .top)` rather than `Label`, which centres its
            // icon against the whole block: this text wraps to four or five
            // lines in the width a Settings row has left after its button, and
            // a triangle floating in the middle of that reads as decoration.
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
                    .accessibilityHidden(true)
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(warning)
        }
    }
}
