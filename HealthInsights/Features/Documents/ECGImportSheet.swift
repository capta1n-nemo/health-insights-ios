import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import InsightKit
#if canImport(UIKit)
import UIKit
#endif

/// **Import an ECG. Store it. Show it. Never interpret it.** Backlog `I7`.
///
/// ⚠️ **The line this screen does not cross.** Reading a trace and saying what
/// it shows is a regulated medical-device claim. So this sheet takes a photo, a
/// PDF or a scan; reads the metadata *printed around* the trace; quotes any
/// classification the **recording device or a clinician** put on the document,
/// with the attribution attached; and stops. There is no field for a conclusion
/// the app reached, because `ECGRecord` has none and `ECGFindingProvenance` has
/// no case for one.
///
/// Everything transcribed is editable before it is saved. An OCR'd date is a
/// guess about when this happened, and a wrong one files a trace against the
/// wrong week of everything else the reader has.
struct ECGImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var isScanning = false
    @State private var isChoosingFile = false
    @State private var isReading = false
    @State private var hasDocument = false

    // The transcription, held as editable state so the reader has the last word.
    @State private var recordedAt = Date()
    @State private var recordedAtIsExact = false
    @State private var source: ECGSource = .photo
    @State private var leads: ECGLeadConfiguration = .unstated
    @State private var averageHeartRate = ""
    @State private var durationSeconds = ""
    @State private var device = ""
    @State private var printedFinding = ""
    @State private var findingProvenance: ECGFindingProvenance = .recordingDevice
    @State private var readerNote = ""
    @State private var pageCount = 1
    @State private var attachmentFileName: String?
    @State private var transcription: ECGTranscriptionEvidence?
    @State private var message: String?

    private let importer = DocumentImportService()
    private let scanner = DocumentScanService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Bring in an ECG from your watch, your GP or a hospital. The date and any details printed on it are read on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                    // ⚠️ Said before anything is imported, not buried in a
                    // footnote afterwards. Somebody importing a heart trace into
                    // a health app has a reasonable expectation that the app
                    // will tell them something about it, and this is where that
                    // expectation is corrected.
                    Label("This app does not read or interpret an ECG. It keeps yours with the rest of your data and shows you what the device or your clinician already printed on it.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Choose the document") {
                    if DocumentCameraView.isAvailable {
                        Button {
                            isScanning = true
                        } label: {
                            Label("Scan it", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        isChoosingFile = true
                    } label: {
                        Label("Choose a PDF", systemImage: "doc.richtext")
                    }
                    if isReading {
                        HStack { ProgressView(); Text("Reading the document…") }
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if hasDocument {
                    Section {
                        DatePicker("Recorded", selection: $recordedAt)
                            .onChange(of: recordedAt) { _, _ in recordedAtIsExact = true }
                        Picker("Leads", selection: $leads) {
                            ForEach(ECGLeadConfiguration.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        HStack {
                            Text("Average heart rate")
                            Spacer()
                            TextField("—", text: $averageHeartRate)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 70)
                            Text("bpm").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Duration")
                            Spacer()
                            TextField("—", text: $durationSeconds)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 70)
                            Text("sec").font(.caption).foregroundStyle(.secondary)
                        }
                        TextField("Device", text: $device)
                    } header: {
                        Text("What the document says")
                    } footer: {
                        if let transcription, !transcription.absentFields.isEmpty {
                            // Named absences rather than blank rows: "the
                            // document did not print a duration" and "the app
                            // failed to read one" look identical otherwise.
                            Text("The document did not print: "
                                 + transcription.absentFields.map(\.displayName)
                                    .joined(separator: ", ").lowercased()
                                 + ". Fill anything in that you know.")
                        }
                    }

                    Section {
                        TextField("As printed on the document", text: $printedFinding)
                        Picker("Who said it", selection: $findingProvenance) {
                            ForEach(ECGFindingProvenance.allCases) { option in
                                Text(option.shortLabel).tag(option)
                            }
                        }
                    } header: {
                        Text("Printed classification")
                    } footer: {
                        Text(findingProvenance.attribution)
                    }

                    Section {
                        TextField("How you felt, what you were told", text: $readerNote,
                                  axis: .vertical)
                            .lineLimit(2...5)
                    } header: {
                        Text("Your note")
                    }
                }
            }
            .navigationTitle("Import an ECG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!hasDocument)
                }
            }
            .fullScreenCover(isPresented: $isScanning) {
                DocumentCameraView { pages in
                    isScanning = false
                    read(pages: pages, source: .documentScan)
                }
            }
            .fileImporter(isPresented: $isChoosingFile,
                          allowedContentTypes: [.pdf]) { outcome in
                switch outcome {
                case .success(let url): read(pdf: url)
                case .failure: message = "That file could not be opened."
                }
            }
            .onChange(of: pickerItem) { _, item in read(photo: item) }
        }
    }

    // MARK: - Reading

    private func read(pages: [PlatformImage], source: ECGSource) {
        guard !pages.isEmpty else { return }
        Task {
            isReading = true
            defer { isReading = false }
            let document = await importer.readImages(pages)
            #if canImport(UIKit)
            // The first page is the one worth keeping — an ECG's trace is on it,
            // and storing every page of a multi-page printout as separate JPEGs
            // with no way to see them in order would be storage without a view.
            if let data = pages.first?.jpegData(compressionQuality: 0.9) {
                attachmentFileName = DocumentAttachmentStore.store(data: data,
                                                                   fileExtension: "jpg")
            }
            #endif
            apply(document, source: source)
        }
    }

    private func read(photo item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            isReading = true
            defer { isReading = false }
            #if canImport(UIKit)
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                message = "That image could not be loaded."
                return
            }
            attachmentFileName = DocumentAttachmentStore.store(data: data,
                                                               fileExtension: "jpg")
            let document = await importer.readImages([image])
            apply(document, source: .photo)
            #endif
        }
    }

    private func read(pdf url: URL) {
        Task {
            isReading = true
            defer { isReading = false }
            // ⚠️ A file picked from Files is unreadable without this, and the
            // failure is a silent empty document rather than an error.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                attachmentFileName = DocumentAttachmentStore.store(data: data,
                                                                   fileExtension: "pdf")
            }
            let document = await importer.readPDF(at: url)
            apply(document, source: .pdf)
        }
    }

    private func apply(_ document: DocumentImportService.DocumentText, source: ECGSource) {
        self.source = source
        pageCount = max(document.pageCount, 1)
        hasDocument = true
        guard document.text.contains(where: \.isLetter) else {
            message = "No text could be read from that document. You can still save it and fill the details in yourself."
            transcription = nil
            return
        }
        let parsed = ECGMetadataParser.parse(document.text)
        transcription = parsed.evidence
        if let date = parsed.recordedAt {
            recordedAt = date
            recordedAtIsExact = true
        }
        leads = parsed.leads
        averageHeartRate = parsed.averageHeartRate.map(String.init) ?? ""
        durationSeconds = parsed.durationSeconds.map { String(format: "%g", $0) } ?? ""
        device = parsed.device ?? ""
        printedFinding = parsed.printedFinding ?? ""
        findingProvenance = parsed.findingProvenance ?? .recordingDevice
        message = nil
        DiagnosticsLog.shared.ok("Import", "ECG document read — \(parsed.evidence.matchedLines.count) metadata line(s)")
    }

    private func save() {
        let finding = printedFinding.trimmingCharacters(in: .whitespaces)
        let record = ECGRecord(
            recordedAt: recordedAt,
            recordedAtIsExact: recordedAtIsExact,
            source: source,
            leads: leads,
            durationSeconds: Double(durationSeconds),
            printedAverageHeartRate: Int(averageHeartRate),
            deviceDescription: device.isEmpty ? nil : device,
            printedFinding: finding.isEmpty ? nil : finding,
            // The provenance is only stored where there is something to
            // attribute — an attribution with nothing attached would be a
            // dangling claim.
            findingProvenance: finding.isEmpty ? nil : findingProvenance,
            readerNote: readerNote.isEmpty ? nil : readerNote,
            pageCount: pageCount,
            attachmentFileName: attachmentFileName,
            transcription: transcription)
        model.saveECGRecord(record)
        dismiss()
    }
}
