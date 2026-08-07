import CoreLocation
import InsightKit
import MapKit
import SwiftUI

/// **A circle, never a pin** — the map the reader asked for on a flagged event.
///
/// P32 names a *"GPS map"*, and this is it. What it draws is the cell the fix
/// was rounded to, not the fix: `CoarseCoordinate` threw the precise position
/// away before it was stored, and a pin would assert a precision that no longer
/// exists anywhere. The circle is the honest rendering of a rounded value, and
/// it is the same discipline every dashed line and stated error bar in this app
/// follows — **modelled is never dressed as measured**, and neither is coarsened.
///
/// The caption says the radius out loud for the same reason a departure travels
/// with its reference depth.
struct EventPlaceMap: View {
    let place: PlaceContext

    private var region: MKCoordinateRegion? {
        guard let cell = place.coordinate else { return nil }
        // Framed to about six cells across, so the circle reads as an area
        // inside a neighbourhood rather than filling the frame — which would
        // make a 250 m cell look like a precise dot on a wide view.
        let span = cell.precisionMetres * 6
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: cell.latitude,
                                           longitude: cell.longitude),
            latitudinalMeters: span, longitudinalMeters: span)
    }

    var body: some View {
        if let cell = place.coordinate, let region {
            VStack(alignment: .leading, spacing: 6) {
                Map(initialPosition: .region(region), interactionModes: [.pan, .zoom]) {
                    MapCircle(center: CLLocationCoordinate2D(latitude: cell.latitude,
                                                             longitude: cell.longitude),
                              radius: cell.precisionMetres)
                        .foregroundStyle(Theme.accent.opacity(0.22))
                        .stroke(Theme.accent.opacity(0.7), lineWidth: 1.5)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)

                Text(caption(for: cell))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Says three things the reader would otherwise have to guess: that the
    /// circle is an area rather than a position, when the fix was taken (which
    /// is often *not* when the event was), and that it is about to be deleted.
    private func caption(for cell: CoarseCoordinate) -> String {
        var parts = [String(format: "Anywhere in about %.0f m — the exact spot was never saved.",
                            cell.precisionMetres)]
        if let at = place.capturedAt {
            parts.append("Fix taken \(at.formatted(date: .omitted, time: .shortened)).")
        }
        parts.append("Deleted when you answer, and after \(FlaggedEventRetention.coordinateLifetimeDays) days either way.")
        return parts.joined(separator: " ")
    }
}
