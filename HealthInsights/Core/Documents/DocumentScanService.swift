import Foundation
import InsightKit
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The first "take a photo of anything" capability: on-device OCR of a document
/// image (a blood-test report today) followed by structured extraction of values
/// the app understands. Everything runs on-device via Apple's Vision framework —
/// no upload, no cloud.
///
/// The structured extraction itself lives in `InsightKit.LabReportParser` (pure,
/// unit-tested); this service just turns an image into text and hands it over.
@MainActor
final class DocumentScanService {

    /// Recognise text in an image using on-device Vision OCR.
    func recognizeText(in image: PlatformImage) async -> String {
        #if canImport(Vision) && canImport(UIKit)
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { continuation.resume(returning: "") }
            }
        }
        #else
        return ""
        #endif
    }

    /// OCR an image, then extract recognised lab values for user confirmation.
    func extractLabValues(from image: PlatformImage) async -> [LabReportParser.Extracted] {
        let text = await recognizeText(in: image)
        return LabReportParser.extract(from: text)
    }

    /// OCR a screenshot of Settings ▸ Screen Time.
    ///
    /// The second thing the camera can read, and the one that exists because
    /// there is no other way in: Apple sandboxes the Screen Time API so no app
    /// can query it, while a picture of the screen carries the exact figures.
    /// The classification of *which* figure is which lives in
    /// `ScreenTimeScreenshotParser`, where it is tested — a daily average read
    /// as a day's total would quietly bias everything compared against it.
    func extractScreenTime(from image: PlatformImage,
                           now: Date = Date()) async -> ScreenTimeScreenshotParser.Result {
        let text = await recognizeText(in: image)
        return ScreenTimeScreenshotParser.parse(text, now: now)
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSObject
#endif
