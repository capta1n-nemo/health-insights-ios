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
    private let steps: [(String, String)] = [
        ("Open Shortcuts and make a new shortcut",
         "Name it anything — “Health Insights daily” works."),
        ("Add the actions that fetch what you want",
         "Screen Time needs an app that exposes it as a Shortcuts action. Calendar, weather and battery are all built in — anything that ends in a number can be sent."),
        ("Add “Open URLs” as the last action",
         "Paste the address below, and replace VALUE with the number from the action above it. Shortcuts will substitute it when it runs."),
        ("Automate it",
         "In the Automation tab, run it at a time each day. Turn off “Ask Before Running” so it goes by itself.")
    ]

    private var urlTemplate: String {
        "healthinsights://shortcut?date=YYYY-MM-DD&\(MetricType.screenTimeMinutes.rawValue)=VALUE"
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
                Text("Any signal this app knows can be sent this way — add `&stepCount=1234`, and so on, one per reading. Send the same day twice and the second replaces the first, so re-running to fix a number is safe. **Anything the app learns to track later works through the same shortcut without you changing it.**")
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
