import SwiftUI
import InsightKit

/// **Settings ▸ Privacy ▸ Delete everything** — the wipe, and the four honest
/// sentences that have to go with it.
///
/// Backlog `Q13` (asked and answered "yes") and `AC4` (the constraint on it).
///
/// ## Why the page exists rather than a red row with a confirmation dialog
///
/// A destructive action is only as trustworthy as what it says beforehand, and
/// there are three things this one has to say that will not fit under a button:
///
/// 1. **What goes.** Every record in every one of the app's `@Model` types, and
///    every file it has written — the provider caches, the Today summary, the
///    imported lab and ECG documents, body-scan assets.
/// 2. **What does not, and cannot.** Apple Health's own copy, and any provider's
///    copy at the provider. This app cannot delete another app's records, and a
///    reader who is not told that will delete everything, watch it come back on
///    the next sync, and conclude — correctly, on the evidence in front of them
///    — that the button lied.
/// 3. **The order that makes it stick.** Disconnect the sources first, *then*
///    delete. Stated as an instruction rather than left to be inferred.
///
/// ## And afterwards, a receipt
///
/// `DataStore.DeletionReport` counts every type before it clears it, so the page
/// can show a tally rather than the word "Done". "Everything was deleted" is
/// unfalsifiable; "12 doses, 431 scores, 2 lab results" is something the reader
/// can check against what they remember putting in. On this feature that is the
/// difference between a claim and evidence, and `AC4` exists because the claim
/// had a way of being quietly untrue.
struct DeleteEverythingView: View {
    @Environment(AppModel.self) private var model

    @State private var confirming = false
    @State private var report: DataStore.DeletionReport?

    var body: some View {
        List {
            if let report {
                receipt(report)
            } else {
                whatGoes
                whatStays
                action
            }
        }
        .navigationTitle("Delete everything")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete everything on this phone?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { report = model.deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Anything still connected will sync its own copy "
                 + "back — disconnect it first if you want it gone for good.")
        }
    }

    // MARK: - Before

    private var whatGoes: some View {
        Section {
            row("Everything you typed in",
                "Weights, blood pressures, doses, side effects, supplements, cycle days, "
                    + "holidays, grounding facts and every correction you have made.")
            row("Everything the app worked out",
                "Card scores and their history, predictions and how they turned out, "
                    + "dismissed suggestions, and the Today summary.")
            row("Everything it stored for you",
                "Lab reports and ECGs you imported, body scans and whatever raw capture "
                    + "your retention setting kept, and the cached copies of what your "
                    + "connected devices have sent.")
        } header: {
            Text("What goes")
        } footer: {
            // The guarantee, in the reader's terms rather than the schema's.
            Text("This is driven by the same list the database itself is built from, so it "
                 + "covers every kind of record the app can hold — including any added "
                 + "after this screen was written.")
        }
    }

    private var whatStays: some View {
        Section {
            row("Apple Health", "Health's own copy is not this app's to delete, and this "
                + "app has never written to it. If it is still connected, the next sync "
                + "brings it all back. Delete it in the Health app itself.")
            row("Your connected accounts",
                "A ring or a scale keeps its own history on its own servers. Disconnect "
                    + "each source first — Settings ▸ the source ▸ Disconnect — and then "
                    + "come back here, or you will be deleting a copy.")
            row("Your preferences",
                "Which notifications you switched off, which suggestions you hid, what a "
                    + "body scan is allowed to keep. Settings, not health data.")
        } header: {
            Text("What stays, and why")
        }
    }

    private var action: some View {
        Section {
            Button(role: .destructive) { confirming = true } label: {
                Label("Delete everything", systemImage: "trash")
            }
        } footer: {
            Text("You will be asked once more. There is no undo and no backup — the point "
                 + "of this app is that none of it ever left the phone.")
        }
    }

    // MARK: - After

    @ViewBuilder
    private func receipt(_ report: DataStore.DeletionReport) -> some View {
        Section {
            LabeledContent("Records deleted", value: "\(report.totalRows)")
            LabeledContent("Kinds of record cleared", value: "\(report.typesCleared)")
            LabeledContent("Files removed", value: "\(report.filesRemoved)")
        } header: {
            Text("Done")
        } footer: {
            Text("Counted before deleting, so this is what went rather than what was "
                 + "meant to go.")
        }

        if !report.nonEmpty.isEmpty {
            Section("What had something in it") {
                ForEach(report.nonEmpty, id: \.type) { entry in
                    LabeledContent(Self.readable(entry.type), value: "\(entry.rows)")
                        .monospacedDigit()
                }
            }
        }

        if !report.failures.isEmpty {
            Section {
                ForEach(report.failures, id: \.self) { failure in
                    Text(failure).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Did not delete")
            } footer: {
                Text("Reported rather than swallowed. These records are still on the phone.")
            }
        }

        Section {
            Text("Anything still connected will sync its own copy back the next time the "
                 + "app refreshes. That copy lives at the source, not here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Presentation

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    /// `SideEffectRecord` → "Side effect". The receipt is for the reader, and a
    /// Swift type name is the app talking to itself.
    ///
    /// Derived rather than mapped: a hand-written dictionary from type name to
    /// label is the same hand-written list `AC4` is about, one layer up, and it
    /// would silently fall back to nothing for the next `@Model` added.
    static func readable(_ typeName: String) -> String {
        var trimmed = typeName
        for suffix in ["Record", "Entry"] where trimmed.hasSuffix(suffix) && trimmed != suffix {
            trimmed = String(trimmed.dropLast(suffix.count))
        }
        var words: [String] = []
        var current = ""
        for character in trimmed {
            if character.isUppercase, !current.isEmpty { words.append(current); current = "" }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        guard let first = words.first else { return typeName }
        return ([first] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }
}
