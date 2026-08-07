import CoreLocation
import Foundation
import InsightKit
import Observation

/// **The only thing in this app that talks to Core Location.**
///
/// Backlog Q6 / P32. The reader approved this feature *with conditions*, and the
/// conditions are architecture rather than etiquette:
///
/// 1. **An onboarding step that explains why, before any system prompt.**
///    Nothing here calls `requestWhenInUseAuthorization()` on its own — the ask
///    is `requestWhileUsing()` and its only callers are screens that have just
///    finished explaining themselves (`OnboardingLocationStep`, and the feed's
///    own row for a reader who skipped it). **The prompt without the
///    explanation is not what was approved**, and the way to keep that true was
///    to make the prompt something a screen has to go and ask for.
/// 2. **A dismissible front-page suggestion when the permission is absent** —
///    `SuggestionEngine.locationPermission`, which reads `access` below.
///
/// ## What it deliberately does not do
///
/// - **`startUpdatingLocation` is never called.** There is no continuous-updates
///   path, no `allowsBackgroundLocationUpdates`, no deferred updates. Visit
///   monitoring is the coarsest thing Core Location offers — it reports that
///   somebody *stopped somewhere*, not where they went — and it is what this
///   uses.
/// - **Full accuracy is never requested.** `requestTemporaryFullAccuracyAuthorization`
///   is not called anywhere. A reader who has given the app reduced accuracy
///   keeps it, and the app is built to work at that resolution: every fix is
///   rounded to a 250 m cell before it is stored, so precise authorisation would
///   buy nothing it could keep.
/// - **It never asks for Always on its own.** `requestBackgroundVisits()` exists
///   and is called only from a control inside the feed that says plainly what it
///   changes. Onboarding asks for While Using and stops there.
/// - **It stores no timeline.** Two things persist: the capped
///   `PlaceAnchorSet` (see its type comment for why the cap is the privacy
///   control) and, in memory only, the most recent fix waiting to be attached to
///   a flagged event. There is no visit log.
///
/// ## The honest limitation
///
/// With While Using authorisation, iOS delivers visits only while the app is in
/// use. So a stretch flagged at 9pm on a phone in a pocket usually has **no
/// place at all**, and the feed says so (`PlaceContext.unobserved`, and
/// `LocationAccess.whileUsing.sentence`). That is a real gap and it is stated
/// rather than papered over — the alternative was to ask for Always during
/// onboarding, which is a much larger request than the reader agreed to and
/// would have been made before they had ever seen the feature work.
@MainActor
@Observable
final class LocationCapture: NSObject {

    /// One instance. Core Location's delegate callbacks are process-wide and two
    /// managers would double-count every arrival into the anchor set.
    static let shared = LocationCapture()

    /// What the app is currently allowed to observe. Mapped off
    /// `CLAuthorizationStatus` so everything downstream — the feed's empty
    /// state, the suggestion, the onboarding step — reasons about a value
    /// InsightKit can test.
    private(set) var access: LocationAccess = .notAsked

    /// The reader's own anchors. Persisted; capped at
    /// `PlaceAnchorSet.maximumAnchors`.
    private(set) var anchors: PlaceAnchorSet

    /// The most recent fix, **in memory only and never written to disk**.
    ///
    /// It exists to be attached to an event the detector produces in the same
    /// pass. Persisting it would be persisting "where this person was last",
    /// which is a location record with one row — and one row is enough to name
    /// a home.
    private(set) var latestFix: (cell: CoarseCoordinate, at: Date, capture: PlaceCapture)?

    private let manager: CLLocationManager
    private let store: PlaceAnchorStore

    /// How stale a fix may be and still be attached to an event. Beyond this the
    /// event gets `.unobserved` rather than a position from somewhere else
    /// entirely — a map pin two hours and one commute out of date is worse than
    /// no map, because the reader would believe it.
    static let fixFreshnessMinutes: Double = 90

    init(store: PlaceAnchorStore = .standard,
         manager: CLLocationManager = CLLocationManager()) {
        self.store = store
        self.manager = manager
        self.anchors = store.load()
        super.init()
        manager.delegate = self
        // Kilometre accuracy is the coarsest setting Core Location accepts and
        // is four times coarser than the cell anything is stored in — so the
        // rounding is never the only thing standing between the app and a
        // precise position.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        // ⚠️ Never true. Declared here rather than left to the default, so a
        // future edit that wants background updates has to delete a line that
        // says why it should not.
        manager.allowsBackgroundLocationUpdates = false
        refreshAccess()
        startIfAllowed()
    }

    // MARK: - Asking

    /// **The onboarding step's ask.** Only ever called after an explanation.
    ///
    /// Safe to call when it cannot do anything: iOS ignores a second request,
    /// and `access.isWorthAsking` is what the callers gate on so a reader who
    /// already declined is never shown a button that does nothing.
    func requestWhileUsing() {
        guard access.isWorthAsking else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// **A second, separate ask, made only from inside the feed.**
    ///
    /// Never from onboarding. Always authorisation is what lets a visit be
    /// delivered while the app is closed, which is the difference between a
    /// flagged evening having a place and not — but it is a much bigger request
    /// than the one the reader agreed to on the way in, and it is only fair to
    /// make it after they have seen what the feed does without it.
    ///
    /// iOS requires While Using first, so this is a no-op until that is granted.
    func requestBackgroundVisits() {
        guard access == .whileUsing else { return }
        manager.requestAlwaysAuthorization()
    }

    /// Whether the "record places while the app is closed" control should be
    /// offered at all.
    var canUpgradeToBackgroundVisits: Bool { access == .whileUsing }

    // MARK: - Observing

    private func startIfAllowed() {
        guard access.capturesPlaces else { return }
        // ⚠️ Visits, not updates. See the type comment.
        manager.startMonitoringVisits()
    }

    private func stop() {
        manager.stopMonitoringVisits()
        latestFix = nil
    }

    /// One fix, taken because the reader opened the feed.
    ///
    /// The fallback for a `whileUsing` install: without it a reader who never
    /// leaves the app open would never see a place at all. It is a single
    /// `requestLocation` — not a stream — on a screen they opened themselves.
    func takeForegroundFix() {
        guard access.capturesPlaces else { return }
        manager.requestLocation()
    }

    // MARK: - Attaching a place to an event

    /// The place to attach to a freshly detected event, or `.unobserved`.
    ///
    /// ⚠️ **Freshness is checked, not assumed.** A fix from this morning
    /// attached to an evening event would be a map the reader trusts and that is
    /// wrong, which is worse than the honest blank `.unobserved` gives.
    func place(forEventAt start: Date, now: Date = Date()) -> PlaceContext {
        guard access.capturesPlaces, let fix = latestFix else { return .unobserved }
        let age = abs(fix.at.timeIntervalSince(start))
        guard age <= Self.fixFreshnessMinutes * 60 else { return .unobserved }
        _ = now
        return PlaceContext(familiarity: anchors.familiarity(of: fix.cell),
                            coordinate: fix.cell,
                            capture: fix.capture,
                            capturedAt: fix.at)
    }

    // MARK: - Internals

    private func refreshAccess() {
        access = Self.access(for: manager.authorizationStatus)
    }

    /// The one place `CLAuthorizationStatus` is translated.
    ///
    /// `static` and pure so it can be reasoned about without a device: the app
    /// target's tests can call it, and nothing else in the codebase has to know
    /// Core Location's vocabulary.
    static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: return .notAsked
        // Restricted is not the same as denied to the reader — they cannot
        // change it — but it is the same to this app: nothing is captured and
        // asking would achieve nothing. `.unavailable` is the honest word for
        // both, and it is the one case that never produces a suggestion.
        case .restricted: return .unavailable
        case .denied: return .denied
        case .authorizedWhenInUse: return .whileUsing
        case .authorizedAlways: return .always
        @unknown default: return .unavailable
        }
    }

    /// Fold an arrival into the anchors and remember it as the latest fix.
    ///
    /// **Rounded before anything else happens to it.** The precise
    /// `CLLocationCoordinate2D` exists as a local for the length of this
    /// function and is never stored, which is what
    /// `CoarseCoordinate(rounding:...)` having no raw initialiser is there to
    /// guarantee.
    private func record(_ coordinate: CLLocationCoordinate2D, at date: Date,
                        capture: PlaceCapture) {
        // A `CLVisit` with no arrival has a coordinate of (0,0); so does a
        // failed fix. Null Island is not a place anybody has been, and letting
        // it become an anchor would make every real place look unfamiliar.
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return }
        let cell = CoarseCoordinate(rounding: coordinate.latitude,
                                    longitude: coordinate.longitude)
        latestFix = (cell, date, capture)
        anchors = anchors.noting(cell, on: date)
        store.save(anchors)
    }

    /// **Erase every anchor.** Wired to a control in the feed, because a reader
    /// who can be told what the app holds and cannot delete it has been told
    /// about a problem rather than given a choice.
    func forgetAllPlaces() {
        anchors = PlaceAnchorSet()
        latestFix = nil
        store.save(anchors)
    }
}

extension LocationCapture: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let previous = access
            refreshAccess()
            if access.capturesPlaces {
                startIfAllowed()
            } else if previous.capturesPlaces {
                // Permission withdrawn in iOS Settings. Stop, and drop the fix
                // held in memory — continuing to attach places after the reader
                // said no would be the app deciding its old permission still
                // counts.
                stop()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let coordinate = visit.coordinate
        // A visit with a distant-past arrival is a *departure* callback for a
        // place already recorded; using `arrivalDate` keeps the anchor's day
        // right without needing the pair.
        let stamp = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
        Task { @MainActor in
            record(coordinate, at: stamp, capture: .visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = last.coordinate
        let stamp = last.timestamp
        Task { @MainActor in
            record(coordinate, at: stamp, capture: .foregroundFix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        // Deliberately silent. A failed fix means the event gets `.unobserved`,
        // which the feed already renders honestly — an alert here would be the
        // app making a fuss about a feature it has just finished saying is
        // optional.
    }
}
