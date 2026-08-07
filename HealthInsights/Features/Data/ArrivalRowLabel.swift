import SwiftUI
import InsightKit

/// One "what changed" row's label: the type's name, and — where the sanitiser
/// refused what arrived — what became of it.
///
/// ## Why the note exists (backlog D43, ruled 2026-08-07)
///
/// `AppModel.observeArrivals` records what arrived **before**
/// `partitionedVitals()` sanitises, and that order is deliberate: a metric
/// arriving persistently outside its `plausibleRange` must not look identical to
/// nothing arriving at all, because that is precisely the state that means a
/// device has started sending garbage.
///
/// The cost of the order was this row. A single vitamin A reading outside its
/// range was announced as "New since you last looked" and then dropped, leaving
/// the reader a row pointing at data the app does not hold. The ruling was to
/// keep the sighting and say what happened to it, in the same habit as
/// `CoverageGate`: **name what was withheld rather than going quiet.**
///
/// A `nil` note is the ordinary case and renders exactly the plain `Label` this
/// replaced — including for every raw field, which nothing sanitises and which
/// therefore carries no verdict at all. "Not judged" is not "judged fine", and
/// neither prints a qualifier.
struct ArrivalRowLabel: View {
    let title: String
    let icon: String
    /// `TypeSightingLedger.ArrivalOutcome.rowNote`, or nil.
    let note: String?

    var body: some View {
        // A plain `Label` where there is nothing to add, so the overwhelmingly
        // common row is byte-for-byte the layout it has always had.
        if let note {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(note)
                        .font(.caption2)
                        // Not `Theme.warn`: nothing here is the reader's fault
                        // or their body's, and colouring a provider quirk as a
                        // warning on the Data tab would read as a health
                        // finding. It is a qualifier, so it is styled as one.
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: icon)
            }
            // Read as one sentence rather than as two unrelated strings, since
            // the note is the half that changes what the name means.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) — \(note)")
        } else {
            Label(title, systemImage: icon)
        }
    }
}
