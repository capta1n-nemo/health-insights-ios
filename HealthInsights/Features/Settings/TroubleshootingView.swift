import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A live diagnostic view: every connection attempt, API call and per-metric
/// import the app makes, with a pass / fail / null / info status. Read-only and
/// entirely on-device; helps pin down why a device "won't connect" or why a
/// stat is missing.
struct TroubleshootingView: View {
    @State private var log = DiagnosticsLog.shared
    @State private var filter: DiagnosticsLog.Status?
    @State private var copied = false

    private var shown: [DiagnosticsLog.Entry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.status == filter }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("All").tag(DiagnosticsLog.Status?.none)
                    Text("Passed").tag(DiagnosticsLog.Status?.some(.ok))
                    Text("Failed").tag(DiagnosticsLog.Status?.some(.fail))
                    Text("Empty").tag(DiagnosticsLog.Status?.some(.null))
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("A running record of syncs, API calls and imported data. Nothing here leaves your phone.")
            }

            if shown.isEmpty {
                Section {
                    Text("No activity yet. Pull to refresh on the Today tab, or connect a device, then come back.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(shown) { entry in row(entry) }
                } header: {
                    Text("\(shown.count) event\(shown.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        copyLog()
                    } label: { Label(copied ? "Copied" : "Copy log", systemImage: "doc.on.doc") }
                    Button(role: .destructive) {
                        log.clear()
                    } label: { Label("Clear", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func row(_ entry: DiagnosticsLog.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.status.symbol)
                .foregroundStyle(color(entry.status))
                .font(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(entry.category) · \(entry.date.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ status: DiagnosticsLog.Status) -> Color {
        switch status {
        case .ok: return Theme.good
        case .fail: return Theme.bad
        case .null: return Theme.warn
        case .info: return .secondary
        }
    }

    private func copyLog() {
        #if canImport(UIKit)
        UIPasteboard.general.string = log.exportText()
        #endif
        withAnimation { copied = true }
        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
    }
}
