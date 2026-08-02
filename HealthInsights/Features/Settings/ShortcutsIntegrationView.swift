import SwiftUI
import InsightKit

/// How to build the automation, and what it last delivered.
///
/// Modelled on `ShotsyIntegrationView`: a source the app cannot pull from gets a
/// screen that explains the gesture rather than a Connect button that would do
/// nothing. The difference is that this one is *generative* — the reader is
/// assembling a shortcut, so the screen has to give them the exact URL and be
/// honest that a hand-built thing can be got wrong (which is why the ingest
/// reports what it refused, and this screen shows it).
struct ShortcutsIntegrationView: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    /// The recipe the reader assembles. Deliberately short: a long one does not
    /// get built.
    ///
    /// Step three used to be "paste this address and replace VALUE with the
    /// number from the action above it", which is three chances to get something
    /// wrong in a string with no feedback. The app now ships a **Log health
    /// data** action, so the reader picks the metric from a menu and drops the
    /// variable in the way Shortcuts drops every other variable. The address is
    /// still below, because a shortcut somebody already built has to keep
    /// working.
    private let steps: [(String, String)] = [
        ("Open Shortcuts and make a new shortcut",
         "Name it anything — “Health Insights daily” works."),
        ("Add the actions that fetch what you want",
         "Screen Time needs an app that exposes it as a Shortcuts action. Calendar, weather and battery are all built in — anything that ends in a number can be sent."),
        ("Add “Log health data” as the last action",
         "It's this app's own action — search for it by name. Pick the metric from the menu, then drag the number from the action above into the Value field."),
        ("Automate it",
         "In the Automation tab, run it at a time each day. Turn off “Ask Before Running” so it goes by itself.")
    ]

    /// Built rather than written out. The parser is the only definition of this
    /// format, and a literal here was a second one that could drift from it —
    /// see `ShortcutIngest.urlTemplate`, which is round-tripped against the
    /// parser in `ShortcutURLBuilderTests`.
    private var urlTemplate: String {
        ShortcutIngest.urlTemplate(for: [.screenTimeMinutes])
    }

    var body: some View {
        List {
            Section {
                statusRow
            } header: {
                Text("Status")
            } footer: {
                Text("The app can't ask your shortcut for anything — it runs on your schedule and hands data over. So the honest thing to show is when it last did.")
            }

            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(step.0)").font(.subheadline)
                        Text(step.1).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Set it up")
            }

            Section {
                Text(urlTemplate)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    UIPasteboard.general.string = urlTemplate
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy the address",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("The address")
            } footer: {
                Text("Only needed if you'd rather use “Open URLs” than the app's own action — an old shortcut, or something that can only produce a web address. Add `&stepCount=1234` and so on, one per reading. Send the same day twice and the second replaces the first, so re-running to fix a number is safe. **Anything the app learns to track later works through either route without you changing anything.**")
            }

            Section {
                Text("Screen Time can't be read by any app — Apple sandboxes it deliberately — so a shortcut is the only way it can reach a health app at all. Calendar load is the other one worth collecting: how many hours of meetings a day is a stress signal nothing else here can see.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What's worth collecting")
            }
        }
        .navigationTitle("Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var statusRow: some View {
        if let last = ShortcutsIntegration.lastRunDate {
            LabeledContent("Last run",
                           value: last.formatted(.relative(presentation: .named)))
            if let summary = ShortcutsIntegration.lastRunSummary {
                Text(summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Hasn't run yet. Once your shortcut calls the address below, this will show when it last did and what it carried.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
