import SwiftUI
import InsightKit

/// **The home-screen widget, shown inside the app that cannot yet install it.**
///
/// Backlog `D8`. Two jobs, and the second is the one that makes this worth a
/// screen rather than a paragraph in a doc:
///
/// 1. It renders the widget **from the stored snapshot file** — the same file a
///    widget extension will read. So the pipeline is exercised by a person, not
///    only by a test, and a defect in the writing half shows up here as a blank
///    card rather than as a surprise on the day the extension is switched on.
/// 2. It says, in the reader's own words rather than a build log's, **why the
///    widget is not on their home screen** — because "it's coming" and "it is
///    blocked on an Apple Developer Program membership you have not bought" are
///    very different statements, and only one of them is true.
///
/// The second is the same rule `CoverageGate` enforces on the cards: a thing
/// that is missing must say what it is waiting for.
struct WidgetPreviewView: View {
    @Environment(AppModel.self) private var model
    /// Read once per appearance rather than on every redraw — it is a file read,
    /// and a `body` that touches the disk is a defect this app has written down
    /// elsewhere (see `docs/data-conventions.md` on observation).
    @State private var snapshot: WidgetSnapshot?
    @State private var renderedAt = Date()

    var body: some View {
        List {
            previewSection
            statusSection
            rulesSection
        }
        .navigationTitle("Home screen widget")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            renderedAt = Date()
            snapshot = model.storedWidgetSnapshot()
        }
    }

    // MARK: - The widget itself

    @ViewBuilder
    private var previewSection: some View {
        Section {
            if let snapshot {
                VStack(alignment: .leading, spacing: 14) {
                    WidgetChrome(size: .small) {
                        DailyNumberWidgetView(snapshot: snapshot, size: .small, now: renderedAt)
                    }
                    WidgetChrome(size: .medium) {
                        DailyNumberWidgetView(snapshot: snapshot, size: .medium, now: renderedAt)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
            } else {
                // Not a failure state to hide. Nothing has been written yet —
                // which happens on a launch before the first evaluation lands —
                // and saying so is more use than an empty box.
                Label("Nothing written yet. This fills in after the app next works out your \(AppModel.widgetInsight.rawValue) score.",
                      systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("What it would show")
        } footer: {
            Text("Drawn from the same file a widget on your home screen would read — not rebuilt for this screen. If it looks right here, it would look right there.")
        }
    }

    // MARK: - Why it is not on the home screen

    private var statusSection: some View {
        Section {
            LabeledContent("On your home screen") {
                Text(WidgetSnapshotStore.isVisibleToWidgets ? "Ready to add" : "Not yet")
                    .foregroundStyle(.secondary)
            }
            if !WidgetSnapshotStore.isVisibleToWidgets {
                VStack(alignment: .leading, spacing: 8) {
                    blocker("An Apple Developer Program membership",
                            "A widget runs in its own sandbox and can only read this app's data through an App Group. Apple does not let a free personal developer account sign one.")
                    blocker("An Xcode account on the Mac that builds this",
                            "A widget is a second app bundle and needs its own signing profile. The Mac that installs this app onto your phone can't create one until Xcode is signed in there.")
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Why it isn't there yet")
        } footer: {
            Text("Both are outside this app — nothing here is half-built waiting on the other half. Everything the widget needs from the app is already working, which is what the panel above is showing you.")
        }
    }

    private func blocker(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "lock")
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - What it is allowed to say

    private var rulesSection: some View {
        Section {
            rule("It only ever repeats the card.",
                 "The number, the words beside it and the reason for any missing number are copied from your Readiness card. A widget that worked the number out again could disagree with the card it opens.")
            rule("A number never appears on its own.",
                 "Whatever qualifies it — an estimate, thin data, experimental — is shown in the same glance. There is no size of this widget that shows the figure and drops the caveat.")
            rule("It says when the reading is old.",
                 "iOS can leave a widget on screen long after the app last ran. If what's behind the number isn't from today, the widget says so instead of letting it pass as this morning's.")
            rule("Nothing on the lock screen.",
                 "Lock screen widgets are readable by anyone holding your phone. Your health isn't going there by default.")
        } header: {
            Text("What a widget is allowed to show")
        }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
