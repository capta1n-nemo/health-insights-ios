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
    ///
    /// - Parameter capturedAt: when the **picture** was taken — `PHAsset
    ///   .creationDate` for a library pick. Deliberately has no default: every
    ///   relative phrase on that screen ("Today", "Last Week") is relative to
    ///   the moment of capture, and this parameter used to be called `now` with
    ///   a `Date()` default, which filed every retrospective screenshot into the
    ///   week it happened to be imported in.
    func extractScreenTime(from image: PlatformImage,
                           capturedAt: Date) async -> ScreenTimeScreenshotParser.Result {
        let text = await recognizeText(in: image)
        return ScreenTimeScreenshotParser.parse(text, capturedAt: capturedAt)
    }

    /// OCR a Week screenshot **and** measure its seven bars, so the week's exact
    /// total can be split across its days.
    ///
    /// The two halves are deliberately separate types: the text half is tested
    /// on Linux in InsightKit, and the pixel half cannot be — see
    /// `ScreenTimeChartReader`.
    func extractScreenTimeWeek(from image: PlatformImage,
                               capturedAt: Date) async -> ScreenTimeWeekScan {
        let result = await extractScreenTime(from: image, capturedAt: capturedAt)
        guard case .week = result.period else {
            return ScreenTimeWeekScan(result: result, barHeights: nil)
        }
        let bars = ScreenTimeChartReader.barHeights(in: image)
        return ScreenTimeWeekScan(result: result, barHeights: bars)
    }
}

/// A Week screenshot's text and its bar geometry together.
struct ScreenTimeWeekScan {
    let result: ScreenTimeScreenshotParser.Result
    /// Seven relative bar heights, or nil where the chart could not be found.
    /// Nil means the week is recorded with no per-day split, never a flat fill.
    let barHeights: [Double]?
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSObject
#endif
