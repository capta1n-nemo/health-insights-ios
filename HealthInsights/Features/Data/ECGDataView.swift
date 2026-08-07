import SwiftUI
import InsightKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(QuickLook)
import QuickLook
#endif

/// **The ECGs the reader has imported** — backlog `I7`.
///
/// ⚠️ **This page shows and it does not interpret.** Every classification here
/// is a quotation carried with `ECGRecord.findingAttribution`, which is a
/// property of the model rather than a string in this file — so a screen that
/// renders a finding somewhere new cannot drop the attribution. There is nothing
/// on this page derived from a waveform, because nothing in this app derives
/// anything from a waveform.
struct ECGDataView: View {
    @Environment(AppModel.self) private var model
    @State private var previewURL: URL?

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.ecgRecords.title,
            entriesHeader: "Recordings",
            entryCount: model.ecgRecords.count,
            emptyHeadline: "No ECGs yet",
            emptyMessage: "Import a photo or PDF of an ECG from Settings ▸ Add or update data. This app keeps and shows a trace; it never interprets one.",
            emptySymbol: "waveform.path.ecg",
            overview: { overview },
            rows: { rows })
        .quickLookPreview($previewURL)
    }

    @ViewBuilder private var overview: some View {
        if !model.ecgRecords.isEmpty {
            Section {
                Text(DataDomain.ecgRecords.summary)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(model.ecgRecords) { record in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.recordedAt.formatted(date: .abbreviated,
                                                     time: record.recordedAtIsExact
                                                        ? .shortened : .omitted))
                    Spacer()
                    Text(record.leads.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !record.recordedAtIsExact {
                    // A date nobody stated must not look like one somebody did.
                    Text("The document did not print a date — this is when you imported it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                HStack(spacing: 10) {
                    if let rate = record.printedAverageHeartRate {
                        Label("\(rate) bpm", systemImage: "heart")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let duration = record.durationSeconds {
                        Label(String(format: "%g sec", duration), systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let device = record.deviceDescription {
                        Text(device).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let finding = record.printedFinding {
                    // ⚠️ The quotation and its attribution, always together. The
                    // attribution comes off the model so it cannot be forgotten
                    // here — see `ECGRecord.findingAttribution`.
                    Text("\u{201C}\(finding)\u{201D}")
                        .font(.subheadline).italic()
                    if let attribution = record.findingAttribution {
                        Text(attribution).font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if let note = record.readerNote, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }

                if let name = record.attachmentFileName,
                   let url = DocumentAttachmentStore.url(for: name),
                   FileManager.default.fileExists(atPath: url.path) {
                    Button {
                        previewURL = url
                    } label: {
                        Label("View the trace", systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    // Said plainly rather than shown as a broken button. The
                    // document is the part the reader actually wanted back.
                    Text("The document itself is no longer on this phone.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .swipeActions {
                Button(role: .destructive) {
                    model.deleteECGRecord(id: record.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
