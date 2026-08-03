import SwiftUI
import InsightKit

/// Settings ▸ Body scans — the two matrices.
///
/// The reader's requirement, in their words: *"make it configurable in the
/// settings, for both 'what is used' and 'what is saved' … allow them to
/// granularly select what they want to be used, and separately what they want
/// to be saved."* `BodyScanPolicy` has held that shape — and the
/// `retained ⊆ captured` rule — since the scan engine landed, with nothing
/// reading it, so retention was the app's choice rather than the reader's.
/// This is the screen that hands it over.
///
/// **Two sections rather than one list of tri-state rows.** Use and keep are
/// two questions with different stakes: using the colour frames to find a
/// silhouette leaves nothing behind, keeping them writes a photograph of the
/// reader to disk. A single control per asset would force the two to move
/// together, which is exactly the choice `BodyScanPolicy` exists to unbundle.
///
/// The screen never expresses an impossible state: a keep toggle for something
/// that is not being collected is disabled and says why, and every edit goes
/// back through `BodyScanPolicy`'s own mutators, which normalise. The one place
/// the rule lives is the model.
struct BodyScanSettingsView: View {
    @Environment(AppModel.self) private var model

    private var policy: BodyScanPolicy { model.bodyScanPolicy }

    var body: some View {
        List {
            captureSection
            retentionSection
            consequencesSection
            presetSection
        }
        .navigationTitle("Body scans")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What a scan uses

    private var captureSection: some View {
        Section {
            ForEach(BodyScanAsset.allCases) { asset in
                Toggle(isOn: capturing(asset)) {
                    row(asset, note: asset.isRequiredToMeasure
                        ? "Required — no scan can be taken without it."
                        : nil)
                }
            }
        } header: {
            Text("What a scan uses")
        } footer: {
            Text("Turned off, it is never collected in the first place — not collected and then discarded. Switching one off can only make a scan less accurate, never less private, because nothing here is written to disk unless you also keep it below.")
        }
    }

    // MARK: - What it keeps

    private var retentionSection: some View {
        Section {
            ForEach(BodyScanAsset.allCases) { asset in
                Toggle(isOn: retaining(asset)) {
                    row(asset, note: retentionNote(asset))
                }
                .disabled(!policy.canRetain(asset))
            }
        } header: {
            Text("What is kept afterwards")
        } footer: {
            Text("Keeping the raw data is what lets a later, better version of this app re-measure your old scans instead of asking you to take them again. Measurements themselves are always kept — this is only about the raw capture behind them.")
        }
    }

    /// Why a keep row is unavailable, or what keeping it means. Nil where the
    /// row speaks for itself — a note on every line is a note nobody reads.
    private func retentionNote(_ asset: BodyScanAsset) -> String? {
        if !policy.canRetain(asset) { return "Not collected, so there is nothing to keep." }
        if asset.isIdentifiable { return "Recognisable as you. Kept on this phone only, and off by default." }
        return nil
    }

    // MARK: - What the choices add up to

    /// The derived half of `BodyScanPolicy`, said out loud.
    ///
    /// Both flags are on the model and tested there. A reader who has switched
    /// the silhouette off has made scanning impossible, and finding that out at
    /// the capture screen would be the app keeping a consequence to itself.
    private var consequencesSection: some View {
        Section {
            if !policy.canMeasure {
                Label {
                    Text("No scan can be taken with these settings. The silhouette is what every measurement is a width of.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if !policy.isReparseable {
                Label {
                    Text("Nothing raw is being kept, so a future version cannot re-measure these scans — it would need you to take them again.")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            }
            if policy.canMeasure && policy.isReparseable {
                Label {
                    Text("Scans can be taken, and a future version can re-measure them from what is kept.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        } footer: {
            // Said plainly rather than implied by an empty screen. A settings
            // page that reads as though it is doing something today, when the
            // capture it governs has not been built, is the kind of quiet
            // overclaim this app's honesty rules exist to stop.
            Text("Camera and LiDAR capture is not built yet — these choices apply to the first scan you take. Measurements you type in yourself are unaffected: a tape measure collects none of this.")
        }
    }

    private var presetSection: some View {
        Section {
            Button("Use the recommended settings") {
                model.setBodyScanPolicy(.standard)
            }
            Button("Keep the numbers only") {
                model.setBodyScanPolicy(.numbersOnly)
            }
        } footer: {
            Text("Recommended collects everything and keeps everything except the photographs. Numbers only takes the same scan and keeps none of the raw data behind it.")
        }
    }

    // MARK: - Rows and bindings

    private func row(_ asset: BodyScanAsset, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.displayName)
            Text(asset.purpose)
                .font(.caption).foregroundStyle(.secondary)
            if let note {
                Text(note)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// Both bindings write a whole policy back, so `retained ⊆ captured` is
    /// enforced by the initialiser rather than by this screen remembering to —
    /// switching off a capture takes its retention with it, visibly.
    private func capturing(_ asset: BodyScanAsset) -> Binding<Bool> {
        Binding(get: { policy.captured.contains(asset) },
                set: { model.setBodyScanPolicy(policy.capturing(asset, $0)) })
    }

    private func retaining(_ asset: BodyScanAsset) -> Binding<Bool> {
        Binding(get: { policy.retained.contains(asset) },
                set: { model.setBodyScanPolicy(policy.retaining(asset, $0)) })
    }
}
