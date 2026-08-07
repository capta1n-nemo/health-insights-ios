import Foundation
import InsightKit
#if canImport(PDFKit)
import PDFKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// **Turns a document the reader picked into text, whatever kind of document it
/// is.** Backlog `Q7`: *"both? What do you mean? We should be able to accept all
/// of these."*
///
/// Four routes reach this file — the camera, the system document scanner, the
/// photo library and a PDF — and they collapse to two problems: an image needs
/// OCR (`DocumentScanService`), and a PDF may not.
///
/// ## Why a PDF is read twice
///
/// Most pathology PDFs and every Apple Health ECG export carry a **text layer**,
/// and reading it is strictly better than OCR: the characters are the ones the
/// laboratory wrote rather than the ones a recogniser guessed at, so a `5.2`
/// cannot arrive as `52`. But a PDF that was produced by scanning paper carries
/// no text layer at all — it is a picture in a wrapper.
///
/// So: take the text layer where there is one, render the pages and OCR them
/// where there is not, and **say which happened** (`PDFTextSource`). A value
/// lifted from a text layer has no OCR uncertainty and should not be shown
/// carrying any; a value OCR'd out of a scanned PDF has exactly as much as a
/// photograph and must not be flattered by the file extension.
@MainActor
final class DocumentImportService {

    private let scanner: DocumentScanService

    /// The default is built inside rather than defaulted in the signature:
    /// `DocumentScanService` is `@MainActor`, and a default argument is
    /// evaluated in the caller's context, which is not.
    init(scanner: DocumentScanService? = nil) {
        self.scanner = scanner ?? DocumentScanService()
    }

    /// Where a PDF's text came from.
    enum PDFTextSource {
        /// The PDF's own text layer — the laboratory's characters.
        case textLayer
        /// Rendered and OCR'd, because there was no text layer worth reading.
        case rendered
        /// Neither worked.
        case unreadable
    }

    struct DocumentText {
        let text: String
        let pageCount: Int
        let pdfSource: PDFTextSource?
        /// Whether the characters were recognised rather than read. Drives the
        /// confidence a value from this document can reach.
        var isMachineRecognised: Bool {
            switch pdfSource {
            case .textLayer: return false
            case .rendered, .unreadable, .none: return true
            }
        }
    }

    /// Read a PDF at a URL the reader picked.
    ///
    /// - Important: the caller is responsible for the security-scoped resource
    ///   around this call — a file picked from Files is not readable without it,
    ///   and the failure is a silent empty string rather than an error.
    func readPDF(at url: URL) async -> DocumentText {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            return DocumentText(text: "", pageCount: 0, pdfSource: .unreadable)
        }
        let pageCount = document.pageCount
        var layerText = ""
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            if let string = page.string { layerText += string + "\n" }
        }

        // A text layer of a dozen characters is a watermark, not a report. The
        // threshold is deliberately low: any real pathology page has hundreds.
        if layerText.filter(\.isLetter).count >= 40 {
            return DocumentText(text: layerText, pageCount: pageCount, pdfSource: .textLayer)
        }

        #if canImport(UIKit)
        var recognised = ""
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            guard let image = render(page) else { continue }
            recognised += await scanner.recognizeText(in: image) + "\n"
        }
        if recognised.contains(where: \.isLetter) {
            return DocumentText(text: recognised, pageCount: pageCount, pdfSource: .rendered)
        }
        #endif
        return DocumentText(text: layerText, pageCount: pageCount, pdfSource: .unreadable)
        #else
        return DocumentText(text: "", pageCount: 0, pdfSource: .unreadable)
        #endif
    }

    /// OCR one or more images — a photo, or the pages a scanner returned.
    func readImages(_ pages: [PlatformImage]) async -> DocumentText {
        var text = ""
        for page in pages {
            text += await scanner.recognizeText(in: page) + "\n"
        }
        return DocumentText(text: text, pageCount: pages.count, pdfSource: nil)
    }

    #if canImport(PDFKit) && canImport(UIKit)
    /// Render a page at a scale OCR can read.
    ///
    /// 2x, because a pathology PDF's body text at 1x lands near the resolution
    /// where Vision starts confusing `5` and `S` — and a lab value read as a
    /// letter is dropped silently rather than flagged, which is the one failure
    /// mode with no visible symptom.
    private func render(_ page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale: CGFloat = 2
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.set()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
    #endif
}

/// **Where an imported document's bytes live.**
///
/// An ECG is a picture with metadata around it, and the picture is the part the
/// reader actually wants back — so it is copied into the app's own container
/// rather than referenced where the picker found it. A URL into Files is not a
/// document the app owns: it can be moved, renamed or deleted, and a stored
/// absolute path survives neither a restore nor a reinstall.
///
/// ⚠️ **Nothing here reaches the export.** `HealthDataExport.ecgRecords` carries
/// `attachmentFileName` and never the bytes — see that property for why.
enum DocumentAttachmentStore {

    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            return nil
        }
        let folder = base.appendingPathComponent("ImportedDocuments", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Copy a file in, returning the name it was stored under.
    ///
    /// The name carries a UUID rather than the reader's original file name.
    /// Original names are frequently a person's name and a date of birth — see
    /// `docs/privacy-and-ip.md` — and a file name is the one string that ends up
    /// in crash logs and diagnostics without anybody deciding it should.
    static func store(data: Data, fileExtension: String) -> String? {
        guard let directory else { return nil }
        let name = UUID().uuidString + "." + fileExtension
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func url(for fileName: String) -> URL? {
        directory?.appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        guard let url = url(for: fileName) else { return nil }
        return try? Data(contentsOf: url)
    }
}
