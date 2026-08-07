import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import InsightKit
#if canImport(UIKit)
import UIKit
#endif

/// **Bring a blood test in as a document** — scan it, photograph it, or pick a
/// PDF. Backlog `Q7`, and the reader settled the question it was asked as:
/// *"both? What do you mean? We should be able to accept all of these."*
///
/// Typed entry is the fourth route and lives in `LabResultEntrySheet`, because a
/// reader holding a printout and a reader holding a phone are answering
/// different questions. This screen points at it when a scan comes back
/// unreadable, which is the moment it is most wanted.
///
/// ## What changed on 2026-08-07
///
/// It used to extract two analytes — total and HDL cholesterol — and throw the
/// rest of the page away. It now reads **every** analyte the report prints
/// (`LabReportParser`), names the ones a language model can name and the parser
/// cannot (`LabAnalyteExtractor`, `I6`), and shows each value with **how sure it
/// is that it read the number correctly**.
///
/// ⚠️ **Nothing is saved until the reader taps.** A misread lab value is worse
/// than no lab value, so every candidate is shown with its checks and the reader
/// confirms. The lipids additionally become grounding facts, and only when the
/// reading is not doubtful — see `AppModel.saveLabResults`.
struct ImportLabView: View {
    @Environment(AppModel.self) private var model
    @State private var pickerItem: PhotosPickerItem?
    @State private var candidates: [LabResult] = []
    @State private var isProcessing = false
    @State private var processedOnce = false
    @State private var savedMessage: String?
    @State private var isScanning = false
    @State private var isChoosingFile = false
    @State private var isShowingTypedEntry = false
    /// How many pages the last document carried, so "nothing found" can say what
    /// it looked at. Two blank pages and one blank photo are the same message
    /// otherwise, and they are not the same problem.
    @State private var pagesRead = 0
    /// Whether the on-device model contributed. Shown, because "the app read
    /// nine values" and "the app read nine and a model named two more" are
    /// different claims about where a number came from.
    @State private var modelContributed = false
    /// Set when a PDF's own text layer was used. A value read from characters
    /// the laboratory wrote has no OCR uncertainty, and the reader is told which
    /// kind of reading they are looking at.
    @State private var usedTextLayer = false

    private let scanner = DocumentScanService()
    private let importer = DocumentImportService()
    private let extractor = LabAnalyteExtractor()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import a blood test").font(.headline)
                        Text("Scan your pathology report, pick a photo, or choose a PDF. Every value on it is read on your device — nothing is uploaded — and you confirm each one before it is kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // The camera first: a reader holding the report in their hand is
                // the common case, and the system scanner does the two things a
                // raw photo does not — edge detection and perspective
                // correction, which is exactly what the OCR asks for.
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

                Button {
                    savedMessage = nil
                    isChoosingFile = true
                } label: {
                    Label("Choose a PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if isProcessing {
                    HStack { ProgressView(); Text("Reading your report…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity)
                }

                if !candidates.isEmpty {
                    resultsCard
                } else if processedOnce && !isProcessing {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(pagesRead > 1
                                 ? "Couldn't find any values across those \(pagesRead) pages. Blood-test reports vary."
                                 : "Couldn't find any values in that document. Try a sharper, straight-on photo.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            // The fallback named at the moment it is wanted,
                            // rather than left in Settings for the reader to go
                            // looking for after being told the scan failed.
                            Button("Type the numbers in instead") {
                                isShowingTypedEntry = true
                            }
                        }
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
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.pdf]) { outcome in
            if case .success(let url) = outcome { process(pdf: url) }
        }
        .sheet(isPresented: $isShowingTypedEntry) { LabResultEntrySheet() }
    }

    private var libraryPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Label("Choose a photo", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    @ViewBuilder private var resultsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Found \(candidates.count) value\(candidates.count == 1 ? "" : "s")")
                    .font(.headline)

                if usedTextLayer {
                    Text("Read from the PDF's own text rather than from a picture of it, so these are the characters your laboratory wrote.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if modelContributed {
                    Text("Some names were worked out by the on-device model. Every number was still taken from the document itself and checked against it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                ForEach(candidates) { candidate in
                    LabResultRow(result: candidate, showsChecks: true)
                    Divider()
                }

                if doubtfulCount > 0 {
                    Label("\(doubtfulCount) of these could not be checked out. Compare them against your report before you keep them — the lipids among them will not be used for your heart-risk estimate.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.warn)
                }

                Button {
                    save()
                } label: {
                    Text("Keep these values").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Type them in instead") { isShowingTypedEntry = true }
                    .font(.caption)
            }
        }
    }

    private var doubtfulCount: Int {
        candidates.filter { $0.confidence == .doubtful }.count
    }

    private func save() {
        // Confirmed by the reader's tap. What that confirms is *the reading*,
        // which is why the flag lives on the result and not on the import: a
        // month later this is the only record that a person looked at it.
        let confirmed = candidates.map { candidate in
            LabResult(id: candidate.id, analyte: candidate.analyte, value: candidate.value,
                      unit: candidate.unit, referenceRange: candidate.referenceRange,
                      collectedAt: candidate.collectedAt,
                      collectedAtIsExact: candidate.collectedAtIsExact,
                      source: candidate.source, evidence: candidate.evidence,
                      isConfirmedByReader: true)
        }
        model.saveLabResults(confirmed)
        savedMessage = "Saved \(confirmed.count) value(s)."
        candidates = []
    }

    // MARK: - Reading a document

    private func process(_ pages: [PlatformImage]) {
        guard !pages.isEmpty else { return }
        savedMessage = nil
        pagesRead = pages.count
        Task {
            isProcessing = true
            defer { isProcessing = false; processedOnce = true }
            let document = await importer.readImages(pages)
            await extract(document, source: .documentScan)
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
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                DiagnosticsLog.shared.fail("Import", "Couldn't load the selected image")
                return
            }
            let document = await importer.readImages([image])
            await extract(document, source: .photo)
            #endif
        }
    }

    private func process(pdf url: URL) {
        savedMessage = nil
        Task {
            isProcessing = true
            defer { isProcessing = false; processedOnce = true }
            // ⚠️ A file picked from Files is unreadable without this, and the
            // failure is a silent empty document rather than an error.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let document = await importer.readPDF(at: url)
            pagesRead = document.pageCount
            await extract(document, source: .pdf)
        }
    }

    private func extract(_ document: DocumentImportService.DocumentText,
                         source: LabResultSource) async {
        usedTextLayer = document.pdfSource == .textLayer
        let outcome = await extractor.extract(from: document.text, source: source)
        modelContributed = outcome.modelRan
            && outcome.results.contains { $0.evidence?.method == .onDeviceModel }
        candidates = outcome.results
        for refusal in outcome.refusals {
            DiagnosticsLog.shared.null("Import", "Model proposal refused — \(refusal)")
        }
        if outcome.results.isEmpty {
            DiagnosticsLog.shared.null("Import", "Read \(pagesRead) page(s) — no values found")
        } else {
            DiagnosticsLog.shared.ok("Import", "Read \(pagesRead) page(s) — \(outcome.results.count) value(s) found")
        }
    }
}
