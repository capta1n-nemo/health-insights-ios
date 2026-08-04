import SwiftUI
import PhotosUI
import InsightKit
#if canImport(UIKit)
import UIKit
#endif

/// "Take a photo of your blood test." Pick an image, OCR it on-device, and let
/// the user confirm the values before they're saved as grounding inputs. This is
/// the first slice of the broader "import anything" capability.
struct ImportLabView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var extracted: [LabReportParser.Extracted] = []
    @State private var isProcessing = false
    @State private var processedOnce = false
    @State private var savedMessage: String?
    @State private var isScanning = false
    /// How many pages the last scan carried, so the "nothing found" line can
    /// say what it looked at. Two blank pages and one blank photo are the same
    /// message otherwise, and they are not the same problem.
    @State private var pagesRead = 0
    private let scanner = DocumentScanService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import a blood test").font(.headline)
                        // Leads with scanning, because the button below does.
                        // The prose still said "choose a photo" after the
                        // scanner became the primary action, so it pointed at
                        // the tinted secondary button — spotted in the
                        // simulator on 2026-08-04. Copy that names an action
                        // has to name the one the eye lands on.
                        Text("Scan your pathology report with the camera, or pick a photo you already have. The text is read on your device — nothing is uploaded — and any cholesterol values are pulled out for you to confirm.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // The camera first, the library second: a reader holding the
                // report in their hand is the common case, and until now the
                // only route was to photograph it, leave the app, and come back
                // to pick the photo they had just taken. The system scanner
                // also does the two things a raw camera photo does not — edge
                // detection and perspective correction — and a straight-on,
                // cropped page is exactly what the OCR asks for in the failure
                // message below.
                if DocumentCameraView.isAvailable {
                    Button {
                        savedMessage = nil
                        isScanning = true
                    } label: {
                        Label("Scan the report", systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // The branch is over the view rather than over the argument:
                // `.bordered` and `.borderedProminent` are different concrete
                // types and a ternary between them has nothing to unify to.
                if DocumentCameraView.isAvailable {
                    libraryPicker.buttonStyle(.bordered)
                } else {
                    libraryPicker.buttonStyle(.borderedProminent)
                }

                if isProcessing {
                    HStack { ProgressView(); Text("Reading your report…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity)
                }

                if !extracted.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Found these values").font(.headline)
                            ForEach(extracted, id: \.kind) { value in
                                HStack {
                                    Text(value.kind.displayName)
                                    Spacer()
                                    Text(String(format: "%.1f %@", value.value, value.displayUnit))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button {
                                for value in extracted { model.saveGrounding(kind: value.kind, value: value.value) }
                                savedMessage = "Saved \(extracted.count) value(s) to your profile."
                                extracted = []
                            } label: {
                                Text("Save to my profile").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else if processedOnce && !isProcessing {
                    Card {
                        Text(pagesRead > 1
                             ? "Couldn't find recognised values across those \(pagesRead) pages. Blood-test reports vary — you can add the numbers manually in Settings."
                             : "Couldn't find recognised values in that image. Try a sharper, straight-on photo, or add the numbers manually in Settings.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good).font(.subheadline)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, newItem in process(newItem) }
        .fullScreenCover(isPresented: $isScanning) {
            DocumentCameraView { pages in
                isScanning = false
                process(pages)
            }
        }
    }

    private var libraryPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Choose a photo", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    /// Read a scan's pages and keep the first value found for each kind.
    ///
    /// **All the pages, not the first.** A pathology report runs to several
    /// sheets and the panel this app reads is rarely on the one scanned first;
    /// reading only page one would make a two-page report look unreadable.
    ///
    /// First-found wins per kind, in page order. A report that states a value
    /// twice states it identically — a repeated cholesterol is the summary line
    /// and the table row — so the tie-break only decides which of two equal
    /// numbers is shown, and page order is the one the reader can predict.
    private func process(_ pages: [PlatformImage]) {
        guard !pages.isEmpty else { return }
        savedMessage = nil
        pagesRead = pages.count
        Task {
            isProcessing = true
            defer { isProcessing = false; processedOnce = true }
            var found: [LabReportParser.Extracted] = []
            for page in pages {
                for value in await scanner.extractLabValues(from: page)
                where !found.contains(where: { $0.kind == value.kind }) {
                    found.append(value)
                }
            }
            extracted = found
            if found.isEmpty {
                DiagnosticsLog.shared.null("Import", "Scanned \(pages.count) page(s) — no recognised values")
            } else {
                DiagnosticsLog.shared.ok("Import", "Scanned \(pages.count) page(s) — \(found.count) value(s) found")
            }
        }
    }

    private func process(_ item: PhotosPickerItem?) {
        guard let item else { return }
        savedMessage = nil
        pagesRead = 1
        Task {
            isProcessing = true
            defer { isProcessing = false; processedOnce = true }
            #if canImport(UIKit)
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                extracted = await scanner.extractLabValues(from: image)
                if extracted.isEmpty {
                    DiagnosticsLog.shared.null("Import", "Blood-test photo read — no recognised values")
                } else {
                    DiagnosticsLog.shared.ok("Import", "Blood-test photo read — \(extracted.count) value(s) found")
                }
            } else {
                DiagnosticsLog.shared.fail("Import", "Couldn't load the selected image")
            }
            #endif
        }
    }
}
