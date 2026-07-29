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
    private let scanner = DocumentScanService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import a blood test").font(.headline)
                        Text("Choose a clear photo of your pathology report. The text is read on your device — nothing is uploaded — and any cholesterol values are pulled out for you to confirm.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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
                        Text("Couldn't find recognised values in that image. Try a sharper, straight-on photo, or add the numbers manually in Settings.")
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
    }

    private func process(_ item: PhotosPickerItem?) {
        guard let item else { return }
        savedMessage = nil
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
